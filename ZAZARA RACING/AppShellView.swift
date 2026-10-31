//
//  AppShellView.swift
//  ZAZARA RACING
//
//  Four-tab app shell and the secondary tabs.
//

import Charts
import Combine
import CoreLocation
import MapKit
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

enum AppTab: String, CaseIterable, Identifiable {
    case drag
    case track
    case devices
    case more

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .drag: return "TIMING"
        case .track: return "TRACK"
        case .devices: return "DEVICES"
        case .more: return "MINE"
        }
    }

    var title: String {
        switch self {
        case .drag: return "TIMING"
        case .track: return "TRACK"
        case .devices: return "DEVICES"
        case .more: return "MINE"
        }
    }

    var icon: String {
        switch self {
        case .drag: return "speedometer"
        case .track: return "map"
        case .devices: return "antenna.radiowaves.left.and.right"
        case .more: return "person"
        }
    }
}

/// China's online maps (including Apple Maps in mainland China) use the
/// GCJ-02 datum, while GPS / RaceChrono data is WGS84. When enabled, WGS84
/// coordinates are offset only for display; stored data keeps WGS84.
private enum ChinaMapAlignment {
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    static func display(_ coordinate: CLLocationCoordinate2D, enabled: Bool) -> CLLocationCoordinate2D {
        guard enabled else { return coordinate }
        return gcj02(from: coordinate)
    }

    static func stored(fromMap coordinate: CLLocationCoordinate2D, enabled: Bool) -> CLLocationCoordinate2D {
        guard enabled else { return coordinate }
        return wgs84(fromGCJ: coordinate)
    }

    static func wgs84(fromGCJ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !isOutsideChina(coordinate) else { return coordinate }
        var latitude = coordinate.latitude
        var longitude = coordinate.longitude
        for _ in 0..<3 {
            let converted = gcj02(from: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            latitude -= converted.latitude - coordinate.latitude
            longitude -= converted.longitude - coordinate.longitude
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func gcj02(from coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !isOutsideChina(coordinate) else { return coordinate }

        let dLat = transformLat(x: coordinate.longitude - 105.0, y: coordinate.latitude - 35.0)
        let dLng = transformLng(x: coordinate.longitude - 105.0, y: coordinate.latitude - 35.0)

        let radLat = coordinate.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        let latitude = coordinate.latitude
            + (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        let longitude = coordinate.longitude
            + (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }

    private static func isOutsideChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude < 72.004 || coordinate.longitude > 137.8347
            || coordinate.latitude < 0.8293 || coordinate.latitude > 55.8271
    }
}

final class PhoneLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var started = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start() {
        guard !started else { return }
        started = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

private enum TimingRoute: Hashable {
    case drag
    case track
}

struct AppShellView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: AppTab
    @State private var dragPath: [TimingRoute] = []

    init(manager: GPSLinkManager, initialTab: AppTab = .devices) {
        self.manager = manager
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            Color.zzCanvas.ignoresSafeArea()
            tabView
            connectingOverlay
        }
        .background(Color.zzCanvas)
        .preferredColorScheme(.dark)
        .environment(\.locale, AppSettings.shared.locale)
        .animation(.easeInOut(duration: 0.2), value: manager.linkState)
        .zzOnChange(of: selectedTab) { tab in
            if tab != .devices {
                manager.stopScan()
            }
        }
    }

    /// Native system tab bar. On iOS 18+ the tab bar adapts to a sidebar on
    /// wide layouts (iPhone Duo inner / iPad), exactly like Phone and Alipay;
    /// the Liquid Glass material and its selection transition are system-drawn.
    @ViewBuilder
    private var tabView: some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, macOS 15.0, *) {
            GeometryReader { proxy in
                let duoLandscape = isDuoLandscape(size: proxy.size)

                TabView(selection: $selectedTab) {
                    Tab(value: AppTab.drag) {
                        dragTab
                            .environment(\.layoutDirection, .leftToRight)
                    } label: {
                        tabLabel(.drag)
                    }

                    Tab(value: AppTab.track) {
                        trackTab
                            .environment(\.layoutDirection, .leftToRight)
                    } label: {
                        tabLabel(.track)
                    }

                    Tab(value: AppTab.devices) {
                        DevicesView(manager: manager)
                            .environment(\.layoutDirection, .leftToRight)
                    } label: {
                        tabLabel(.devices)
                    }

                    Tab(value: AppTab.more) {
                        MoreView(manager: manager)
                            .environment(\.layoutDirection, .leftToRight)
                    } label: {
                        tabLabel(.more)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                // Duo inner/cover landscape: the system puts the adaptive
                // sidebar on the leading edge. RTL moves that sidebar to the
                // trailing (right) edge; each tab's content is forced back to
                // LTR so the interface itself is not mirrored.
                .environment(\.layoutDirection, duoLandscape ? .rightToLeft : .leftToRight)
            }
        } else {
            legacyTabView
        }
        #else
        legacyTabView
        #endif
    }

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            dragTab
                .tabItem { tabLabel(.drag) }
                .tag(AppTab.drag)

            trackTab
                .tabItem { tabLabel(.track) }
                .tag(AppTab.track)

            DevicesView(manager: manager)
                .tabItem { tabLabel(.devices) }
                .tag(AppTab.devices)

            MoreView(manager: manager)
                .tabItem { tabLabel(.more) }
                .tag(AppTab.more)
        }
    }

    /// Timing detail pages live in a NavigationStack so the system draws the
    /// back button at the leading edge, with the right safe areas on Duo,
    /// normal iPhones, and older iOS versions.
    private var dragTab: some View {
        NavigationStack(path: $dragPath) {
            dragView
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(for: TimingRoute.self) { route in
                    switch route {
                    case .drag:
                        DragTimingView()
                    case .track:
                        TrackTimingView(manager: manager)
                    }
                }
        }
    }

    private var trackTab: some View {
        NavigationStack {
            TrackLibraryView(manager: manager) {
                selectedTab = .devices
            }
        }
    }

    private var dragView: some View {
        DragView(
            manager: manager,
            openDragTiming: {
                dragPath.append(.drag)
            },
            openTrackTiming: {
                dragPath.append(.track)
            },
            openDevices: {
                selectedTab = .devices
            }
        )
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(settings.t(tab.localizationKey), systemImage: tab.icon)
    }

    /// The Duo's inner display is phone-idiom but nearly square in landscape
    /// (around 1.4:1). Regular iPhones are much wider (about 2.1:1), and iPad
    /// is a different idiom. Only the Duo-like landscape needs the sidebar
    /// forced to the trailing edge.
    private func isDuoLandscape(size: CGSize) -> Bool {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        // Only the unfolded Duo panel: it is phone-idiom but almost 1.4:1
        // in landscape (around 1000×700 pt). Cover landscape, regular
        // iPhones and iPad are deliberately excluded.
        guard size.width > size.height, size.width > 900, size.height > 600 else { return false }
        return size.width / max(size.height, 1) < 1.8
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var connectingOverlay: some View {
        if case let .connecting(_, name) = manager.linkState {
            ZZConnectingOverlay(name: name) {
                manager.cancelConnection()
            }
            .zIndex(10)
            .transition(.opacity)
        }
    }
}

// MARK: - Drag / Track placeholders

struct DragView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    var openDragTiming: () -> Void
    var openTrackTiming: () -> Void
    var openDevices: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("Timing"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            )

            ScrollView {
                VStack(spacing: 16) {
                    TimingConnectionStatusPanel(statuses: timingDeviceStatuses)

                    // 直线加速入口暂时隐藏，DragTimingView 代码保留。
                    // TimingModeCard(
                    //     kind: .drag,
                    //     title: settings.t("Drag"),
                    //     onTap: openDragTiming
                    // )

                    TimingModeCard(
                        kind: .track,
                        title: settings.t("Track"),
                        onTap: openTrackTiming
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.zzCanvas)
        }
        .background(Color.zzCanvas.ignoresSafeArea())
    }

    private var timingDeviceStatuses: [TimingDeviceStatus] {
        guard manager.isConnected, let module = manager.connectedModule else {
            return []
        }

        // Keep this as an array: cameras and other accessories can be appended
        // later without changing the panel layout.
        return [
            TimingDeviceStatus(
                id: module.id,
                name: module.name,
                kind: .gps,
                signalLevel: manager.connectedRSSI.map(GPSLinkManager.signalLevel(for:)),
                connectionType: settings.t("Bluetooth LE"),
                shortID: module.shortID
            )
        ]
    }
}

private struct TimingDeviceStatus: Identifiable {
    let id: UUID
    let name: String
    let kind: TimingDeviceKind
    let signalLevel: Int?
    let connectionType: String
    let shortID: String
}

private enum TimingDeviceKind {
    case gps
    case camera

    var icon: String {
        switch self {
        case .gps: return "location.north.circle.fill"
        case .camera: return "camera.fill"
        }
    }

