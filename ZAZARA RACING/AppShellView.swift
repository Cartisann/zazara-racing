//
//  AppShellView.swift
//  ZAZARA RACING
//
//  Four-tab app shell and the secondary tabs.
//

import Charts
import SwiftUI
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
        TrackLibraryView(manager: manager) {
            selectedTab = .devices
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

                    TimingModeCard(
                        kind: .drag,
                        title: settings.t("Drag"),
                        onTap: openDragTiming
                    )

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

/// Main "Track" tab: the track library placeholder. The live GPS track
/// telemetry lives in `TrackTimingView`, opened from Timing → Track.
struct TrackLibraryView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    var openDevices: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("Track"),
                subtitle: settings.t("Track library and lap timing"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            ) {
                EmptyView()
            }

            ScrollView {
                VStack(spacing: 16) {
                    ZZComingSoonCard(
                        icon: "map",
                        useTrackIcon: true,
                        title: settings.t("Track library is coming soon"),
                        message: settings.t("Connect a Bluetooth GPS receiver to record circuits, lap times and session history."),
                        actionTitle: settings.t("Connect a GPS device"),
                        action: openDevices
                    )
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.zzCanvas)
        }
        .background(Color.zzCanvas.ignoresSafeArea())
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

// MARK: - Drag timing page

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
                .font(.system(size: compact ? 22 : 27, weight: .bold, design: .monospaced))
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
    @AppStorage("zazara.trackTileOrder.v1") private var orderRaw = ""
    @State private var order = TrackTileID.defaultOrder
    @State private var isEditing = false
    @State private var draggingID: String?
    @State private var section: TrackSection = .overview
    @Namespace private var sectionNamespace

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
                ZStack {
                    overviewContent
                        .opacity(section == .overview ? 1 : 0)
                        .allowsHitTesting(section == .overview)
                        .accessibilityHidden(section != .overview)

                    TrackDashboardView(manager: manager)
                        .opacity(section == .dashboard ? 1 : 0)
                        .allowsHitTesting(section == .dashboard)
                        .accessibilityHidden(section != .dashboard)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.18), value: section)

                sectionBar
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle(settings.t(section.titleKey))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                trackToolbarContent
            }
        }
        .onAppear(perform: normalizeOrder)
        .zzOnChange(of: order) { newOrder in
            orderRaw = newOrder.joined(separator: ",")
        }
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
                if isEditing {
                    editHint
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
        let hintHeight: CGFloat = isEditing ? 26 : 0
        let availableHeight = max(0, size.height - topPadding - bottomPadding - hintHeight)
        let tileHeight = max(0, (availableHeight - spacing * 3) / 4)

        return VStack(spacing: 10) {
            if isEditing {
                editHint
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

    private var editHint: some View {
        Text(settings.t("Drag tiles to reorder"))
            .font(.system(size: 10.5, weight: .regular))
            .foregroundStyle(Color.zzTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private var trackToolbarContent: some View {
        HStack(spacing: 10) {
            Text(rateText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzSecondary)

            if section == .overview {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditing.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.zzInk)
                        Text(settings.t(isEditing ? "Done" : "Edit"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.zzRed)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.zzRedSoft))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rateText: String {
        let rate = manager.trackTelemetry.updateRateHz
        return rate > 0 ? String(format: "%.1f Hz", rate) : "— Hz"
    }

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

// MARK: - Track dashboard

private enum TrackSection: String, CaseIterable, Identifiable {
    case overview
    case dashboard

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "Overview"
        case .dashboard: return "Dashboard"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .dashboard: return "speedometer"
        }
    }
}

private struct GForcePoint: Identifiable {
    let id: Int
    let lateral: Double
    let longitudinal: Double
}

private struct RoutePoint {
    let latitude: Double
    let longitude: Double
}

private struct TrackDashboardView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings

    @State private var rangeMax: Double = 60
    @State private var points: [GForcePoint] = []
    @State private var route: [RoutePoint] = []
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

    private var gaugePanel: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(settings.t("Speed"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)

                Spacer(minLength: 6)

                Text("0–\(Int(rangeMax))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

                Text(String(format: "%.2f / %.2f", lateralG, longitudinalG))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
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
                if route.count < 2 {
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

        if let latitude = telemetry.latitude, let longitude = telemetry.longitude {
            let point = RoutePoint(latitude: latitude, longitude: longitude)
            if let last = route.last {
                if abs(point.latitude - last.latitude) > 0.000001
                    || abs(point.longitude - last.longitude) > 0.000001 {
                    route.append(point)
                }
            } else {
                route.append(point)
            }
            if route.count > 600 {
                route.removeFirst(route.count - 600)
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
        route.removeAll()
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
