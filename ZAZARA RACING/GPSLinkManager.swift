//
//  GPSLinkManager.swift
//  ZAZARA RACING
//
//  CoreBluetooth pairing, saved modules and live link health.
//

import Combine
import CoreBluetooth
import Foundation

// MARK: - Models

struct SavedGPSModule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var lastLinkedAt: Date

    var lastLinkedDateText: String {
        Self.dateFormatter.string(from: lastLinkedAt).uppercased()
    }

    var lastLinkedTimeText: String {
        Self.timeFormatter.string(from: lastLinkedAt)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct DiscoveredGPSModule: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int?
    var lastSeen: Date
}

enum GPSLinkState: Equatable {
    case idle
    case connecting(moduleID: UUID, name: String)
    case connected
}

struct GPSLinkAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Manager

final class GPSLinkManager: NSObject, ObservableObject {
    // MARK: Published state

    @Published private(set) var linkState: GPSLinkState = .idle
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var authorization: CBManagerAuthorization = .notDetermined
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredModules: [DiscoveredGPSModule] = []
    @Published private(set) var savedModules: [SavedGPSModule] = []
    @Published private(set) var connectedModule: SavedGPSModule?
    @Published private(set) var connectedRSSI: Int?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var linkEventID = 0
    @Published private(set) var alert: GPSLinkAlert?

    // MARK: Computed state

    var isConnected: Bool {
        linkState == .connected
    }

    var isConnecting: Bool {
        if case .connecting = linkState { return true }
        return false
    }

    var connectedSignalLevel: Int {
        Self.signalLevel(for: connectedRSSI)
    }

    var connectedSignalLabel: String {
        Self.signalLabel(for: connectedRSSI)
    }

    // MARK: Private state

    private var central: CBCentralManager?
    private var activePeripheral: CBPeripheral?
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingModule: SavedGPSModule?
    private var wantsScan = false
    private var isReconnectScan = false
    private var isResolvingConnection = false
    private var intentionalDisconnect = false
    private var connectTimeout: Timer?
    private var rssiTimer: Timer?

    private let defaults: UserDefaults
    private let persistenceKey = "zazara.savedGPSModules.v1"
    private let maximumSavedModules = 12
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")

    // MARK: Init

    override init() {
        defaults = .standard
        super.init()
        loadSavedModules()
    }

    deinit {
        connectTimeout?.invalidate()
        rssiTimer?.invalidate()
    }

    // MARK: Scanning

    func startScan() {
        clearAlert()

        guard linkState == .idle else { return }

        ensureCentral()
        wantsScan = true

        guard let state = central?.state else { return }

        switch state {
        case .poweredOn:
            beginScan(clearResults: true)
        case .unknown:
            // The system may still be presenting the Bluetooth permission prompt.
            isScanning = true
            discoveredModules = []
        default:
            isScanning = false
        }
    }

    func stopScan() {
        wantsScan = false
        isScanning = false
        central?.stopScan()
    }