    var labelKey: String {
        switch self {
        case .gps: return "GPS"
        case .camera: return "Camera"
        }
    }
}

private struct TimingConnectionStatusPanel: View {
    let statuses: [TimingDeviceStatus]
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            if statuses.isEmpty {
                notConnectedRow
            } else {
                ForEach(Array(statuses.enumerated()), id: \.element.id) { index, status in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.zzLine)
                            .frame(height: 0.5)
                            .padding(.leading, 64)
                    }
                    statusRow(status)
                }
            }
        }
        .zzCard(cornerRadius: 18)
    }

    private var notConnectedRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.zzMutedSurface)
                    .frame(width: 34, height: 34)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.zzTertiary)
            }

            Text(settings.t("Not connected"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.zzInk)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func statusRow(_ status: TimingDeviceStatus) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.zzRedSoft)
                    .frame(width: 34, height: 34)

                Image(systemName: status.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.zzGreen)
                        .frame(width: 5, height: 5)

                    Text(status.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .lineLimit(1)

                    Text("#\(status.shortID)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.zzTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }

                HStack(spacing: 4) {
                    Text(settings.t(status.kind.labelKey))
                    Text("·")
                    Text(status.connectionType)
                }
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)

            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                ZZSignalBars(level: status.signalLevel ?? 0)

                Text(settings.signalLabel(level: status.signalLevel ?? 0))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private enum TimingModeKind {
    case drag
    case track
}

private struct TimingModeCard: View {
    let kind: TimingModeKind
    let title: String
    var badge: String? = nil
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                card(isInteractive: true)
            }
            .buttonStyle(ZZCardButtonStyle())
        } else {
            card(isInteractive: false)
        }
    }

    private func card(isInteractive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.zzRedSoft)
                        .frame(width: 48, height: 48)

                    if kind == .track {
                        ZZTrackShape()
                            .stroke(
                                Color.zzInk,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 32, height: 26)
                    } else {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.zzInk)
                    }
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.zzInk)

                Spacer(minLength: 8)

                if let badge {
                    Text(badge)
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.zzRed)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.zzRedSoft))
                } else if isInteractive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.zzTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.zzMutedSurface))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(minHeight: 124, alignment: .leading)
        .zzCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct TrackLibraryView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var phoneLocation = PhoneLocationProvider()
    private let onOpenDevices: () -> Void

    @State private var imported: [ImportedTrack] = []
    @State private var selectedTrack: TrackMapInfo?
    @State private var previewTrack: TrackMapInfo?
    @State private var pendingEditTrack: TrackMapInfo?
    @State private var editorItem: TrackEditorItem?
    @State private var showSearch = false
    @State private var panelCollapsed = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var showImporter = false
    @State private var importError: String?

    init(manager: GPSLinkManager, onOpenDevices: @escaping () -> Void = {}) {
        self.manager = manager
        self.onOpenDevices = onOpenDevices
    }

    private var filteredTracks: [TrackMapInfo] {
        let tracks = imported.map { track in
            TrackMapInfo(
                id: track.id,
                name: track.name,
                subtitle: "",
                resource: nil,
                jsonData: track.jsonData
            )
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tracks }
        return tracks.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var trackEditorCenter: CLLocationCoordinate2D? {
        if let coordinate = phoneLocation.coordinate { return coordinate }
        guard let latitude = manager.trackTelemetry.latitude,
              let longitude = manager.trackTelemetry.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscapeBody(size: proxy.size)
            } else {
                regularBody
            }
        }
        .background(Color.zzCanvas.ignoresSafeArea())
        .onChange(of: showSearch) { _, isOn in
            if isOn { searchFocused = true } else { searchFocused = false }
        }
        .onAppear {
            imported = TrackStore.load()
            phoneLocation.start()
        }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .topBarTrailing) {
                trackToolbarButtons
            }
            #else
            ToolbarItemGroup(placement: .primaryAction) {
                trackToolbarButtons
            }
            #endif
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [TrackImporter.contentType],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var tracks = imported
                for url in urls {
                    if let track = try? TrackImporter.importTrack(from: url) {
                        tracks.append(track)
                    }
                }
                TrackStore.save(tracks)
                imported = tracks
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert(
            "导入失败",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $selectedTrack, onDismiss: {
            guard let track = pendingEditTrack else { return }
            pendingEditTrack = nil
            editorItem = TrackEditorItem(track: imported.first(where: { $0.id == track.id }))
        }) { track in
            TrackDetailSheet(track: track) {
                pendingEditTrack = track
                selectedTrack = nil
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $editorItem) { item in
            editorSheet(item.track)
        }
        #else
        .sheet(item: $editorItem) { item in
            editorSheet(item.track)
        }
        #endif
    }

    private var regularBody: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("Track"),
                subtitle: settings.t("Track library and lap timing"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            ) {
                EmptyView()
            }

            List {
                ForEach(filteredTracks) { track in
                    Button {
                        selectedTrack = track
                    } label: {
                        TrackNameRow(track: track)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
                .onDelete { offsets in
                    var tracks = imported
                    let all = filteredTracks
                    let ids = offsets.compactMap { all.indices.contains($0) ? all[$0].id : nil }
                    tracks.removeAll { ids.contains($0.id) }
                    TrackStore.save(tracks)
                    imported = tracks
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.zzCanvas)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showSearch {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .background(Color.zzCanvas.opacity(0.96))
            }
        }
    }

    private func landscapeBody(size: CGSize) -> some View {
        let cardWidth = min(820, max(360, size.width * 0.42))
        let selected = previewTrack ?? filteredTracks.first

        return ZStack(alignment: panelCollapsed ? .bottomLeading : .topLeading) {
            TrackMapCanvas(
                traps: selected.flatMap { TrackMapCatalog.load($0)?.track?.traps } ?? []
            )
            .id(selected?.id ?? "none")
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.zzInk.opacity(0.28))
                        .frame(width: 40, height: 5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .gesture(collapseDragGesture)
                        .padding(.top, 6)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(settings.t("Track"))
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.zzInk)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .gesture(collapseDragGesture)
                }

                if !panelCollapsed {
                        List {
                        ForEach(filteredTracks) { track in
                            Button {
                                previewTrack = track
                            } label: {
                                TrackNameRow(
                                    track: track,
                                    isSelected: track.id == selected?.id
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        .onDelete { offsets in
                            var tracks = imported
                            let all = filteredTracks
                            let ids = offsets.compactMap { all.indices.contains($0) ? all[$0].id : nil }
                            tracks.removeAll { ids.contains($0.id) }
                            TrackStore.save(tracks)
                            imported = tracks
                            if let previewTrack, ids.contains(previewTrack.id) {
                                self.previewTrack = nil
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)

                    if showSearch {
                        searchBar
                            .padding(.horizontal, 12)
                            .padding(.top, 6)
                            .padding(.bottom, 10)
                    }
                }
            }
            .frame(width: cardWidth)
            .frame(maxHeight: panelCollapsed ? nil : .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.zzLine.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 26, y: 12)
            .padding(.vertical, 12)
            .padding(.leading, 16)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: panelCollapsed)

        }
        .toolbar {
            if let selected {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openEditor(selected)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("编辑赛道")
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openEditor(selected)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("编辑赛道")
                }
                #endif
            }
        }
    }

    private func openEditor(_ track: TrackMapInfo) {
        guard let importedTrack = imported.first(where: { $0.id == track.id }) else { return }
        editorItem = TrackEditorItem(track: importedTrack)
    }

    private var collapseDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                if value.translation.height > 24 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        panelCollapsed = true
                    }
                } else if value.translation.height < -24 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        panelCollapsed = false
                    }
                }
            }
    }

    @ViewBuilder
    private var trackToolbarButtons: some View {
        Button {
            showSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("搜索赛道")

        Button {
            showImporter = true
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .accessibilityLabel("导入 .rcz")

        Button {
            editorItem = TrackEditorItem(track: nil)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("手动添加赛道")
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)

            TextField("搜索赛道", text: $query)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.zzInk)
                .focused($searchFocused)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.zzTertiary)
                }
                .buttonStyle(.plain)
            }

            Button("取消") {
                query = ""
                searchFocused = false
                showSearch = false
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.zzInk)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.zzSurface))
        .overlay(Capsule().strokeBorder(Color.zzLine, lineWidth: 0.5))
    }

    @ViewBuilder
    private func editorSheet(_ track: ImportedTrack?) -> some View {
        ManualTrackSheet(
            manager: manager,
            phoneLocation: phoneLocation,
            editingTrack: track,
            initialCenter: trackEditorCenter,
            alignChinaMap: settings.alignChinaMap
        ) { saved in
            save(saved)
        }
    }

    private func save(_ track: ImportedTrack) {
        var tracks = imported
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
        } else {
            tracks.append(track)
        }
        TrackStore.save(tracks)
        imported = tracks
    }
}

private enum ManualGateType: String, CaseIterable, Identifiable {
    case start = "起始线"
    case finish = "终点线"
    case startFinish = "起始/终点线"
    case split = "分段计时线"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .start: return Color.zzGreen
        case .finish: return Color.zzRed
        case .startFinish: return Color.zzAmber
        case .split: return Color(red: 0.35, green: 0.68, blue: 1.0)
        }
    }
}

private struct ManualGate: Identifiable {
    let id = UUID()
    var name: String
    var type: ManualGateType = .start
    var coordinate: CLLocationCoordinate2D
    var heading: Double = 0
    var widthMeters: Double = 20
    var lengthMeters: Double = 80
}

