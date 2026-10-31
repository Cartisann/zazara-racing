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
    var hardwareID: String? = nil

    var lastLinkedDateText: String {
        Self.dateFormatter.string(from: lastLinkedAt).uppercased()
    }

    var lastLinkedTimeText: String {
        Self.timeFormatter.string(from: lastLinkedAt)
    }

    /// Hardware-based when available; falls back to the iOS UUID for legacy
    /// records created before the firmware advertised a hardware ID.
    var shortID: String {
        hardwareID ?? String(id.uuidString.prefix(4)).uppercased()
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
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct DiscoveredGPSModule: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int?
    var lastSeen: Date
    var hardwareID: String? = nil

    var shortID: String {
        hardwareID ?? String(id.uuidString.prefix(4)).uppercased()
    }
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

/// Latest decoded GPS values for the live Track dashboard.
struct TrackRoutePoint: Equatable {
    let latitude: Double
    let longitude: Double
}

struct TrackTelemetry: Equatable {
    var date: Date?
    var satellites: Int?
    var hdop: Double?
    var vdop: Double?
    var fix: Int?
    var heading: Double?
    var altitude: Double?
    var latitude: Double?
    var longitude: Double?
    var elapsed: TimeInterval = 0
    var distanceKm: Double = 0
    var speedKPH: Double?
    var updateRateHz: Double = 0
    var route: [TrackRoutePoint] = []
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
    @Published private(set) var availableSavedModuleIDs: Set<UUID> = []
    @Published private(set) var connectedModule: SavedGPSModule?
    @Published private(set) var connectedRSSI: Int?
    @Published private(set) var connectedMACAddress: String?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var trackTelemetry = TrackTelemetry()
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
    private var identityCharacteristic: CBCharacteristic?
    private var heartbeatPendingAt: Date?
    private var rssiPendingAt: Date?
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingModule: SavedGPSModule?
    private var wantsScan = false
    private var isDisconnecting = false
    private var isReconnectScan = false
    private var isResolvingConnection = false
    private var intentionalDisconnect = false
    private var connectTimeout: Timer?
    private var rssiTimer: Timer?
    private var savedAvailabilitySeenAt: [UUID: Date] = [:]
    private var savedAvailabilityExpiry: [UUID: DispatchWorkItem] = [:]

    private let defaults: UserDefaults
    private let persistenceKey = "zazara.savedGPSModules.v1"
    private let maximumSavedModules = 12
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelUUID = CBUUID(string: "2A19")
    private let raceChronoServiceUUID = CBUUID(string: "1FF8")
    private let raceChronoGPSUUID = CBUUID(string: "0003")
    private let raceChronoTimeUUID = CBUUID(string: "0004")

    private var raceChronoGPSCharacteristic: CBCharacteristic?
    private var raceChronoTimeCharacteristic: CBCharacteristic?
    private var timePacketsBySync: [UInt8: DateComponents] = [:]
    private var latestTimePacket: DateComponents?
    private var trackSessionStart: Date?
    private var lastGPSFix: (lat: Double, lon: Double)?
    private var trackDistanceMeters: Double = 0
    private var trackRoute: [TrackRoutePoint] = []
    private var rateWindowStart: Date?
    private var rateWindowCount: Int = 0
    private var lastTelemetryPublish = Date.distantPast
    private var pendingTelemetry = TrackTelemetry()

    // ZAZARA 官方发现服务。硬件在广播中同时保留 RaceChrono 的 0x1FF8，
    // 但这个自定义 128-bit 服务只由 ZAZARA 硬件广播，因此 App 不会看到
    // 其他 RaceChrono DIY 设备，更不会看到附近的普通 BLE 设备。
    private let zazaraServiceUUID = CBUUID(string: "848C50CF-2272-4E15-B32C-3183B3FB8BF6")
    private let zazaraIdentityCharacteristicUUID = CBUUID(string: "CDF36350-93B6-4BF9-A78E-61E08AA444BA")
    private let zazaraIdentityPrefix = Data("ZAZARA".utf8)
    private let minimumZazaraIdentityVersion: UInt8 = 1

    // MARK: Init

    override init() {
        defaults = .standard
        super.init()
        loadSavedModules()
    }

    deinit {
        connectTimeout?.invalidate()
        rssiTimer?.invalidate()
        savedAvailabilityExpiry.values.forEach { $0.cancel() }
    }

    // MARK: Scanning

    func startScan() {
        clearAlert()
        clearSavedAvailability()

        guard linkState == .idle else { return }

        ensureCentral()
        wantsScan = true

        // Wait for didDisconnectPeripheral before scanning; the module does not
        // re-advertise until it has fully released the previous connection.
        if isDisconnecting {
            isScanning = true
            discoveredModules = []
            return
        }

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
        clearSavedAvailability()
        central?.stopScan()
    }

    private func beginScan(clearResults: Bool) {
        guard let central, central.state == .poweredOn else { return }

        if clearResults {
            discoveredModules = []
            knownPeripherals = [:]
            clearSavedAvailability()
        }

        central.stopScan()
        central.scanForPeripherals(
            withServices: [zazaraServiceUUID],
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
                lastLinkedAt: Date(),
                hardwareID: module.hardwareID
            )
        )
    }

    func connect(_ module: SavedGPSModule) {
        guard linkState == .idle else { return }

        clearAlert()
        intentionalDisconnect = false
        identityCharacteristic = nil
        heartbeatPendingAt = nil
        rssiPendingAt = nil
        connectedMACAddress = nil
        clearRaceChronoCharacteristics()
        resetTrackTelemetry()
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
        identityCharacteristic = nil
        heartbeatPendingAt = nil
        rssiPendingAt = nil
        connectedMACAddress = nil
        clearRaceChronoCharacteristics()
        resetTrackTelemetry()
        clearSavedAvailability()

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
        isDisconnecting = true
        connectTimeout?.invalidate()
        connectTimeout = nil
        clearSavedAvailability()
        stopSignalPolling()

        if let peripheral = activePeripheral {
            peripheral.delegate = nil
            central?.cancelPeripheralConnection(peripheral)
        }

        activePeripheral = nil
        pendingModule = nil
        identityCharacteristic = nil
        heartbeatPendingAt = nil
        rssiPendingAt = nil
        connectedMACAddress = nil
        clearRaceChronoCharacteristics()
        resetTrackTelemetry()
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
        clearSavedAvailability()
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
            withServices: [zazaraServiceUUID],
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
        identityCharacteristic = nil
        heartbeatPendingAt = nil
        rssiPendingAt = nil
        connectedMACAddress = nil
        clearRaceChronoCharacteristics()
        resetTrackTelemetry()
        clearSavedAvailability()

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
        let wasActive = (connectedModule?.id == module.id)
            || (isConnected && activePeripheral?.identifier == module.id)
        let wasPending = isConnecting && pendingModule?.id == module.id

        savedModules.removeAll { $0.id == module.id }
        savedAvailabilitySeenAt.removeValue(forKey: module.id)
        savedAvailabilityExpiry.removeValue(forKey: module.id)?.cancel()
        var available = availableSavedModuleIDs
        available.remove(module.id)
        availableSavedModuleIDs = available
        persistSavedModules()

        // Deleting the active record ends the BLE link as part of the delete.
        if wasActive {
            disconnect()
        } else if wasPending {
            cancelConnection()
        }
    }

    func clearSavedRecords() {
        let wasActive = isConnected
        let wasPending = isConnecting

        savedModules.removeAll()
        clearSavedAvailability()
        persistSavedModules()

        if wasActive {
            disconnect()
        } else if wasPending {
            cancelConnection()
        }
    }

    func dismissAlert() {
        alert = nil
    }

    private func recordLink(id: UUID, name: String, hardwareID: String?) -> SavedGPSModule {
        let existingHardwareID = savedModules.first(where: { $0.id == id })?.hardwareID
        let module = SavedGPSModule(
            id: id,
            name: name,
            lastLinkedAt: Date(),
            hardwareID: hardwareID ?? existingHardwareID
        )

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

    /// Re-check immediately when the app returns to the foreground.
    func refreshConnectionHealth() {
        guard isConnected else { return }
        refreshLinkHealth()
    }

    private func startSignalPolling() {
        stopSignalPolling()
        refreshLinkHealth()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshLinkHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        rssiTimer = timer
    }

    private func refreshLinkHealth() {
        guard isConnected else {
            stopSignalPolling()
            return
        }

        guard let peripheral = activePeripheral, peripheral.state == .connected else {
            handleUnexpectedLinkLoss()
            return
        }

        let now = Date()
        if let pending = heartbeatPendingAt, now.timeIntervalSince(pending) > 3.5 {
            handleUnexpectedLinkLoss()
            return
        }

        // A GATT read is a stronger liveness check than CBPeripheral.state:
        // it requires the peripheral to answer over the air.
        if heartbeatPendingAt == nil, let identityCharacteristic {
            heartbeatPendingAt = now
            peripheral.readValue(for: identityCharacteristic)
        }

        if rssiPendingAt == nil {
            rssiPendingAt = now
            peripheral.readRSSI()
        }
    }

    private func stopSignalPolling() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        heartbeatPendingAt = nil
        rssiPendingAt = nil
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

    private func isZazaraAdvertisement(_ advertisementData: [String: Any]) -> Bool {
        // The scan itself is already filtered by zazaraServiceUUID. Some iOS
        // versions expose only the private "hashed service UUIDs" key, so an
        // absent public key must not hide a valid result; post-connect identity
        // verification remains the source of truth.
        guard let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] else {
            return true
        }
        return services.contains(zazaraServiceUUID)
    }

    private func isValidZazaraIdentity(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        guard data.starts(with: zazaraIdentityPrefix) else { return false }
        return data[7] >= minimumZazaraIdentityVersion
    }

    private func markSavedModuleAvailable(_ id: UUID) {
        let now = Date()
        savedAvailabilitySeenAt[id] = now

        if !availableSavedModuleIDs.contains(id) {
            var updated = availableSavedModuleIDs
            updated.insert(id)
            availableSavedModuleIDs = updated
        }

        // Re-arm a one-shot expiry instead of relying on a repeating RunLoop
        // timer. If the hardware disappears, the saved row returns to Connect
        // automatically without requiring stop/start.
        savedAvailabilityExpiry[id]?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            guard let seen = self.savedAvailabilitySeenAt[id],
                  Date().timeIntervalSince(seen) >= 4.5 else { return }

            self.savedAvailabilitySeenAt.removeValue(forKey: id)
            self.savedAvailabilityExpiry.removeValue(forKey: id)

            var updated = self.availableSavedModuleIDs
            updated.remove(id)
            self.availableSavedModuleIDs = updated
        }
        savedAvailabilityExpiry[id] = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: expiry)
    }

    private func clearSavedAvailability() {
        savedAvailabilityExpiry.values.forEach { $0.cancel() }
        savedAvailabilityExpiry.removeAll()
        savedAvailabilitySeenAt.removeAll()
        if !availableSavedModuleIDs.isEmpty {
            availableSavedModuleIDs = []
        }
    }

    private func hardwareID(from name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hashIndex = trimmed.lastIndex(of: "#") else { return nil }

        let suffix = trimmed[trimmed.index(after: hashIndex)...]
        guard suffix.count == 4, suffix.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return suffix.uppercased()
    }

    private func displayNameWithoutHardwareID(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(
            of: #"\s+#[0-9A-Fa-f]{4}$"#,
            options: .regularExpression
        ) else {
            return trimmed
        }

        return String(trimmed[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resetTrackTelemetry(startSession: Bool = false) {
        timePacketsBySync.removeAll()
        latestTimePacket = nil
        trackSessionStart = startSession ? Date() : nil
        lastGPSFix = nil
        trackDistanceMeters = 0
        trackRoute.removeAll()
        rateWindowStart = nil
        rateWindowCount = 0
        lastTelemetryPublish = .distantPast
        pendingTelemetry = TrackTelemetry()
        trackTelemetry = TrackTelemetry()
    }

    private func clearRaceChronoCharacteristics() {
        raceChronoGPSCharacteristic = nil
        raceChronoTimeCharacteristic = nil
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private func readInt32(_ data: Data, at offset: Int) -> Int32 {
        let value = (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
        return Int32(bitPattern: value)
    }

    private func decodeGPSTime(_ data: Data) {
        guard data.count >= 3 else { return }

        let sync = data[0] >> 5
        let payload = (Int(data[0] & 0x1F) << 16)
            | (Int(data[1]) << 8)
            | Int(data[2])
        let year = 2000 + payload / 8928
        let monthRemainder = payload % 8928
        let month = monthRemainder / 744 + 1
        let dayRemainder = monthRemainder % 744
        let day = dayRemainder / 24 + 1
        let hour = dayRemainder % 24

        guard (2000...2100).contains(year),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour) else { return }

        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        timePacketsBySync[sync] = components
        latestTimePacket = components
    }

    private func decodeGPSTelemetry(_ data: Data) {
        guard data.count >= 20 else { return }

        let now = Date()
        let sync = data[0] >> 5
        let timePayload = (Int(data[0] & 0x1F) << 16)
            | (Int(data[1]) << 8)
            | Int(data[2])
        let minute = timePayload / 30000
        let second = (timePayload % 30000) / 500
        let millisecond = (timePayload % 500) * 2

        let fix = Int(data[3] >> 6)
        let satelliteRaw = Int(data[3] & 0x3F)
        let latitudeRaw = readInt32(data, at: 4)
        let longitudeRaw = readInt32(data, at: 8)
        let altitudeRaw = readUInt16(data, at: 12)
        let speedRaw = readUInt16(data, at: 14)
        let headingRaw = readUInt16(data, at: 16)
        let hdopRaw = data[18]
        let vdopRaw = data[19]

        var telemetry = pendingTelemetry
        telemetry.fix = fix
        telemetry.satellites = satelliteRaw == 0x3F ? nil : satelliteRaw

        if latitudeRaw != Int32.max, longitudeRaw != Int32.max {
            telemetry.latitude = Double(latitudeRaw) / 10_000_000
            telemetry.longitude = Double(longitudeRaw) / 10_000_000
        } else {
            telemetry.latitude = nil
            telemetry.longitude = nil
            lastGPSFix = nil
        }

        if altitudeRaw == 0xFFFF {
            telemetry.altitude = nil
        } else if altitudeRaw & 0x8000 != 0 {
            telemetry.altitude = Double(altitudeRaw & 0x7FFF) - 500
        } else {
            telemetry.altitude = Double(altitudeRaw & 0x7FFF) / 10 - 500
        }

        if speedRaw == 0xFFFF {
            telemetry.speedKPH = nil
        } else if speedRaw & 0x8000 != 0 {
            telemetry.speedKPH = Double(speedRaw & 0x7FFF) / 10
        } else {
            telemetry.speedKPH = Double(speedRaw & 0x7FFF) / 100
        }

        telemetry.heading = headingRaw == 0xFFFF ? nil : Double(headingRaw) / 100
        telemetry.hdop = hdopRaw == 0xFF ? nil : Double(hdopRaw) / 10
        telemetry.vdop = vdopRaw == 0xFF ? nil : Double(vdopRaw) / 10

        if var components = timePacketsBySync[sync] ?? latestTimePacket {
            components.minute = minute
            components.second = second
            components.nanosecond = millisecond * 1_000_000
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            telemetry.date = calendar.date(from: components)
        } else {
            telemetry.date = nil
        }

        if let latitude = telemetry.latitude, let longitude = telemetry.longitude {
            if let previous = lastGPSFix {
                let segment = Self.distanceMeters(
                    from: previous,
                    to: (latitude, longitude)
                )
                if segment.isFinite, segment > 0.25, segment < 1_000 {
                    trackDistanceMeters += segment
                }
            }
            lastGPSFix = (latitude, longitude)

            if let last = trackRoute.last {
                if abs(latitude - last.latitude) > 0.000001
                    || abs(longitude - last.longitude) > 0.000001 {
                    trackRoute.append(TrackRoutePoint(latitude: latitude, longitude: longitude))
                }
            } else {
                trackRoute.append(TrackRoutePoint(latitude: latitude, longitude: longitude))
            }
            if trackRoute.count > 600 {
                trackRoute.removeFirst(trackRoute.count - 600)
            }
        }
        telemetry.distanceKm = trackDistanceMeters / 1000
        telemetry.route = trackRoute

        if trackSessionStart == nil {
            trackSessionStart = now
        }
        telemetry.elapsed = trackSessionStart.map { now.timeIntervalSince($0) } ?? 0

        // Derive the update rate from the GPS fix timestamps carried in the
        // RaceChrono packets (2 ms resolution), not from BLE notification
        // arrival. Connection interval jitter and notification coalescing
        // therefore do not affect the displayed Hz.
        if let fixDate = telemetry.date {
            if let windowStart = rateWindowStart {
                let interval = fixDate.timeIntervalSince(windowStart)

                if interval < 0 || interval > 2 {
                    // GPS time jumped or the stream stalled: start a new
                    // window instead of reporting a bogus low rate.
                    rateWindowStart = fixDate
                    rateWindowCount = 0
                    telemetry.updateRateHz = 0
                } else if interval >= 1 {
                    rateWindowCount += 1
                    telemetry.updateRateHz = Double(rateWindowCount) / interval
                    rateWindowStart = fixDate
                    rateWindowCount = 0
                } else {
                    // Duplicate timestamps should not inflate the count.
                    if interval > 0 {
                        rateWindowCount += 1
                    }
                    telemetry.updateRateHz = pendingTelemetry.updateRateHz
                }
            } else {
                rateWindowStart = fixDate
                rateWindowCount = 0
                telemetry.updateRateHz = 0
            }
        } else {
            telemetry.updateRateHz = pendingTelemetry.updateRateHz
        }

        pendingTelemetry = telemetry

        if now.timeIntervalSince(lastTelemetryPublish) >= 0.2 {
            trackTelemetry = telemetry
            lastTelemetryPublish = now
        }
    }

    private static func distanceMeters(
        from start: (lat: Double, lon: Double),
        to end: (lat: Double, lon: Double)
    ) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = start.lat * .pi / 180
        let lat2 = end.lat * .pi / 180
        let deltaLat = (end.lat - start.lat) * .pi / 180
        let deltaLon = (end.lon - start.lon) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func hardwareID(fromIdentity data: Data) -> String? {
        guard data.count >= 16 else { return nil }
        return String(format: "%02X%02X", data[14], data[15])
    }

    private func macAddress(fromIdentity data: Data) -> String? {
        guard data.count >= 16 else { return nil }
        return (10..<16)
            .map { String(format: "%02X", data[$0]) }
            .joined(separator: ":")
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
        return "ZAZARA GPS \(suffix)"
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
            clearSavedAvailability()

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
                identityCharacteristic = nil
                connectedMACAddress = nil
                clearRaceChronoCharacteristics()
                resetTrackTelemetry()
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

        // 扫描时已经按 ZAZARA 自定义服务过滤；这里再校验一次，避免 iOS
        // 缓存或错误配置把非 ZAZARA 设备带进列表。
        guard isZazaraAdvertisement(advertisementData) else { return }

        let rawName = displayName(for: peripheral, advertisementData: advertisementData)
        let advertisedHardwareID = hardwareID(from: rawName)
        let name = displayNameWithoutHardwareID(rawName)

        // This is the module the user asked us to reconnect to.
        if let pendingModule,
           pendingModule.id == identifier,
           case .connecting = linkState {
            knownPeripherals[identifier] = peripheral
            if self.pendingModule?.hardwareID == nil, let advertisedHardwareID {
                self.pendingModule?.hardwareID = advertisedHardwareID
            }

            if activePeripheral == nil {
                openConnection(to: peripheral)
            }
            return
        }

        knownPeripherals[identifier] = peripheral

        guard isScanning else { return }

        // A previously linked module belongs in Bluetooth records, not in the
        // "new device" scan results. Keep it cached above so tapping its saved
        // record can reconnect without a fresh discovery, and mark it as
        // currently connectable.
        if let savedIndex = savedModules.firstIndex(where: { $0.id == identifier }) {
            var changed = false
            if let advertisedHardwareID,
               savedModules[savedIndex].hardwareID != advertisedHardwareID {
                savedModules[savedIndex].hardwareID = advertisedHardwareID
                changed = true
            }
            if !name.isEmpty, savedModules[savedIndex].name != name {
                savedModules[savedIndex].name = name
                changed = true
            }
            if changed {
                persistSavedModules()
            }
            markSavedModuleAvailable(identifier)
            return
        }

        let rawRSSI = RSSI.intValue
        let reading: Int? = rawRSSI == 127 ? nil : rawRSSI

        if let index = discoveredModules.firstIndex(where: { $0.id == identifier }) {
            discoveredModules[index].name = name
            discoveredModules[index].rssi = reading
            discoveredModules[index].lastSeen = Date()
            if let advertisedHardwareID {
                discoveredModules[index].hardwareID = advertisedHardwareID
            }
        } else {
            discoveredModules.append(
                DiscoveredGPSModule(
                    id: identifier,
                    name: name,
                    rssi: reading,
                    lastSeen: Date(),
                    hardwareID: advertisedHardwareID
                )
            )
        }

        discoveredModules.sort {
            ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Ignore a late connect callback after the user cancelled or after a
        // forced link-loss reset.
        guard case .connecting = linkState else {
            central.cancelPeripheralConnection(peripheral)
            return
        }

        // Keep the link in .connecting until the ZAZARA identity characteristic
        // has been read; only then is the module saved / shown as connected.
        central.stopScan()

        isScanning = false
        wantsScan = false
        isReconnectScan = false
        isResolvingConnection = false
        intentionalDisconnect = false
        clearSavedAvailability()

        activePeripheral = peripheral
        peripheral.delegate = self

        peripheral.discoverServices([zazaraServiceUUID])
    }

    private func completeVerifiedConnection(
        to peripheral: CBPeripheral,
        hardwareID: String?,
        macAddress: String?
    ) {
        guard
            peripheral == activePeripheral,
            case .connecting = linkState
        else { return }

        guard peripheral.state == .connected else {
            handleUnexpectedLinkLoss()
            return
        }

        connectTimeout?.invalidate()
        connectTimeout = nil

        let name = pendingModule?.name ?? displayName(for: peripheral)
        let cachedRSSI = discoveredModules.first(where: { $0.id == peripheral.identifier })?.rssi
        let module = recordLink(
            id: peripheral.identifier,
            name: name,
            hardwareID: hardwareID
        )

        discoveredModules.removeAll()
        pendingModule = nil
        connectedModule = module
        connectedRSSI = cachedRSSI
        connectedMACAddress = macAddress
        resetTrackTelemetry(startSession: true)
        batteryLevel = nil
        linkState = .connected
        linkEventID += 1

        startSignalPolling()
        peripheral.discoverServices([batteryServiceUUID, raceChronoServiceUUID])
    }

    private func failIdentityVerification() {
        failConnection(
            title: l10n.t("Unsupported GPS module"),
            message: l10n.t("This device isn’t a ZAZARA GPS module.")
        )
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
        finishDisconnectedLink(
            peripheral: peripheral,
            wasConnected: isConnected,
            wasConnecting: isConnecting,
            wasIntentional: intentionalDisconnect
        )
    }

    private func finishDisconnectedLink(
        peripheral: CBPeripheral,
        wasConnected: Bool,
        wasConnecting: Bool,
        wasIntentional: Bool
    ) {
        let name = connectedModule?.name
            ?? pendingModule?.name
            ?? displayName(for: peripheral)

        intentionalDisconnect = false
        connectTimeout?.invalidate()
        connectTimeout = nil
        stopSignalPolling()

        isResolvingConnection = false
        isReconnectScan = false
        isDisconnecting = false
        pendingModule = nil
        identityCharacteristic = nil
        connectedMACAddress = nil
        clearRaceChronoCharacteristics()
        resetTrackTelemetry()
        clearSavedAvailability()

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

        if wantsScan, linkState == .idle {
            beginScan(clearResults: true)
        } else {
            isScanning = false
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

    /// CoreBluetooth normally delivers didDisconnect, but iOS can keep a stale
    /// `.connected` UI after the peripheral disappears. The RSSI/health timer
    /// calls this to force the saved row back to "Connect".
    private func handleUnexpectedLinkLoss() {
        guard isConnected || isConnecting else { return }

        guard let peripheral = activePeripheral else {
            disconnect()
            return
        }

        let wasConnected = isConnected
        let wasConnecting = isConnecting
        finishDisconnectedLink(
            peripheral: peripheral,
            wasConnected: wasConnected,
            wasConnecting: wasConnecting,
            wasIntentional: false
        )
        central?.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - CBPeripheralDelegate

extension GPSLinkManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == activePeripheral else { return }

        if isConnected {
            guard error == nil else { return }

            if let batteryService = peripheral.services?.first(where: { $0.uuid == batteryServiceUUID }) {
                peripheral.discoverCharacteristics([batteryLevelUUID], for: batteryService)
            }

            if let raceService = peripheral.services?.first(where: { $0.uuid == raceChronoServiceUUID }) {
                peripheral.discoverCharacteristics(
                    [raceChronoGPSUUID, raceChronoTimeUUID],
                    for: raceService
                )
            }
            return
        }

        guard case .connecting = linkState else { return }

        guard
            error == nil,
            let identityService = peripheral.services?.first(where: { $0.uuid == zazaraServiceUUID })
        else {
            failIdentityVerification()
            return
        }

        peripheral.discoverCharacteristics(
            [zazaraIdentityCharacteristicUUID],
            for: identityService
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard peripheral == activePeripheral else { return }

        if service.uuid == zazaraServiceUUID {
            guard case .connecting = linkState else { return }
            guard
                error == nil,
                let identity = service.characteristics?.first(where: {
                    $0.uuid == zazaraIdentityCharacteristicUUID
                })
            else {
                failIdentityVerification()
                return
            }

            identityCharacteristic = identity
            peripheral.readValue(for: identity)
            return
        }

        if service.uuid == raceChronoServiceUUID {
            guard isConnected, error == nil else { return }

            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == raceChronoGPSUUID {
                    raceChronoGPSCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == raceChronoTimeUUID {
                    raceChronoTimeCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            return
        }

        guard
            isConnected,
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
        guard peripheral == activePeripheral else { return }

        if characteristic.uuid == zazaraIdentityCharacteristicUUID {
            if case .connecting = linkState {
                guard
                    error == nil,
                    let value = characteristic.value,
                    isValidZazaraIdentity(value)
                else {
                    failIdentityVerification()
                    return
                }

                heartbeatPendingAt = nil
                completeVerifiedConnection(
                    to: peripheral,
                    hardwareID: hardwareID(fromIdentity: value) ?? pendingModule?.hardwareID,
                    macAddress: macAddress(fromIdentity: value)
                )
                return
            }

            if isConnected {
                heartbeatPendingAt = nil
                if error != nil {
                    handleUnexpectedLinkLoss()
                }
            }
            return
        }

        if characteristic.uuid == raceChronoGPSUUID {
            if error == nil, let data = characteristic.value {
                decodeGPSTelemetry(data)
            }
            return
        }

        if characteristic.uuid == raceChronoTimeUUID {
            if error == nil, let data = characteristic.value {
                decodeGPSTime(data)
            }
            return
        }

        guard
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
        guard peripheral == activePeripheral else { return }

        rssiPendingAt = nil

        if error != nil {
            handleUnexpectedLinkLoss()
            return
        }

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
                name: "ZAZARA RACING",
                lastLinkedAt: Date().addingTimeInterval(-2 * 86_400)
            ),
            SavedGPSModule(
                id: vboxID,
                name: "ZAZARA RACING 2",
                lastLinkedAt: Date().addingTimeInterval(-12 * 86_400)
            ),
            SavedGPSModule(
                id: dragyID,
                name: "ZAZARA RACING 3",
                lastLinkedAt: Date().addingTimeInterval(-34 * 86_400)
            )
        ]
    }

    static var discoveredModules: [DiscoveredGPSModule] {
        [
            DiscoveredGPSModule(
                id: raceboxID,
                name: "ZAZARA RACING",
                rssi: -56,
                lastSeen: Date()
            ),
            DiscoveredGPSModule(
                id: UUID(uuidString: "E3AF8E77-4BBD-4938-8473-0D4E540C9F04")!,
                name: "ZAZARA RACING 2",
                rssi: -71,
                lastSeen: Date()
            ),
            DiscoveredGPSModule(
                id: vboxID,
                name: "ZAZARA RACING 3",
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