    private func beginScan(clearResults: Bool) {
        guard let central, central.state == .poweredOn else { return }

        if clearResults {
            discoveredModules = []
            knownPeripherals = [:]
        }

        central.stopScan()
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    // MARK: Linking

    func connect(_ module: DiscoveredGPSModule) {
        connect(
            SavedGPSModule(
                id: module.id,
                name: module.name,
                lastLinkedAt: Date()
            )
        )
    }

    func connect(_ module: SavedGPSModule) {
        guard linkState == .idle else { return }

        clearAlert()
        ensureCentral()

        pendingModule = module
        isResolvingConnection = false
        linkState = .connecting(moduleID: module.id, name: module.name)
        startConnectTimeout()

        guard let state = central?.state else { return }

        switch state {
        case .poweredOn:
            beginConnectionAttempt()
        case .unknown:
            // Wait for centralManagerDidUpdateState to finish powering up.
            break
        case .unauthorized:
            failConnection(
                title: l10n.t("Bluetooth access required"),
                message: l10n.t("Allow Bluetooth access in Settings, then try linking your GPS module again.")
            )
        case .poweredOff:
            failConnection(
                title: l10n.t("Bluetooth is off"),
                message: l10n.t("Turn on Bluetooth, then try linking your GPS module again.")
            )
        case .unsupported:
            failConnection(
                title: l10n.t("Bluetooth unavailable"),
                message: l10n.t("This device can’t connect to Bluetooth LE modules.")
            )
        case .resetting:
            failConnection(
                title: l10n.t("Bluetooth resetting"),
                message: l10n.t("Give Bluetooth a moment, then try again.")
            )
        @unknown default:
            failConnection(
                title: l10n.t("Bluetooth unavailable"),
                message: l10n.t("Bluetooth is not ready. Try again in a moment.")
            )
        }
    }

    func cancelConnection() {
        guard case .connecting = linkState else { return }

        connectTimeout?.invalidate()
        connectTimeout = nil
        central?.stopScan()
        wantsScan = false
        isScanning = false
        isReconnectScan = false
        isResolvingConnection = false
        pendingModule = nil

        if let peripheral = activePeripheral {
            intentionalDisconnect = true
            peripheral.delegate = nil
            central?.cancelPeripheralConnection(peripheral)
            activePeripheral = nil
        }

        linkState = .idle
    }

    func disconnect() {
        guard isConnected else { return }

        clearAlert()
        intentionalDisconnect = true
        connectTimeout?.invalidate()
        connectTimeout = nil
        stopSignalPolling()

        if let peripheral = activePeripheral {
            peripheral.delegate = nil
            central?.cancelPeripheralConnection(peripheral)
        }

        activePeripheral = nil
        pendingModule = nil
        isResolvingConnection = false
        isReconnectScan = false
        isScanning = false
        wantsScan = false
        connectedModule = nil
        connectedRSSI = nil
        batteryLevel = nil
        linkState = .idle
    }

    private func beginConnectionAttempt() {
        guard
            !isResolvingConnection,
            let central,
            central.state == .poweredOn,
            let module = pendingModule,
            case .connecting = linkState
        else { return }

        isResolvingConnection = true
        wantsScan = false
        isScanning = false
        central.stopScan()

        if let peripheral = knownPeripherals[module.id]
            ?? central.retrievePeripherals(withIdentifiers: [module.id]).first {
            openConnection(to: peripheral)
            return
        }

        // The module has been saved before but is not cached by the system.
        // Scan quietly until it advertises, or until the link timeout fires.
        isReconnectScan = true
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func openConnection(to peripheral: CBPeripheral) {
        guard let central, central.state == .poweredOn else {
            failConnection(
                title: l10n.t("Bluetooth not ready"),
                message: l10n.t("Turn on Bluetooth and try linking again.")
            )
            return
        }

        isReconnectScan = false
        central.stopScan()
        isScanning = false

        activePeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    private func startConnectTimeout() {
        connectTimeout?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard case let .connecting(_, name) = self.linkState else { return }

            self.failConnection(
                title: self.l10n.t("Link timed out"),
                message: self.l10n.t("%@ didn’t respond. Power the module on, keep it close, and try again.", name)
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        connectTimeout = timer
    }

    private func failConnection(title: String, message: String) {
        guard case .connecting = linkState else { return }

        connectTimeout?.invalidate()
        connectTimeout = nil
        central?.stopScan()
        wantsScan = false
        isScanning = false
        isReconnectScan = false
        isResolvingConnection = false
        pendingModule = nil

        if let peripheral = activePeripheral {
            intentionalDisconnect = true
            peripheral.delegate = nil
            central?.cancelPeripheralConnection(peripheral)
            activePeripheral = nil
        }

        linkState = .idle
        alert = GPSLinkAlert(title: title, message: message)
    }

    // MARK: Saved modules

    func forget(_ module: SavedGPSModule) {
        savedModules.removeAll { $0.id == module.id }
        persistSavedModules()
    }

    func clearSavedRecords() {
        savedModules.removeAll()
        persistSavedModules()
    }

    func dismissAlert() {
        alert = nil
    }

    private func recordLink(id: UUID, name: String) -> SavedGPSModule {
        let module = SavedGPSModule(id: id, name: name, lastLinkedAt: Date())

        savedModules.removeAll { $0.id == id }
        savedModules.insert(module, at: 0)
        if savedModules.count > maximumSavedModules {
            savedModules = Array(savedModules.prefix(maximumSavedModules))
        }

        persistSavedModules()
        return module
    }

    private func loadSavedModules() {
        guard
            let data = defaults.data(forKey: persistenceKey),
            let decoded = try? JSONDecoder().decode([SavedGPSModule].self, from: data)
        else { return }

        savedModules = decoded.sorted { $0.lastLinkedAt > $1.lastLinkedAt }
    }

    private func persistSavedModules() {
        guard let data = try? JSONEncoder().encode(savedModules) else { return }
        defaults.set(data, forKey: persistenceKey)
    }

    // MARK: Signal polling

    private func startSignalPolling() {
        stopSignalPolling()
        activePeripheral?.readRSSI()

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.activePeripheral?.readRSSI()
        }
        RunLoop.main.add(timer, forMode: .common)
        rssiTimer = timer
    }

    private func stopSignalPolling() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    // MARK: Helpers

    private func ensureCentral() {
        guard central == nil else { return }

        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        bluetoothState = central?.state ?? .unknown
        authorization = CBManager.authorization
    }

    private func displayName(
        for peripheral: CBPeripheral,
        advertisementData: [String: Any]? = nil
    ) -> String {
        if let localName = advertisementData?[CBAdvertisementDataLocalNameKey] as? String {
            let cleaned = localName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(32))
            }
        }

        if let name = peripheral.name {
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return String(cleaned.prefix(32))
            }
        }

        if let pendingModule, pendingModule.id == peripheral.identifier {
            return pendingModule.name
        }

        if let saved = savedModules.first(where: { $0.id == peripheral.identifier }) {
            return saved.name
        }

        let suffix = peripheral.identifier.uuidString.prefix(4).uppercased()
        return "GPS Module \(suffix)"
    }