private struct ManualTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var manager: GPSLinkManager
    @ObservedObject var phoneLocation: PhoneLocationProvider

    let editingTrack: ImportedTrack?
    let initialCenter: CLLocationCoordinate2D?
    let alignChinaMap: Bool
    let onSave: (ImportedTrack) -> Void

    @State private var name = ""
    @State private var gates: [ManualGate] = []
    @State private var selectedGateID: UUID?
    @State private var editingGateID: UUID?
    @State private var errorText: String?
    @State private var mapHeight: CGFloat = 600
    @State private var mapSpan: Double = 0.004
    @State private var mapHeading: Double = 0
    @State private var camera: MapCameraPosition
    @State private var didAutoCenter: Bool
    @State private var isSatellite = false

    init(
        manager: GPSLinkManager,
        phoneLocation: PhoneLocationProvider,
        editingTrack: ImportedTrack? = nil,
        initialCenter: CLLocationCoordinate2D? = nil,
        alignChinaMap: Bool = false,
        onSave: @escaping (ImportedTrack) -> Void
    ) {
        self.manager = manager
        self.phoneLocation = phoneLocation
        self.editingTrack = editingTrack
        self.initialCenter = initialCenter
        self.alignChinaMap = alignChinaMap
        self.onSave = onSave

        let loadedGates = editingTrack.map { Self.loadGates(from: $0.jsonData) } ?? []
        _name = State(initialValue: editingTrack?.name ?? "")
        _gates = State(initialValue: loadedGates)

        let trackCenter = loadedGates.first?.coordinate
        _didAutoCenter = State(initialValue: trackCenter != nil || initialCenter != nil)

        if editingTrack != nil, !loadedGates.isEmpty {
            let latitudes = loadedGates.map(\.coordinate.latitude)
            let longitudes = loadedGates.map(\.coordinate.longitude)
            let center = CLLocationCoordinate2D(
                latitude: (latitudes.reduce(0, +) / Double(latitudes.count)),
                longitude: (longitudes.reduce(0, +) / Double(longitudes.count))
            )
            let latitudeSpan = (latitudes.max() ?? center.latitude) - (latitudes.min() ?? center.latitude)
            let longitudeSpan = (longitudes.max() ?? center.longitude) - (longitudes.min() ?? center.longitude)
            let display = ChinaMapAlignment.display(center, enabled: alignChinaMap)
            _camera = State(initialValue: .region(MKCoordinateRegion(
                center: display,
                span: MKCoordinateSpan(
                    latitudeDelta: max(0.002, latitudeSpan * 2 + 0.001),
                    longitudeDelta: max(0.002, longitudeSpan * 2 + 0.001)
                )
            )))
        } else {
            let rawCenter = trackCenter
                ?? initialCenter
                ?? CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
            let center = ChinaMapAlignment.display(rawCenter, enabled: alignChinaMap)
            _camera = State(initialValue: .region(MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            )))
        }
    }

    private static func loadGates(from data: Data) -> [ManualGate] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let track = root["track"] as? [String: Any],
            let traps = track["traps"] as? [[String: Any]]
        else { return [] }

        var gates: [ManualGate] = []
        for trap in traps {
            guard
                let latitudeRaw = (trap["centerLatitude"] as? NSNumber)?.intValue,
                let longitudeRaw = (trap["centerLongitude"] as? NSNumber)?.intValue,
                latitudeRaw != 2147483647,
                longitudeRaw != 2147483647
            else { continue }

            let name = trap["name"] as? String
            let type = (trap["type"] as? String).flatMap(ManualGateType.init(rawValue:))
                ?? (gates.isEmpty ? .startFinish : .split)
            let heading = (trap["heading"] as? NSNumber)?.doubleValue ?? 0
            let width = (trap["width"] as? NSNumber)?.doubleValue ?? 20
            let length = (trap["length"] as? NSNumber)?.doubleValue ?? 80

            gates.append(ManualGate(
                name: name ?? "计时点 \(gates.count + 1)",
                type: type,
                coordinate: CLLocationCoordinate2D(
                    latitude: Double(latitudeRaw) / 10_000_000,
                    longitude: Double(longitudeRaw) / 10_000_000
                ),
                heading: heading,
                widthMeters: width,
                lengthMeters: length
            ))
        }
        return gates
    }

    private var currentLocation: CLLocationCoordinate2D? {
        if let coordinate = phoneLocation.coordinate { return coordinate }
        guard let latitude = manager.trackTelemetry.latitude,
              let longitude = manager.trackTelemetry.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var editingIndex: Int? {
        guard let editingGateID else { return nil }
        return gates.firstIndex { $0.id == editingGateID }
    }

    private var metersPerPoint: Double {
        max(0.05, mapSpan * 111_320 / max(Double(mapHeight), 240))
    }

    private func screenHalfWidth(_ gate: ManualGate) -> CGFloat {
        CGFloat(max(2, gate.widthMeters / 2 / metersPerPoint))
    }

    private func screenArrowLength(_ gate: ManualGate) -> CGFloat {
        CGFloat(max(16, gate.lengthMeters / metersPerPoint))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                nameBar
                mapEditor
            }
            .background(Color.zzCanvas)
            .navigationTitle(editingTrack == nil ? "添加赛道" : "编辑赛道")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("取消")

                    deleteButton
                    addPointsMenu

                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("完成")
                }
                #else
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("取消")

                    deleteButton
                    addPointsMenu

                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("完成")
                }
                #endif
            }
            .onAppear {
                phoneLocation.start()
            }
            .onReceive(phoneLocation.$coordinate) { coordinate in
                guard !didAutoCenter, let coordinate else { return }
                didAutoCenter = true
                let display = ChinaMapAlignment.display(coordinate, enabled: alignChinaMap)
                withAnimation(.easeInOut(duration: 0.3)) {
                    camera = .region(MKCoordinateRegion(
                        center: display,
                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
                    ))
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var deleteButton: some View {
        Button {
            deleteSelectedGate()
        } label: {
            Image(systemName: "trash")
        }
        .disabled(selectedGateID == nil)
        .accessibilityLabel("删除计时点")
    }

    private var addPointsMenu: some View {
        Menu {
            Button {
                addGate()
            } label: {
                Label("添加计时点", systemImage: "plus.circle")
            }
            if !gates.isEmpty {
                Button(role: .destructive) {
                    gates.removeAll()
                    selectedGateID = nil
                    editingGateID = nil
                } label: {
                    Label("清除全部计时点", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("更多")
    }

    private var nameBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)

            TextField("赛道名称", text: $name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.zzInk)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.zzRed)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.zzSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.zzLine).frame(height: 0.5)
        }
    }

    private var mapEditor: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
                // 标注层：已保存计时点交给地图原生标注定位。
                ForEach(Array(gates.enumerated()), id: \.element.id) { index, gate in
                    if gate.id != editingGateID {
                        Annotation(
                            "",
                            coordinate: ChinaMapAlignment.display(gate.coordinate, enabled: alignChinaMap),
                            anchor: .center
                        ) {
                            GateAnnotationView(
                                gate: gate,
                                index: index + 1,
                                halfWidth: screenHalfWidth(gate),
                                arrowLength: screenArrowLength(gate),
                                mapHeading: mapHeading,
                                onTap: {
                                    selectedGateID = gate.id
                                    editingGateID = gate.id
                                }
                            )
                        }
                        .annotationTitles(.hidden)
                    }
                }

                // 当前位置标识。
                if let currentLocation {
                    Annotation(
                        "",
                        coordinate: ChinaMapAlignment.display(currentLocation, enabled: alignChinaMap),
                        anchor: .center
                    ) {
                        CurrentLocationMarker()
                    }
                    .annotationTitles(.hidden)
                }

                // 编辑层：当前计时点 + 控制点。
                if let index = editingIndex {
                    Annotation(
                        "",
                        coordinate: ChinaMapAlignment.display(gates[index].coordinate, enabled: alignChinaMap),
                        anchor: .center
                    ) {
                        GateEditingView(
                            gate: gates[index],
                            index: index + 1,
                            halfWidth: screenHalfWidth(gates[index]),
                            arrowLength: screenArrowLength(gates[index]),
                            mapHeading: mapHeading,
                            onSelect: {
                                selectedGateID = gates[index].id
                                editingGateID = gates[index].id
                            },
                            onMove: { translation in
                                commitMove(gates[index], translation: translation, proxy: proxy)
                            },
                            onHeading: { heading in
                                setHeading(gates[index].id, heading: heading)
                            },
                            onWidth: { halfWidth in
                                setWidth(gates[index].id, halfWidth: halfWidth)
                            },
                            onLength: { arrowLength in
                                setLength(gates[index].id, arrowLength: arrowLength)
                            }
                        )
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(isSatellite ? .imagery(elevation: .flat) : .standard(elevation: .flat))
            .onMapCameraChange(frequency: .continuous) { context in
                mapSpan = context.region.span.latitudeDelta
                mapHeading = context.camera.heading
            }
            .overlay(alignment: .top) {
                if editingIndex != nil {
                    mapTopBar
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                }
            }
            .overlay(alignment: .topTrailing) {
                mapControls
            }
        }
    }

    private func commitMove(_ gate: ManualGate, translation: CGSize, proxy: MapProxy) {
        let display = ChinaMapAlignment.display(gate.coordinate, enabled: alignChinaMap)
        guard let start = proxy.convert(display, to: .local) else { return }
        let target = CGPoint(x: start.x + translation.width, y: start.y + translation.height)
        guard let mapCoordinate = proxy.convert(target, from: .local) else { return }
        moveGate(gate.id, to: ChinaMapAlignment.stored(fromMap: mapCoordinate, enabled: alignChinaMap))
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            Button {
                locateCurrent()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(currentLocation == nil ? Color.zzTertiary : Color.zzInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.zzSurface.opacity(0.96)))
                    .overlay(Circle().strokeBorder(Color.zzLine, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(currentLocation == nil)
            .accessibilityLabel("定位到当前位置")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSatellite.toggle()
                }
            } label: {
                Image(systemName: isSatellite ? "globe.asia.australia.fill" : "map")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.zzSurface.opacity(0.96)))
                    .overlay(Circle().strokeBorder(Color.zzLine, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSatellite ? "切换标准地图" : "切换卫星地图")
        }
        .padding(.top, editingIndex != nil ? 62 : 12)
        .padding(.trailing, 12)
    }

    private var mapTopBar: some View {
        HStack(spacing: 8) {
            if let index = editingIndex {
                TextField("新计时点", text: $gates[index].name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.zzSurface.opacity(0.96)))
                    .overlay(Capsule().strokeBorder(Color.zzLine, lineWidth: 0.5))

                Menu {
                    ForEach(ManualGateType.allCases) { type in
                        Button {
                            gates[index].type = type
                        } label: {
                            if gates[index].type == type {
                                Label(type.rawValue, systemImage: "checkmark")
                            } else {
                                Text(type.rawValue)
                            }
                        }
                    }
                } label: {
                    Text(gates[index].type.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(gates[index].type.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.zzSurface.opacity(0.96)))
                        .overlay(Capsule().strokeBorder(Color.zzLine, lineWidth: 0.5))
                }

                Spacer(minLength: 4)

                Button {
                    finishPointEditing()
                } label: {
                    Text("完成")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.zzCanvas)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.zzInk))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addGate() {
        let mapCenter = camera.region?.center
            ?? ChinaMapAlignment.display(
                initialCenter ?? CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                enabled: alignChinaMap
            )
        let gate = ManualGate(
            name: "新计时点 \(gates.count + 1)",
            coordinate: ChinaMapAlignment.stored(fromMap: mapCenter, enabled: alignChinaMap)
        )
        gates.append(gate)
        selectedGateID = gate.id
        editingGateID = gate.id
        errorText = nil
    }

    private func deleteSelectedGate() {
        guard let selectedGateID else { return }
        gates.removeAll { $0.id == selectedGateID }
        if editingGateID == selectedGateID { editingGateID = nil }
        self.selectedGateID = nil
        errorText = nil
    }

    private func moveGate(_ id: UUID, to coordinate: CLLocationCoordinate2D) {
        guard let index = gates.firstIndex(where: { $0.id == id }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            gates[index].coordinate = coordinate
        }
    }

    private func setHeading(_ id: UUID, heading: Double) {
        guard let index = gates.firstIndex(where: { $0.id == id }) else { return }
        gates[index].heading = heading
    }

    private func setWidth(_ id: UUID, halfWidth: CGFloat) {
        guard let index = gates.firstIndex(where: { $0.id == id }) else { return }
        let meters = Double(halfWidth * 2) * metersPerPoint
        gates[index].widthMeters = min(max(meters, 4), 100)
    }

    private func setLength(_ id: UUID, arrowLength: CGFloat) {
        guard let index = gates.firstIndex(where: { $0.id == id }) else { return }
        let meters = Double(arrowLength) * metersPerPoint
        gates[index].lengthMeters = min(max(meters, 10), 400)
    }

    private func locateCurrent() {
        guard let coordinate = currentLocation else { return }
        if let index = editingIndex {
            gates[index].coordinate = coordinate
        }
        let display = ChinaMapAlignment.display(coordinate, enabled: alignChinaMap)
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .region(MKCoordinateRegion(
                center: display,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            ))
        }
    }

    private func finishPointEditing() {
        editingGateID = nil
        selectedGateID = nil
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = "请输入赛道名称"
            return
        }
        guard !gates.isEmpty else {
            errorText = "请至少添加一个计时点"
            return
        }

        let traps: [[String: Any]] = gates.map { gate in
            [
                "name": gate.name,
                "centerLatitude": Int((gate.coordinate.latitude * 10_000_000).rounded()),
                "centerLongitude": Int((gate.coordinate.longitude * 10_000_000).rounded()),
                "type": gate.type.rawValue,
                "heading": gate.heading,
                "width": gate.widthMeters,
                "length": gate.lengthMeters
            ]
        }
        let track: [String: Any] = [
            "name": trimmed,
            "traps": traps
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: ["track": track]) else {
            errorText = "生成赛道数据失败"
            return
        }

        onSave(ImportedTrack(id: editingTrack?.id ?? UUID().uuidString, name: trimmed, jsonData: data))
        dismiss()
    }
}

private extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

private struct CurrentLocationMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.0, green: 0.478, blue: 1.0).opacity(0.18))
                .frame(width: 34, height: 34)

            Circle()
                .fill(Color(red: 0.0, green: 0.478, blue: 1.0))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
                .shadow(color: Color.black.opacity(0.35), radius: 4, y: 1)
        }
        .accessibilityLabel("当前位置")
    }
}

private struct GateGeometry {
    let gate: ManualGate
    let halfWidth: CGFloat
    let arrowLength: CGFloat
    let canvas: CGFloat
    let mapHeading: Double

    var center: CGPoint { CGPoint(x: canvas / 2, y: canvas / 2) }
    var headHeight: CGFloat { arrowLength * 0.2923 }
    var headWidth: CGFloat { arrowLength * 0.3692 }
    var shaftWidth: CGFloat { arrowLength * 0.1692 }
    var shaftHalfHeight: CGFloat { (arrowLength - headHeight) / 2 }
    var arrowTipAbove: CGFloat { shaftHalfHeight + headHeight }
    var radians: Double { (gate.heading - mapHeading) * .pi / 180 }
    var direction: CGPoint { CGPoint(x: sin(radians), y: -cos(radians)) }
    var perpendicular: CGPoint { CGPoint(x: cos(radians), y: sin(radians)) }

    var tip: CGPoint { center + direction * arrowTipAbove }
    var base: CGPoint { tip - direction * headHeight }
    var tail: CGPoint { center - direction * shaftHalfHeight }
    var widthLeft: CGPoint { center - perpendicular * halfWidth }
    var widthRight: CGPoint { center + perpendicular * halfWidth }
    var badgePoint: CGPoint { center - direction * (max(halfWidth, arrowTipAbove) + 20) }
}

private struct GateArrowBodyShape: Shape {
    let geometry: GateGeometry

    func path(in rect: CGRect) -> Path {
        let g = geometry
        let halfShaft = g.shaftWidth / 2
        let halfHead = g.headWidth / 2

        var path = Path()
        path.move(to: g.tip)
        path.addLine(to: g.base + g.perpendicular * halfHead)
        path.addLine(to: g.base + g.perpendicular * halfShaft)
        path.addLine(to: g.tail + g.perpendicular * halfShaft)
        path.addLine(to: g.tail - g.perpendicular * halfShaft)
        path.addLine(to: g.base - g.perpendicular * halfShaft)
        path.addLine(to: g.base - g.perpendicular * halfHead)
        path.closeSubpath()
        return path
    }
}

private struct GateArrowVisual: View {
    let gate: ManualGate
    let index: Int
    let halfWidth: CGFloat
    let arrowLength: CGFloat
    let canvas: CGFloat
    let mapHeading: Double

    private var geometry: GateGeometry {
        GateGeometry(gate: gate, halfWidth: halfWidth, arrowLength: arrowLength, canvas: canvas, mapHeading: mapHeading)
    }

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: geometry.widthLeft)
                path.addLine(to: geometry.widthRight)
            }
            .stroke(gate.type.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))

            GateArrowBodyShape(geometry: geometry)
                .fill(gate.type.color.opacity(0.45))

            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.zzCanvas)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(gate.type.color))
                .position(geometry.badgePoint)
        }
        .frame(width: canvas, height: canvas)
    }
}

private struct GateAnnotationView: View {
    let gate: ManualGate
    let index: Int
    let halfWidth: CGFloat
    let arrowLength: CGFloat
    let mapHeading: Double
    let onTap: () -> Void

    private var canvas: CGFloat { max(320, max(halfWidth * 2, arrowLength) + 120) }
    private var geometry: GateGeometry {
        GateGeometry(gate: gate, halfWidth: halfWidth, arrowLength: arrowLength, canvas: canvas, mapHeading: mapHeading)
    }

    var body: some View {
        GateArrowVisual(
            gate: gate,
            index: index,
            halfWidth: halfWidth,
            arrowLength: arrowLength,
            canvas: canvas,
            mapHeading: mapHeading
        )
        .contentShape(GateArrowBodyShape(geometry: geometry))
        .onTapGesture { onTap() }
    }
}

private struct GateEditingView: View {
    let gate: ManualGate
    let index: Int
    let halfWidth: CGFloat
    let arrowLength: CGFloat
    let mapHeading: Double
    let onSelect: () -> Void
    let onMove: (CGSize) -> Void
    let onHeading: (Double) -> Void
    let onWidth: (CGFloat) -> Void
    let onLength: (CGFloat) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingBody = false
    @State private var tipStart: TipStart?
    @State private var widthStart: WidthStart?
    @State private var lengthStart: LengthStart?

    private struct TipStart {
        let heading: Double
        let angle: Double
    }

    private struct WidthStart {
        let halfWidth: CGFloat
        let distance: CGFloat
    }

    private struct LengthStart {
        let arrowLength: CGFloat
        let distance: CGFloat
    }

    private var canvas: CGFloat { max(320, max(halfWidth * 2, arrowLength) + 120) }
    private var geometry: GateGeometry {
        GateGeometry(gate: gate, halfWidth: halfWidth, arrowLength: arrowLength, canvas: canvas, mapHeading: mapHeading)
    }

    var body: some View {
        ZStack {
            GateArrowVisual(
                gate: gate,
                index: index,
                halfWidth: halfWidth,
                arrowLength: arrowLength,
                canvas: canvas,
                mapHeading: mapHeading
            )
            .allowsHitTesting(false)

            GateArrowBodyShape(geometry: geometry)
                .fill(Color.white.opacity(0.001))
                .contentShape(GateArrowBodyShape(geometry: geometry))
                .gesture(bodyDrag)

            handle(at: geometry.tip, icon: "arrow.triangle.2.circlepath")
                .gesture(tipDrag)

            handle(at: geometry.widthLeft, icon: "arrow.left.and.right")
                .gesture(widthDrag)

            handle(at: geometry.widthRight, icon: "arrow.left.and.right")
                .gesture(widthDrag)

            handle(at: geometry.tail, icon: "arrow.up.and.down")
                .gesture(lengthDrag)
        }
        .frame(width: canvas, height: canvas)
        .coordinateSpace(name: "gate-edit-space")
        .offset(dragOffset)
    }

    private var bodyDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if !isDraggingBody {
                    isDraggingBody = true
                    onSelect()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                onMove(value.translation)
                dragOffset = .zero
                isDraggingBody = false
            }
    }

    private var tipDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gate-edit-space"))
            .onChanged { value in
                let dx = value.location.x - geometry.center.x
                let dy = value.location.y - geometry.center.y
                let angle = atan2(dx, -dy) * 180 / .pi

                if tipStart == nil {
                    tipStart = TipStart(heading: gate.heading, angle: angle)
                }
                guard let start = tipStart else { return }

                var delta = angle - start.angle
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }

                var heading = (start.heading + delta).truncatingRemainder(dividingBy: 360)
                if heading < 0 { heading += 360 }
                onHeading(heading)
            }
            .onEnded { _ in tipStart = nil }
    }

    private var widthDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gate-edit-space"))
            .onChanged { value in
                let distance = hypot(value.location.x - geometry.center.x, value.location.y - geometry.center.y)
                if widthStart == nil {
                    widthStart = WidthStart(halfWidth: halfWidth, distance: distance)
                }
                guard let start = widthStart else { return }
                onWidth(start.halfWidth + (distance - start.distance))
            }
            .onEnded { _ in widthStart = nil }
    }

    private var lengthDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gate-edit-space"))
            .onChanged { value in
                let distance = hypot(value.location.x - geometry.center.x, value.location.y - geometry.center.y)
                if lengthStart == nil {
                    lengthStart = LengthStart(arrowLength: arrowLength, distance: distance)
                }
                guard let start = lengthStart else { return }
                let tailRatio: CGFloat = 0.3538
                onLength(start.arrowLength + (distance - start.distance) / tailRatio)
            }
            .onEnded { _ in lengthStart = nil }
    }

    private func handle(at point: CGPoint, icon: String) -> some View {
        Circle()
            .fill(Color.zzSurface)
            .overlay(Circle().strokeBorder(gate.type.color, lineWidth: 1.5))
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(gate.type.color)
            )
            .frame(width: 28, height: 28)
            .position(point)
    }
}

