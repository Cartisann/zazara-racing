//
//  AppShellView.swift
//  ZAZARA RACING
//
//  Four-tab app shell and the secondary tabs.
//

import SwiftUI
import UniformTypeIdentifiers

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

private struct ZZTabGlyph: View {
    let tab: AppTab
    let selected: Bool

    var body: some View {
        if tab == .track {
            ZZTrackShape()
                .stroke(
                    selected ? Color.zzRed : Color.zzSecondary,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 25, height: 20)
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 19, weight: selected ? .semibold : .regular))
                .frame(width: 26, height: 22)
        }
    }
}

struct AppShellView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: AppTab
    @State private var showingDragTiming = false
    @State private var showingTrackTiming = false

    init(manager: GPSLinkManager, initialTab: AppTab = .devices) {
        self.manager = manager
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        GeometryReader { proxy in
            let isShortPortrait = proxy.size.height > proxy.size.width
                && proxy.size.height < 760
                && proxy.size.width >= 390
            let useSideBar = (proxy.size.width > proxy.size.height && proxy.size.width >= 700)
                || ZZDeviceMetrics.isDuoOuterDisplay
                || isShortPortrait

            ZStack {
                Color.zzCanvas.ignoresSafeArea()
                shellContent(useSideBar: useSideBar)
                connectingOverlay

                if showingDragTiming {
                    DragTimingView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingDragTiming = false
                        }
                    }
                    .zIndex(20)
                    .transition(.move(edge: .trailing))
                }

                if showingTrackTiming {
                    TrackTimingView(manager: manager) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingTrackTiming = false
                        }
                    }
                    .zIndex(20)
                    .transition(.move(edge: .trailing))
                }
            }
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

    @ViewBuilder
    private func shellContent(useSideBar: Bool) -> some View {
        if useSideBar {
            ZStack {
                tabContent
                glassTabOverlay
            }
        } else {
            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ZZTabBar(
                        selection: $selectedTab,
                        isConnected: manager.isConnected
                    )
                }
        }
    }

    private var glassTabOverlay: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .allowsHitTesting(false)

                ZZGlassSideTabBar(
                    selection: $selectedTab,
                    isConnected: manager.isConnected
                )
                .padding(.trailing, 14)
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea()
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

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .drag:
            DragView(
                manager: manager,
                openDragTiming: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingDragTiming = true
                    }
                },
                openTrackTiming: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingTrackTiming = true
                    }
                }
            ) {
                selectedTab = .devices
            }
        case .track:
            TrackView(manager: manager)
        case .devices:
            DevicesView(manager: manager)
        case .more:
            MoreView(manager: manager)
        }
    }
}

// MARK: - Tab bar

struct ZZTabBar: View {
    @Binding var selection: AppTab
    var isConnected = false
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            ZZTabGlyph(tab: tab, selected: selection == tab)

                            if tab == .devices && isConnected {
                                Circle()
                                    .fill(Color.zzGreen)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 1, y: -1)
                            }
                        }

                        Text(settings.t(tab.localizationKey))
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.55)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? Color.zzRed : Color.zzSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                                )
                                .shadow(color: Color.zzRed.opacity(0.08), radius: 5, x: 0, y: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t(tab.localizationKey))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: 470)
        .background {
            ZZLiquidGlassBackground(cornerRadius: 34)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 9)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.20))
                .frame(width: 32, height: 1.2)
                .blur(radius: 0.4)
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Liquid Glass side tabs

struct ZZGlassSideTabBar: View {
    @Binding var selection: AppTab
    var isConnected = false
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            ZZTabGlyph(tab: tab, selected: selection == tab)

                            if tab == .devices && isConnected {
                                Circle()
                                    .fill(Color.zzGreen)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 1, y: -1)
                            }
                        }

                        Text(settings.t(tab.localizationKey))
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.15)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                    .foregroundStyle(selection == tab ? Color.zzRed : Color.zzSecondary)
                    .frame(width: 58, height: 54)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                                )
                                .shadow(color: Color.zzRed.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t(tab.localizationKey))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background {
            ZZLiquidGlassBackground(cornerRadius: 30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 10)
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.20))
                .frame(width: 24, height: 1.2)
                .blur(radius: 0.4)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .contain)
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
                    .foregroundStyle(Color.zzRed)
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
                                Color.zzRed,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 32, height: 26)
                    } else {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.zzRed)
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

struct TrackView: View {
    @ObservedObject var manager: GPSLinkManager

    var body: some View {
        TrackTimingView(
            manager: manager,
            showsCloseButton: false,
            onClose: {}
        )
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
                            Color.zzRed,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 40, height: 32)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.zzRed)
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
                        .foregroundStyle(Color.zzRed)
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
    var onClose: () -> Void
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
                header

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
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(settings.t("Drag"))
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(Color.zzInk)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 15)
        .background(Color.zzSurface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.zzInk)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.zzMutedSurface))
                    .overlay(Circle().stroke(Color.zzLine, lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Back"))
            .padding(.trailing, 30)
            .padding(.top, 8)
        }
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
                Text(settings.t(mode.titleKey))
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Color.zzRed)
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
                    .foregroundStyle(Color.zzRed)
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
                    .keyboardType(.numberPad)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(data.label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Text(data.value)
                .font(.system(size: 27, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.34)

            if let secondary = data.secondary {
                Text(secondary)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Text(data.unit)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .aspectRatio(1.2, contentMode: .fit)
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
    var showsCloseButton: Bool = true
    var onClose: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @AppStorage("zazara.trackTileOrder.v1") private var orderRaw = ""
    @State private var order = TrackTileID.defaultOrder
    @State private var isEditing = false
    @State private var draggingID: String?

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
                contentHeader

                ScrollView {
                    VStack(spacing: 10) {
                        if isEditing {
                            Text(settings.t("Drag tiles to reorder"))
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(Color.zzTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: normalizeOrder)
        .zzOnChange(of: order) { newOrder in
            orderRaw = newOrder.joined(separator: ",")
        }
    }

    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(settings.t("GPS receiver"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.zzInk)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(rateText)
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzSecondary)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditing.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 9, weight: .bold))
                        Text(settings.t(isEditing ? "Done" : "Edit"))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.zzRed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.zzRedSoft))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.trailing, showsCloseButton ? 58 : 0)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.zzSurface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            if showsCloseButton {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.zzInk)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.zzMutedSurface))
                        .overlay(Circle().stroke(Color.zzLine, lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("Back"))
                .padding(.trailing, 30)
                .padding(.top, 8)
            }
        }
    }

    private var rateText: String {
        let rate = manager.trackTelemetry.updateRateHz
        return rate > 0 ? String(format: "%.1f Hz", rate) : "— Hz"
    }

    @ViewBuilder
    private func tileCell(_ id: String) -> some View {
        let data = tileData(id)
        let tile = TrackDataTile(data: data, isEditing: isEditing)

        if isEditing {
            tile
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.zzRed)
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