    private func clearAlert() {
        if alert != nil {
            alert = nil
        }
    }

    private var l10n: AppSettings { .shared }

    static func signalLevel(for rssi: Int?) -> Int {
        guard let rssi, rssi < 0 else { return 0 }

        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -78 { return 2 }
        return 1
    }

    static func signalLabel(for rssi: Int?) -> String {
        switch signalLevel(for: rssi) {
        case 4: return "Excellent"
        case 3: return "Good"
        case 2: return "Fair"
        case 1: return "Weak"
        default: return "Measuring"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension GPSLinkManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        authorization = CBManager.authorization

        switch central.state {
        case .poweredOn:
            if case .connecting = linkState, pendingModule != nil {
                beginConnectionAttempt()
            } else if wantsScan, linkState == .idle {
                beginScan(clearResults: true)
            }

        case .poweredOff, .unauthorized, .unsupported, .resetting:
            if isScanning {
                isScanning = false
                central.stopScan()
            }
            wantsScan = false

            if isConnecting {
                let title: String
                let message: String
                switch central.state {
                case .unauthorized:
                    title = l10n.t("Bluetooth access required")
                    message = l10n.t("Allow Bluetooth access in Settings to link your GPS module.")
                case .poweredOff:
                    title = l10n.t("Bluetooth is off")
                    message = l10n.t("Turn on Bluetooth, then try linking again.")
                case .unsupported:
                    title = l10n.t("Bluetooth unavailable")
                    message = l10n.t("This device can’t connect to Bluetooth LE modules.")
                default:
                    title = l10n.t("Bluetooth resetting")
                    message = l10n.t("Give Bluetooth a moment, then try again.")
                }
                failConnection(title: title, message: message)
            }

            if isConnected {
                let name = connectedModule?.name ?? l10n.t("Your GPS module")
                stopSignalPolling()
                activePeripheral?.delegate = nil
                activePeripheral = nil
                connectedModule = nil
                connectedRSSI = nil
                batteryLevel = nil
                linkState = .idle
                alert = GPSLinkAlert(
                    title: l10n.t("Link lost"),
                    message: l10n.t("%@ disconnected because Bluetooth is unavailable. Reconnect to continue.", name)
                )
            }

        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let identifier = peripheral.identifier
        let name = displayName(for: peripheral, advertisementData: advertisementData)

        // This is the module the user asked us to reconnect to.
        if let pendingModule,
           pendingModule.id == identifier,
           case .connecting = linkState {
            knownPeripherals[identifier] = peripheral

            if activePeripheral == nil {
                openConnection(to: peripheral)
            }
            return
        }

        knownPeripherals[identifier] = peripheral

        guard isScanning else { return }

        let rawRSSI = RSSI.intValue
        let reading: Int? = rawRSSI == 127 ? nil : rawRSSI

        if let index = discoveredModules.firstIndex(where: { $0.id == identifier }) {
            discoveredModules[index].name = name
            discoveredModules[index].rssi = reading
            discoveredModules[index].lastSeen = Date()
        } else {
            discoveredModules.append(
                DiscoveredGPSModule(
                    id: identifier,
                    name: name,
                    rssi: reading,
                    lastSeen: Date()
                )
            )
        }

        discoveredModules.sort {
            ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeout?.invalidate()
        connectTimeout = nil
        central.stopScan()

        isScanning = false
        wantsScan = false
        isReconnectScan = false
        isResolvingConnection = false
        intentionalDisconnect = false

        activePeripheral = peripheral
        peripheral.delegate = self

        let name = displayName(for: peripheral)
        let module = recordLink(id: peripheral.identifier, name: name)
        let cachedRSSI = discoveredModules.first(where: { $0.id == peripheral.identifier })?.rssi
        discoveredModules.removeAll()

        pendingModule = nil
        connectedModule = module
        connectedRSSI = cachedRSSI
        batteryLevel = nil
        linkState = .connected
        linkEventID += 1

        startSignalPolling()
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard isConnecting else { return }

        let name = pendingModule?.name ?? displayName(for: peripheral)
        failConnection(
            title: l10n.t("Link failed"),
            message: l10n.t("Couldn’t establish a link with %@. Move closer and try again.", name)
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let wasConnected = isConnected
        let wasConnecting = isConnecting
        let wasIntentional = intentionalDisconnect
        let name = connectedModule?.name
            ?? pendingModule?.name
            ?? displayName(for: peripheral)

        intentionalDisconnect = false
        connectTimeout?.invalidate()
        connectTimeout = nil
        stopSignalPolling()

        isResolvingConnection = false
        isReconnectScan = false
        isScanning = false
        wantsScan = false
        pendingModule = nil

        if activePeripheral?.identifier == peripheral.identifier {
            activePeripheral = nil
        }
        peripheral.delegate = nil

        connectedModule = nil
        connectedRSSI = nil
        batteryLevel = nil

        if wasConnected || wasConnecting {
            linkState = .idle
        }

        if !wasIntentional {
            if wasConnected {
                alert = GPSLinkAlert(
                    title: l10n.t("Link lost"),
                    message: l10n.t("%@ disconnected. Power the module on and link again.", name)
                )
            } else if wasConnecting {
                alert = GPSLinkAlert(
                    title: l10n.t("Link interrupted"),
                    message: l10n.t("The connection to %@ was interrupted. Try linking again.", name)
                )
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension GPSLinkManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard
            peripheral == activePeripheral,
            error == nil,
            let batteryService = peripheral.services?.first(where: { $0.uuid == batteryServiceUUID })
        else { return }

        peripheral.discoverCharacteristics([batteryLevelUUID], for: batteryService)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard
            peripheral == activePeripheral,
            error == nil,
            service.uuid == batteryServiceUUID,
            let battery = service.characteristics?.first(where: { $0.uuid == batteryLevelUUID })
        else { return }

        if battery.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: battery)
        }
        peripheral.readValue(for: battery)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard
            peripheral == activePeripheral,
            error == nil,
            characteristic.uuid == batteryLevelUUID,
            let value = characteristic.value?.first
        else { return }

        batteryLevel = Int(value)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didReadRSSI RSSI: NSNumber,
        error: Error?
    ) {
        guard peripheral == activePeripheral, error == nil else { return }
        connectedRSSI = RSSI.intValue == 127 ? nil : RSSI.intValue
    }
}

// MARK: - Preview data

#if DEBUG
extension GPSLinkManager {
    static func preview(
        savedModules: [SavedGPSModule] = [],
        discoveredModules: [DiscoveredGPSModule] = [],
        isScanning: Bool = false,
        bluetoothState: CBManagerState = .poweredOn,
        connectedModule: SavedGPSModule? = nil,
        connectedRSSI: Int? = nil,
        batteryLevel: Int? = nil
    ) -> GPSLinkManager {
        let manager = GPSLinkManager()
        manager.savedModules = savedModules
        manager.discoveredModules = discoveredModules
        manager.isScanning = isScanning
        manager.bluetoothState = bluetoothState
        manager.authorization = .allowedAlways
        manager.connectedModule = connectedModule
        manager.connectedRSSI = connectedRSSI
        manager.batteryLevel = batteryLevel
        manager.linkState = connectedModule == nil ? .idle : .connected
        return manager
    }
}

enum ZZPreviewData {
    static let raceboxID = UUID(uuidString: "6B1A7E20-4A6E-4A6B-9A80-01B7A3B4E101")!
    static let vboxID = UUID(uuidString: "0F2E6C11-58E7-49B1-9C3D-22A1BA2FCA02")!
    static let dragyID = UUID(uuidString: "91D4C5A8-2FD0-46CE-B08D-9C9AC4ADB703")!

    static var savedModules: [SavedGPSModule] {
        [
            SavedGPSModule(
                id: raceboxID,
                name: "RaceBox Mini 2",
                lastLinkedAt: Date().addingTimeInterval(-2 * 86_400)
            ),
            SavedGPSModule(
                id: vboxID,
                name: "VBOX Sport",
                lastLinkedAt: Date().addingTimeInterval(-12 * 86_400)
            ),
            SavedGPSModule(
                id: dragyID,
                name: "Dragy GPS",
                lastLinkedAt: Date().addingTimeInterval(-34 * 86_400)
            )
        ]
    }

    static var discoveredModules: [DiscoveredGPSModule] {
        [
            DiscoveredGPSModule(
                id: raceboxID,
                name: "RaceBox Mini 2",
                rssi: -56,
                lastSeen: Date()
            ),
            DiscoveredGPSModule(
                id: UUID(uuidString: "E3AF8E77-4BBD-4938-8473-0D4E540C9F04")!,
                name: "Apex GPS R1",
                rssi: -71,
                lastSeen: Date()
            ),
            DiscoveredGPSModule(
                id: vboxID,
                name: "VBOX Sport",
                rssi: -83,
                lastSeen: Date()
            )
        ]
    }

    static var connectedModule: SavedGPSModule {
        savedModules[0]
    }
}
#endif