// MARK: - Track library maps

private struct TrackMapInfo: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let resource: String?
    let jsonData: Data?
}

private enum TrackMapCatalog {
    static let builtIn: [TrackMapInfo] = [
        TrackMapInfo(
            id: "tianma",
            name: "天马",
            subtitle: "",
            resource: "tianma_track",
            jsonData: nil
        ),
        TrackMapInfo(
            id: "taicang",
            name: "太仓极速星辰",
            subtitle: "",
            resource: "taicang_track",
            jsonData: nil
        )
    ]

    static func tracks(imported: [ImportedTrack]) -> [TrackMapInfo] {
        // Only imported .rcz tracks are listed. The built-in 天马/太仓 cards
        // are kept in the project but intentionally not shown here.
        imported.map {
            let raw = $0.name
            let name = raw.hasPrefix("track_")
                ? String(raw.dropFirst("track_".count))
                : raw
            return TrackMapInfo(
                id: $0.id,
                name: name,
                subtitle: "",
                resource: nil,
                jsonData: $0.jsonData
            )
        }
    }

    static func load(_ track: TrackMapInfo) -> RaceChronoTrackFile? {
        let data: Data?
        if let jsonData = track.jsonData {
            data = jsonData
        } else if let resource = track.resource {
            data = Bundle.main.url(forResource: resource, withExtension: "json").flatMap {
                try? Data(contentsOf: $0)
            }
        } else {
            data = nil
        }

        guard let data else { return nil }
        return try? JSONDecoder().decode(RaceChronoTrackFile.self, from: data)
    }
}

private struct ImportedTrack: Codable, Identifiable {
    let id: String
    let name: String
    let jsonData: Data
}

private enum TrackStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ZAZARAImportedTracks", isDirectory: true)
    }

    private static var fileURL: URL {
        directory.appendingPathComponent("tracks.json")
    }

    static func load() -> [ImportedTrack] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ImportedTrack].self, from: data)) ?? []
    }

    static func save(_ tracks: [ImportedTrack]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private enum TrackImporter {
    static let contentType = UTType(filenameExtension: "rcz") ?? .data

    static func importTrack(from url: URL) throws -> ImportedTrack {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["trackId.json"] else {
            throw NSError(
                domain: "ZAZARA.RCZ",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "rcz 里没有 trackId.json"]
            )
        }

        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }

        let rawName = url.deletingPathExtension().lastPathComponent
        let name = rawName.hasPrefix("track_")
            ? String(rawName.dropFirst("track_".count))
            : rawName

        return ImportedTrack(
            id: UUID().uuidString,
            name: name,
            jsonData: data
        )
    }
}

private struct RaceChronoTrackFile: Decodable {
    let id: Int64?
    let track: RaceChronoTrack?
}

private struct RaceChronoTrack: Decodable {
    let name: String?
    let description: String?
    let traps: [RaceChronoTrap]?
}

private struct RaceChronoTrap: Decodable, Identifiable {
    let name: String?
    let centerLatitude: Int?
    let centerLongitude: Int?

    var id: String {
        "\(name ?? "trap")-\(centerLatitude ?? 0)-\(centerLongitude ?? 0)"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard
            let latitude = centerLatitude,
            let longitude = centerLongitude,
            latitude != .max,
            longitude != .max
        else { return nil }

        return CLLocationCoordinate2D(
            latitude: Double(latitude) / 10_000_000,
            longitude: Double(longitude) / 10_000_000
        )
    }
}

private struct TrackNameRow: View {
    let track: TrackMapInfo
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(track.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.zzTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.zzInk.opacity(isSelected ? 0.08 : 0))
        )
    }
}

private struct TrackEditorItem: Identifiable {
    let id = UUID()
    let track: ImportedTrack?
}

private struct TrackDetailSheet: View {
    let track: TrackMapInfo
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var file: RaceChronoTrackFile?

    private var traps: [RaceChronoTrap] {
        file?.track?.traps ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TrackMapCanvas(traps: traps)
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if traps.isEmpty {
                        Text("这个 .rcz 只有赛道 ID，没有坐标；导入带轨迹的 .rcz 或手动添加坐标后才能显示地图。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.zzSecondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.zzCanvas)
            .navigationTitle(track.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { onEdit() }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑") { onEdit() }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear {
            file = TrackMapCatalog.load(track)
        }
    }
}

private struct TrackMapCanvas: View {
    let traps: [RaceChronoTrap]

    @EnvironmentObject private var settings: AppSettings
    @State private var camera: MapCameraPosition = .automatic

    private var hasCoordinates: Bool {
        traps.contains { $0.coordinate != nil }
    }

    var body: some View {
        if hasCoordinates {
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
                ForEach(traps) { trap in
                    if let coordinate = trap.coordinate {
                        Annotation(
                            trap.name ?? "",
                            coordinate: ChinaMapAlignment.display(coordinate, enabled: settings.alignChinaMap)
                        ) {
                            Circle()
                                .fill(Color.zzRed)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.zzInk, lineWidth: 2))
                                .shadow(color: .black.opacity(0.4), radius: 3)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
        } else {
            ZStack {
                Color.zzMutedSurface

                VStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.zzTertiary)

                    Text("缺少赛道坐标")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.zzTertiary)
                }
            }
        }
    }
}

private struct ZZComingSoonCard: View {
    let icon: String
    var useTrackIcon: Bool = false
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.zzRedSoft)
                    .frame(width: 78, height: 78)

                if useTrackIcon {
                    ZZTrackShape()
                        .stroke(
                            Color.zzInk,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 40, height: 32)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.zzInk)
                }
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.zzInk)

                Text(message)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text(actionTitle)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 20)
            }
            .buttonStyle(ZZPrimaryButtonStyle())
            .frame(maxWidth: 310)

            Text(settings.t("NEXT MILESTONE"))
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.zzTertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .zzCard(cornerRadius: 22)
    }
}

// MARK: - Mine

struct MoreView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("Mine"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    accountSection
                    settingsSection
                    aboutSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.zzCanvas)
        }
        .background(Color.zzCanvas.ignoresSafeArea())
        .confirmationDialog(
            settings.t("Delete all devices?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(settings.t("Delete all"), role: .destructive) {
                manager.clearSavedRecords()
            }
            Button(settings.t("Cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("This removes every saved device and disconnects the active GPS module."))
        }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZZSectionHeader(title: settings.t("Account"))

            VStack(spacing: 0) {
                settingsRow(
                    icon: "person.crop.circle",
                    title: settings.t("Account"),
                    value: settings.t("Not signed in"),
                    showsChevron: false
                )
            }
            .zzCard(cornerRadius: 16)
        }
    }

    // MARK: Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZZSectionHeader(title: settings.t("Settings"))

            languageCard
            gpsSettingsCard
            mapAlignmentCard

            Text(settings.t("Deleting devices disconnects the active GPS module."))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.zzTertiary)
                .padding(.horizontal, 4)
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.zzMutedSurface))

                Text(settings.t("App language"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.zzInk)

                Spacer(minLength: 8)
            }

            Picker("", selection: $settings.language) {
                Text("English").tag(AppLanguage.english)
                Text("简体中文").tag(AppLanguage.chinese)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(settings.t("Language"))

            Text(settings.t("Changes apply immediately throughout the app."))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.zzTertiary)
        }
        .padding(14)
        .zzCard(cornerRadius: 16)
    }

    private var mapAlignmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $settings.alignChinaMap) {
                HStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.zzMutedSurface))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.t("Align to China map"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.zzInk)

                        Text(settings.t("Render WGS84 tracks and routes aligned to the Chinese map (GCJ-02). Stored data stays WGS84."))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.zzTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Color.zzGreen)

            Text(settings.t("Only affects map display. Imported .rcz tracks and recorded GPS data keep their original WGS84 coordinates."))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.zzTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .zzCard(cornerRadius: 16)
    }

    private var gpsSettingsCard: some View {
        VStack(spacing: 0) {
            Button {
                ZZPlatform.openBluetoothSettings()
            } label: {
                settingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: settings.t("Bluetooth"),
                    value: manager.zzStatus(language: settings.language).text,
                    showsChevron: true
                )
            }
            .buttonStyle(ZZCardButtonStyle())

            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)
                .padding(.leading, 56)

            Button {
                showClearConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.zzRedSoft))

                    Text(settings.t("Delete all devices"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.zzRed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer()

                    if manager.savedModules.isEmpty {
                        Text(settings.t("None"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.zzTertiary)
                    }
                }
                .padding(14)
            }
            .buttonStyle(ZZCardButtonStyle())
            .disabled(manager.savedModules.isEmpty)
        }
        .zzCard(cornerRadius: 16)
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZZSectionHeader(title: settings.t("About"))

            VStack(spacing: 0) {
                settingsRow(
                    icon: "info.circle",
                    title: settings.t("Version"),
                    value: versionDisplay,
                    showsChevron: false
                )
                Rectangle()
                    .fill(Color.zzLine)
                    .frame(height: 0.5)
                    .padding(.leading, 56)
                settingsRow(
                    icon: "location.north.circle",
                    title: settings.t("Protocol"),
                    value: settings.t("Bluetooth LE"),
                    showsChevron: false
                )
            }
            .zzCard(cornerRadius: 16)
        }
    }

    private var versionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private var footer: some View {
        VStack(spacing: 6) {
            ZZWordmark()
            Text(settings.t("TRACK GRADE GPS LINK"))
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.zzTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func settingsRow(
        icon: String,
        title: String,
        value: String,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.zzInk)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.zzMutedSurface))

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.zzInk)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.zzTertiary)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

private struct TrackDashboardView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings

    @State private var rangeMax: Double = 60
    @State private var points: [GForcePoint] = []
    @State private var lastDate: Date?
    @State private var lastSpeedMS: Double?
    @State private var lastHeading: Double?
    @State private var lateralG: Double = 0
    @State private var longitudinalG: Double = 0
    @State private var nextPointID: Int = 0

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            let horizontalPadding: CGFloat = 12
            let verticalPadding: CGFloat = 8
            let contentWidth = max(0, proxy.size.width - horizontalPadding * 2)
            let contentHeight = max(0, proxy.size.height - verticalPadding * 2)
            let isWide = proxy.size.width > proxy.size.height

            Group {
                if isWide {
                    let side = min(
                        contentWidth * 0.42,
                        (contentHeight - spacing) / 2
                    )

                    HStack(spacing: spacing) {
                        gaugePanel

                        VStack(spacing: spacing) {
                            gForcePanel
                                .frame(width: side, height: side)
                            routePanel
                                .frame(width: side, height: side)
                        }
                        .frame(width: side)
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                } else {
                    let side = min(
                        contentHeight * 0.36,
                        (contentWidth - spacing) / 2
                    )

                    VStack(spacing: spacing) {
                        gaugePanel

                        HStack(spacing: spacing) {
                            gForcePanel
                                .frame(width: side, height: side)
                            routePanel
                                .frame(width: side, height: side)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .zzOnChange(of: manager.trackTelemetry) { telemetry in
            consume(telemetry)
        }
        .zzOnChange(of: manager.linkState) { state in
            if state != .connected {
                reset()
            }
        }
    }

    private var speed: Double {
        max(0, manager.trackTelemetry.speedKPH ?? 0)
    }

    private var rateText: String {
        let rate = manager.trackTelemetry.updateRateHz
        return rate > 0 ? String(format: "%.1f Hz", rate) : "— Hz"
    }

    private var gaugePanel: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.t("Speed"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)

                Spacer(minLength: 6)

                Text(rateText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzSecondary)
            }

            Gauge(value: speed, in: 0...rangeMax) {
                Text(settings.t("Speed"))
            } currentValueLabel: {
                VStack(spacing: 2) {
                    Text("\(Int(speed.rounded()))")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.zzInk)

                    Text("km/h")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.zzSecondary)
                }
            }
            .gaugeStyle(CarDialGaugeStyle(rangeMax: rangeMax))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zzCard(cornerRadius: 18)
    }

    private var gForcePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.t("G-Force"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)

                Spacer(minLength: 6)
            }

            Chart {
                RuleMark(x: .value("Lateral", 0))
                    .foregroundStyle(Color.zzLine)
                RuleMark(y: .value("Longitudinal", 0))
                    .foregroundStyle(Color.zzLine)

                ForEach(points) { point in
                    PointMark(
                        x: .value("Lateral", point.lateral),
                        y: .value("Longitudinal", point.longitudinal)
                    )
                    .symbolSize(pointSize(point))
                    .foregroundStyle(pointColor(point))
                }
            }
            .chartXScale(domain: -2...2)
            .chartYScale(domain: -2...2)
            .chartXAxis {
                AxisMarks(values: [-2.0, -1.0, 0.0, 1.0, 2.0]) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.zzLine.opacity(0.45))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number == 0 ? "0" : "\(Int(number))g")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.zzTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [-2.0, -1.0, 0.0, 1.0, 2.0]) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.zzLine.opacity(0.45))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number == 0 ? "0" : "\(Int(number))g")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.zzTertiary)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.background(Color.zzMutedSurface.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if points.isEmpty {
                    Text(settings.t("No G data yet"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.zzTertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zzCard(cornerRadius: 18)
    }

    private var routePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.t("Route"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)

                Spacer(minLength: 6)

                Text(String(format: "%.2f", manager.trackTelemetry.distanceKm))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Canvas { context, size in
                drawRoute(context: &context, size: size)
            }
            .background(
                Color.zzMutedSurface.opacity(0.3),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if manager.trackTelemetry.route.count < 2 {
                    Text(settings.t("No route data yet"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.zzTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .zzCard(cornerRadius: 18)
    }

    private func pointSize(_ point: GForcePoint) -> CGFloat {
        nextPointID - point.id == 0 ? 70 : 20
    }

    private func pointColor(_ point: GForcePoint) -> Color {
        let age = max(0, nextPointID - point.id)
        return Color.zzRed.opacity(max(0.12, 1 - Double(age) / 160))
    }

    private func drawRoute(context: inout GraphicsContext, size: CGSize) {
        let route = manager.trackTelemetry.route
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        guard rect.width > 20, rect.height > 20 else { return }

        var grid = Path()
        for step in 0...4 {
            let x = rect.minX + rect.width * CGFloat(step) / 4
            let y = rect.minY + rect.height * CGFloat(step) / 4
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.addLine(to: CGPoint(x: x, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(
            grid,
            with: .color(Color.zzLine.opacity(0.35)),
            style: StrokeStyle(lineWidth: 0.5)
        )

        guard route.count > 1 else { return }

        let latitudes = route.map(\.latitude)
        let longitudes = route.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }

        let spanLat = max(maxLat - minLat, 0.000001)
        let spanLon = max(maxLon - minLon, 0.000001)
        let scale = min(rect.width / CGFloat(spanLon), rect.height / CGFloat(spanLat))
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2

        func project(_ latitude: Double, _ longitude: Double) -> CGPoint {
            CGPoint(
                x: rect.midX + CGFloat(longitude - centerLon) * scale,
                y: rect.midY - CGFloat(latitude - centerLat) * scale
            )
        }

        var path = Path()
        path.move(to: project(route[0].latitude, route[0].longitude))
        for point in route.dropFirst() {
            path.addLine(to: project(point.latitude, point.longitude))
        }
        context.stroke(
            path,
            with: .color(Color.zzRed),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        let start = project(route[0].latitude, route[0].longitude)
        let end = project(route[route.count - 1].latitude, route[route.count - 1].longitude)

        context.fill(
            Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)),
            with: .color(Color.zzGreen)
        )

        let endRect = CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: endRect), with: .color(Color.zzRed))
        context.stroke(
            Path(ellipseIn: endRect),
            with: .color(Color.white.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1)
        )
    }

    private func consume(_ telemetry: TrackTelemetry) {
        let speedKPH = max(0, telemetry.speedKPH ?? 0)
        let required = min(480, max(60, ceil((speedKPH + 10) / 60) * 60))
        if required > rangeMax {
            withAnimation(.easeOut(duration: 0.35)) {
                rangeMax = required
            }
        }

        guard let date = telemetry.date else { return }
        let speedMS = speedKPH / 3.6
        let previousDate = lastDate
        let previousSpeedMS = lastSpeedMS
        let previousHeading = lastHeading
        lastDate = date
        lastSpeedMS = speedMS
        lastHeading = telemetry.heading

        guard let previousDate, let previousSpeedMS else { return }
        let dt = date.timeIntervalSince(previousDate)
        guard dt > 0.02, dt < 2 else { return }

        let longitudinal = (speedMS - previousSpeedMS) / dt / 9.80665
        var lateral = 0.0
        if let heading = telemetry.heading, let previousHeading {
            var delta = heading - previousHeading
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            lateral = speedMS * (delta * .pi / 180 / dt) / 9.80665
        }

        lateralG = filtered(lateralG, with: lateral)
        longitudinalG = filtered(longitudinalG, with: longitudinal)

        points.append(
            GForcePoint(
                id: nextPointID,
                lateral: min(max(lateralG, -2), 2),
                longitudinal: min(max(longitudinalG, -2), 2)
            )
        )
        nextPointID += 1
        if points.count > 160 {
            points.removeFirst(points.count - 160)
        }
    }

    private func filtered(_ current: Double, with sample: Double) -> Double {
        let clamped = min(max(sample, -4), 4)
        return current * 0.7 + clamped * 0.3
    }

    private func reset() {
        points.removeAll()
        lastDate = nil
        lastSpeedMS = nil
        lastHeading = nil
        lateralG = 0
        longitudinalG = 0
        rangeMax = 60
        nextPointID = 0
    }
}

private struct CarDialGaugeStyle: GaugeStyle {
    let rangeMax: Double

    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: .bottom) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height - 72)
                let radius = max(20, min(size.width / 2 - 18, size.height - 72 - 12))
                let value = min(max(configuration.value, 0), 1)

                func point(_ fraction: CGFloat, scale: CGFloat = 1) -> CGPoint {
                    let angle = Double.pi + Double.pi * Double(fraction)
                    return CGPoint(
                        x: center.x + radius * scale * CGFloat(cos(angle)),
                        y: center.y + radius * scale * CGFloat(sin(angle))
                    )
                }

                var track = Path()
                for step in 0...120 {
                    let p = point(CGFloat(step) / 120)
                    if step == 0 {
                        track.move(to: p)
                    } else {
                        track.addLine(to: p)
                    }
                }
                context.stroke(
                    track,
                    with: .color(Color.zzMutedSurface),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )

                if value > 0 {
                    let activeSteps = max(1, Int(120 * value))
                    var active = Path()
                    for step in 0...activeSteps {
                        let p = point(CGFloat(step) / 120)
                        if step == 0 {
                            active.move(to: p)
                        } else {
                            active.addLine(to: p)
                        }
                    }
                    context.stroke(
                        active,
                        with: .color(Color.zzRed),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                }

                let majorSteps = 6
                for step in 0...majorSteps {
                    let fraction = CGFloat(step) / CGFloat(majorSteps)

                    var major = Path()
                    major.move(to: point(fraction, scale: 0.9))
                    major.addLine(to: point(fraction, scale: 0.98))
                    context.stroke(
                        major,
                        with: .color(Color.zzSecondary.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )

                    let label = Text("\(Int(rangeMax * Double(fraction)))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    context.draw(label, at: point(fraction, scale: 0.78))
                }

                let minorSteps = 30
                for step in 0...minorSteps where step % 5 != 0 {
                    let fraction = CGFloat(step) / CGFloat(minorSteps)
                    var minor = Path()
                    minor.move(to: point(fraction, scale: 0.93))
                    minor.addLine(to: point(fraction, scale: 0.98))
                    context.stroke(
                        minor,
                        with: .color(Color.zzTertiary.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
                    )
                }

                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: point(CGFloat(value), scale: 0.88))
                context.stroke(
                    needle,
                    with: .color(Color.zzRed),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )

                let hubRect = CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: hubRect), with: .color(Color.zzInk))
                context.fill(
                    Path(ellipseIn: hubRect.insetBy(dx: 3, dy: 3)),
                    with: .color(Color.zzRed)
                )
            }

            configuration.currentValueLabel
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DragTimingMetric: Identifiable {
    let id: String
    let title: String
    let unit: String
    let icon: String
}

private enum DragAddMode: String {
    case speed
    case distance

    var titleKey: String {
        switch self {
        case .speed: return "By speed"
        case .distance: return "By distance"
        }
    }

    var dialogTitleKey: String {
        switch self {
        case .speed: return "Add by speed"
        case .distance: return "Add by distance"
        }
    }

    var startLabelKey: String {
        switch self {
        case .speed: return "Start speed"
        case .distance: return "Start distance"
        }
    }

    var endLabelKey: String {
        switch self {
        case .speed: return "End speed"
        case .distance: return "End distance"
        }
    }

    var unit: String {
        switch self {
        case .speed: return "km/h"
        case .distance: return "m"
        }
    }

    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .distance: return "ruler"
        }
    }
}

private enum DragInputField: Hashable {
    case start
    case end
}

struct DragTimingView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showAddOptions = false
    @State private var addMode: DragAddMode?
    @State private var startValue = ""
    @State private var endValue = ""
    @State private var customMetrics: [DragTimingMetric] = []
    @FocusState private var focusedField: DragInputField?

    var body: some View {
        ZStack {
            Color.zzCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        addControl
                        metricsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }

            if let addMode {
                addDialog(addMode)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle(settings.t("Drag"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }


    private var addControl: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if showAddOptions {
                HStack(spacing: 5) {
                    addOption(.speed)
                    addOption(.distance)

                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showAddOptions = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.zzSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.zzMutedSurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.t("Cancel"))
                }
                .padding(5)
                .background(Capsule().fill(Color.zzSurface))
                .overlay(Capsule().stroke(Color.zzLine, lineWidth: 0.7))
                .transition(
                    .scale(scale: 0.86, anchor: .trailing)
                        .combined(with: .opacity)
                )
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showAddOptions = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.zzRed))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("Add"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showAddOptions)
    }

    private func addOption(_ mode: DragAddMode) -> some View {
        Button {
            openAddDialog(mode)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
                Text(settings.t(mode.titleKey))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.zzRed)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.zzRedSoft))
        }
        .buttonStyle(.plain)
    }

    private var metrics: [DragTimingMetric] {
        [
            DragTimingMetric(id: "0-100", title: "0–100", unit: "km/h", icon: "speedometer"),
            DragTimingMetric(id: "60-160", title: "60–160", unit: "km/h", icon: "speedometer"),
            DragTimingMetric(id: "100-200", title: "100–200", unit: "km/h", icon: "speedometer"),
            DragTimingMetric(id: "0-200", title: "0–200", unit: "km/h", icon: "speedometer"),
            DragTimingMetric(id: "80-130", title: "80–130", unit: "km/h", icon: "speedometer"),
            DragTimingMetric(id: "quarter-mile", title: settings.t("1/4 mile"), unit: "402 m", icon: "flag.checkered")
        ] + customMetrics
    }

    private var metricsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(Color.zzLine)
                        .frame(height: 0.5)
                        .padding(.leading, 64)
                }
                metricRow(metric)
            }
        }
        .zzCard(cornerRadius: 18)
    }

    private func metricRow(_ metric: DragTimingMetric) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.zzRedSoft)
                    .frame(width: 38, height: 38)

                Image(systemName: metric.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Color.zzInk)

                Text(metric.unit)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
            }

            Spacer(minLength: 8)

            Text("—")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzTertiary)

            Text("s")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.zzTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func openAddDialog(_ mode: DragAddMode) {
        startValue = ""
        endValue = ""
        withAnimation(.easeOut(duration: 0.18)) {
            showAddOptions = false
            addMode = mode
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            focusedField = .start
        }
    }

    private func closeAddDialog() {
        focusedField = nil
        withAnimation(.easeOut(duration: 0.18)) {
            addMode = nil
        }
        startValue = ""
        endValue = ""
    }

    private var canSave: Bool {
        guard
            let start = Int(startValue),
            let end = Int(endValue)
        else { return false }
        return end > start
    }

    private func saveCustomMetric(_ mode: DragAddMode) {
        guard
            let start = Int(startValue),
            let end = Int(endValue),
            end > start
        else { return }

        customMetrics.append(
            DragTimingMetric(
                id: UUID().uuidString,
                title: "\(start)–\(end)",
                unit: mode.unit,
                icon: mode.icon
            )
        )
        closeAddDialog()
    }

    private func addDialog(_ mode: DragAddMode) -> some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .onTapGesture(perform: closeAddDialog)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(settings.t(mode.dialogTitleKey))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.zzInk)

                    Spacer(minLength: 8)

                    Button {
                        closeAddDialog()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.zzSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.zzMutedSurface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(settings.t("Cancel"))
                }

                Text(settings.t("Only numbers are allowed."))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)

                numericField(
                    titleKey: mode.startLabelKey,
                    text: $startValue,
                    unit: mode.unit,
                    field: .start
                )

                numericField(
                    titleKey: mode.endLabelKey,
                    text: $endValue,
                    unit: mode.unit,
                    field: .end
                )

                HStack(spacing: 10) {
                    Button(settings.t("Cancel")) {
                        closeAddDialog()
                    }
                    .buttonStyle(ZZSecondaryButtonStyle())

                    Button(settings.t("Save")) {
                        saveCustomMetric(mode)
                    }
                    .buttonStyle(ZZPrimaryButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .zzCard(cornerRadius: 22)
            .padding(24)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .zIndex(20)
    }

    private func numericField(
        titleKey: String,
        text: Binding<String>,
        unit: String,
        field: DragInputField
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t(titleKey))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.zzSecondary)

            HStack(spacing: 8) {
                TextField("0", text: text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzInk)
                    .tint(Color.zzRed)
                    .focused($focusedField, equals: field)
                    .zzOnChange(of: text.wrappedValue) { newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            text.wrappedValue = filtered
                        }
                    }

                Text(unit)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.zzMutedSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Track telemetry page

private enum TrackTileID {
    static let defaultOrder = [
        "time", "satellites", "coordDOP",
        "fix", "heading", "altitude",
        "altDOP", "latitude", "longitude",
        "elapsed", "distance", "speed"
    ]

    static let all = Set(defaultOrder)
}

private struct TrackTileData {
    let label: String
    let value: String
    let unit: String
    var secondary: String? = nil
}

private struct TrackDataTile: View {
    let data: TrackTileData
    let isEditing: Bool
    var compact: Bool = false
    var fixedHeight: CGFloat? = nil

    var body: some View {
        Group {
            if let fixedHeight {
                tile.frame(height: fixedHeight)
            } else {
                tile.aspectRatio(1.2, contentMode: .fit)
            }
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(data.label)
                .font(.system(size: compact ? 9.5 : 10.5, weight: .medium))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 3)

            Text(data.value)
                .font(.system(size: compact ? 26 : 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.34)

            if let secondary = data.secondary {
                Text(secondary)
                    .font(.system(size: compact ? 9 : 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Text(data.unit)
                    .font(.system(size: compact ? 9 : 9.5, weight: .medium))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
            }
        }
        .padding(compact ? 7 : 8)
        .frame(maxWidth: .infinity)
        .background(Color.zzSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isEditing ? Color.zzRed.opacity(0.55) : Color.zzLine,
                    lineWidth: isEditing ? 1.2 : 0.8
                )
        )
    }
}

private struct TrackTileDropDelegate: DropDelegate {
    let itemID: String
    @Binding var order: [String]
    @Binding var draggingID: String?

    func dropEntered(info: DropInfo) {
        guard
            let draggingID,
            draggingID != itemID,
            let from = order.firstIndex(of: draggingID),
            let to = order.firstIndex(of: itemID)
        else { return }

        withAnimation(.easeInOut(duration: 0.16)) {
            order.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

struct TrackTimingView: View {
    @ObservedObject var manager: GPSLinkManager

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("zazara.trackTileOrder.v1") private var orderRaw = ""
    @State private var order = TrackTileID.defaultOrder
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    #endif
    @State private var draggingID: String?
    @State private var section: TrackSection = .overview
    @Namespace private var sectionNamespace

    private var isEditing: Bool {
        #if os(iOS)
        editMode?.wrappedValue.isEditing == true
        #else
        false
        #endif
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        ZStack {
            Color.zzCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                #if os(iOS)
                TabView(selection: $section) {
                    overviewContent
                        .tag(TrackSection.overview)

                    TrackDashboardView(manager: manager)
                        .tag(TrackSection.dashboard)

                    TrackTimingMapView(manager: manager)
                        .tag(TrackSection.timing)

                    TrackFullMapView(manager: manager)
                        .tag(TrackSection.map)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #else
                ZStack {
                    overviewContent
                        .opacity(section == .overview ? 1 : 0)
                        .allowsHitTesting(section == .overview)

                    TrackDashboardView(manager: manager)
                        .opacity(section == .dashboard ? 1 : 0)
                        .allowsHitTesting(section == .dashboard)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif

                #if os(macOS)
                sectionBar
                #endif
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle(settings.t(section.titleKey))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) {
                sectionToolbarButtons
            }
            if section == .overview {
                ToolbarItem(placement: .topBarTrailing) {
                    editToolbarButton
                }
            }
            #endif
        }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .onAppear(perform: normalizeOrder)
        .zzOnChange(of: order) { newOrder in
            orderRaw = newOrder.joined(separator: ",")
        }
    }



    private var rateText: String {
        let rate = manager.trackTelemetry.updateRateHz
        return rate > 0 ? String(format: "%.1f Hz", rate) : "— Hz"
    }

    private var overviewContent: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscapeOverview(in: proxy.size)
            } else {
                portraitOverview
            }
        }
    }

    private var portraitOverview: some View {
        ScrollView {
            VStack(spacing: 10) {
                overviewStatusHeader

                if isEditing {
                    overviewStatusRow
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(order, id: \.self) { id in
                        tileCell(id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func landscapeOverview(in size: CGSize) -> some View {
        let horizontalPadding: CGFloat = 16
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 8
        let spacing: CGFloat = 8
        let headerHeight: CGFloat = 50
        let statusRowHeight: CGFloat = isEditing ? 28 : 0
        let availableHeight = max(
            0,
            size.height - topPadding - bottomPadding - headerHeight - statusRowHeight - spacing * 2
        )
        let tileHeight = max(0, (availableHeight - spacing * 3) / 4)

        return VStack(spacing: spacing) {
            overviewStatusHeader

            if isEditing {
                overviewStatusRow
            }

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(order, id: \.self) { id in
                    tileCell(id, compact: true, fixedHeight: tileHeight)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var overviewStatusHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(connectedModuleTitle)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                Text("Bluetooth LE GPS")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.zzSecondary)

                Spacer(minLength: 8)

                Text(rateText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 14)
    }

    private var connectedModuleTitle: String {
        guard let module = manager.connectedModule else {
            return settings.t("Not connected")
        }
        return "\(module.name) #\(module.shortID)"
    }

    private var overviewStatusRow: some View {
        HStack(spacing: 8) {
            if isEditing {
                Text(settings.t("Drag tiles to reorder"))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.zzTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }

    #if os(iOS)
    @ViewBuilder
    private var sectionToolbarButtons: some View {
        ForEach(TrackSection.allCases) { item in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    section = item
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(settings.t(item.titleKey))
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .tint(section == item ? Color.zzInk : Color.zzSecondary)
            .accessibilityAddTraits(section == item ? .isSelected : [])
        }
    }
    #endif

    private var sectionBar: some View {
        HStack(spacing: 4) {
            ForEach(TrackSection.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        section = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(settings.t(item.titleKey))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(section == item ? Color.zzInk : Color.zzSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        if section == item {
                            Capsule()
                                .fill(Color.zzInk.opacity(0.14))
                                .matchedGeometryEffect(id: "trackSection", in: sectionNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.zzLine, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 14, y: 5)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    #if os(iOS)
    private var editToolbarButton: some View {
        Button {
            guard let editMode else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                editMode.wrappedValue = isEditing ? .inactive : .active
            }
        } label: {
            Image(systemName: isEditing ? "checkmark" : "pencil.line")
        }
        .accessibilityLabel(settings.t(isEditing ? "Done" : "Edit"))
    }
    #endif

    @ViewBuilder
    private func tileCell(_ id: String, compact: Bool = false, fixedHeight: CGFloat? = nil) -> some View {
        let data = tileData(id)
        let tile = TrackDataTile(
            data: data,
            isEditing: isEditing,
            compact: compact,
            fixedHeight: fixedHeight
        )

        if isEditing {
            tile
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.zzInk)
                        .padding(6)
                }
                .opacity(draggingID == id ? 0.62 : 1)
                .onDrag {
                    draggingID = id
                    return NSItemProvider(object: id as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: TrackTileDropDelegate(
                        itemID: id,
                        order: $order,
                        draggingID: $draggingID
                    )
                )
        } else {
            tile
        }
    }

    private func tileData(_ id: String) -> TrackTileData {
        let telemetry = manager.trackTelemetry
        let hasData = telemetry.date != nil
            || telemetry.satellites != nil
            || telemetry.latitude != nil

        switch id {
        case "time":
            return TrackTileData(
                label: settings.t("Time"),
                value: telemetry.date.map { Self.timeFormatter.string(from: $0) } ?? "—",
                unit: "",
                secondary: telemetry.date.map { Self.dateFormatter.string(from: $0) }
            )
        case "satellites":
            return TrackTileData(
                label: settings.t("Satellites"),
                value: telemetry.satellites.map(String.init) ?? "—",
                unit: settings.t("SVs")
            )
        case "coordDOP":
            return TrackTileData(
                label: settings.t("Coordinate error"),
                value: number(telemetry.hdop, format: "%.2f"),
                unit: "DOP"
            )
        case "fix":
            return TrackTileData(
                label: settings.t("Fix type"),
                value: telemetry.fix.map(String.init) ?? "—",
                unit: ""
            )
        case "heading":
            return TrackTileData(
                label: settings.t("Heading"),
                value: number(telemetry.heading, format: "%.0f"),
                unit: "°"
            )
        case "altitude":
            return TrackTileData(
                label: settings.t("Altitude"),
                value: number(telemetry.altitude, format: "%.1f"),
                unit: "m"
            )
        case "altDOP":
            return TrackTileData(
                label: settings.t("Altitude error"),
                value: number(telemetry.vdop, format: "%.2f"),
                unit: "DOP"
            )
        case "latitude":
            return TrackTileData(
                label: settings.t("Latitude"),
                value: number(telemetry.latitude, format: "%.5f"),
                unit: "°"
            )
        case "longitude":
            return TrackTileData(
                label: settings.t("Longitude"),
                value: number(telemetry.longitude, format: "%.5f"),
                unit: "°"
            )
        case "elapsed":
            return TrackTileData(
                label: settings.t("Elapsed time"),
                value: hasData ? elapsedText(telemetry.elapsed) : "—",
                unit: "s"
            )
        case "distance":
            return TrackTileData(
                label: settings.t("Distance"),
                value: hasData ? String(format: "%.2f", telemetry.distanceKm) : "—",
                unit: "km"
            )
        case "speed":
            return TrackTileData(
                label: settings.t("Vehicle speed"),
                value: number(telemetry.speedKPH, format: "%.0f"),
                unit: "kph"
            )
        default:
            return TrackTileData(label: "", value: "—", unit: "")
        }
    }

    private func number(_ value: Double?, format: String) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: format, value)
    }

    private func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = max(0, elapsed)
        let minutes = Int(total) / 60
        let seconds = total - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }

    private func normalizeOrder() {
        var seen = Set<String>()
        var normalized: [String] = []

        for id in orderRaw.split(separator: ",").map(String.init) {
            guard TrackTileID.all.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            normalized.append(id)
        }

        for id in TrackTileID.defaultOrder where !seen.contains(id) {
            normalized.append(id)
        }

        order = normalized
    }
}

// MARK: - Track timing map

private struct TrackTimingMapView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings

    private var speed: Double {
        max(0, manager.trackTelemetry.speedKPH ?? 0)
    }

    var body: some View {
        VStack(spacing: 12) {
            speedCard

            HStack(spacing: 12) {
                timeCard(
                    title: settings.t("Best result"),
                    value: "—"
                )
                timeCard(
                    title: settings.t("Last lap"),
                    value: "—"
                )
            }

            timeCard(
                title: settings.t("This lap"),
                value: "—"
            )
            .frame(minHeight: 92)

            timeDifferenceCard
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var speedCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t("Speed"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)
                Text("km/h")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.zzTertiary)
            }

            Spacer(minLength: 8)

            Text("\(Int(speed.rounded()))")
                .font(.system(size: 46, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 110)
        .zzCard(cornerRadius: 18)
    }

    private func timeCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 16)
    }

    private var timeDifferenceCard: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let fillWidth: CGFloat = timeDifference.map { diff in
                min(width * 0.5, width * CGFloat(abs(diff)) / 10)
            } ?? 0

            ZStack {
                if let diff = timeDifference, fillWidth > 0 {
                    Rectangle()
                        .fill(diff >= 0 ? Color.zzRed : Color.zzGreen)
                        .frame(width: fillWidth, height: height)
                        .position(
                            x: diff >= 0
                                ? width / 2 - fillWidth / 2
                                : width / 2 + fillWidth / 2,
                            y: height / 2
                        )
                }

                Text(timeDifferenceText)
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.zzInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.t("Time difference"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.zzSecondary)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .zzCard(cornerRadius: 18)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Positive means the current lap is slower than the fastest lap: the red
    /// fill grows from the center toward the leading edge. Negative is faster:
    /// the green fill grows from the center toward the trailing edge.
    /// No lap-timing source yet, so no delta is available.
    private var timeDifference: Double? {
        nil
    }

    private var timeDifferenceText: String {
        guard let diff = timeDifference else { return "—" }
        return String(format: "%.2f", diff)
    }

}

// MARK: - Full screen map

private struct TrackFullMapView: View {
    @ObservedObject var manager: GPSLinkManager

    @State private var camera: MapCameraPosition = .automatic

    private var route: [TrackRoutePoint] {
        manager.trackTelemetry.route
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            if route.count > 1 {
                MapPolyline(coordinates: route.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(
                    Color.zzRed,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }

            if let current = route.last {
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: current.latitude,
                        longitude: current.longitude
                    )
                ) {
                    Circle()
                        .fill(Color.zzInk)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.zzRed, lineWidth: 3))
                        .shadow(color: .black.opacity(0.35), radius: 4)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.zzLine, lineWidth: 0.8)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

// MARK: - Track dashboard

private enum TrackSection: String, CaseIterable, Identifiable {
    case overview
    case dashboard
    case timing
    case map

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "Overview"
        case .dashboard: return "Dashboard"
        case .timing: return "Timing"
        case .map: return "Map"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .dashboard: return "speedometer"
        case .timing: return "timer"
        case .map: return "map"
        }
    }
}

private struct GForcePoint: Identifiable {
    let id: Int
    let lateral: Double
    let longitudinal: Double
}
