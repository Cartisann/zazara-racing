//
//  AppShellView.swift
//  ZAZARA RACING
//
//  Four-tab app shell and the secondary tabs.
//

import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case drag
    case track
    case devices
    case more

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .drag: return "DRAG"
        case .track: return "TRACK"
        case .devices: return "DEVICES"
        case .more: return "MORE"
        }
    }

    var title: String {
        switch self {
        case .drag: return "DRAG"
        case .track: return "TRACK"
        case .devices: return "DEVICES"
        case .more: return "MORE"
        }
    }

    var icon: String {
        switch self {
        case .drag: return "speedometer"
        case .track: return "map"
        case .devices: return "antenna.radiowaves.left.and.right"
        case .more: return "square.grid.2x2"
        }
    }
}

struct AppShellView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: AppTab

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
            }
        }
        .background(Color.zzCanvas)
        .preferredColorScheme(.light)
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
            DragView(manager: manager) { selectedTab = .devices }
        case .track:
            TrackView(manager: manager) { selectedTab = .devices }
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
                            Image(systemName: tab.icon)
                                .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                                .frame(width: 26, height: 22)

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
                                .fill(Color.white.opacity(0.3))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.68), lineWidth: 0.6)
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
                .fill(Color.white.opacity(0.55))
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
                            Image(systemName: tab.icon)
                                .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                                .frame(width: 26, height: 21)

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
                                .fill(Color.white.opacity(0.28))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.65), lineWidth: 0.6)
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
                .fill(Color.white.opacity(0.55))
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
    var openDevices: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("Drag"),
                subtitle: settings.t("Quarter-mile performance"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            )

            ScrollView {
                VStack(spacing: 16) {
                    ZZComingSoonCard(
                        icon: "flag.checkered",
                        title: settings.t("Drag timing is next"),
                        message: settings.t("Connect a Bluetooth GPS receiver to unlock 0–100, quarter-mile and trap-speed runs."),
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

struct TrackView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    var openDevices: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("Track"),
                subtitle: settings.t("Circuit sessions and lap timing"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            )

            ScrollView {
                VStack(spacing: 16) {
                    ZZComingSoonCard(
                        icon: "map",
                        title: settings.t("Track sessions are next"),
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

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.zzRed)
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

// MARK: - More

struct MoreView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ZZScreenHeader(
                title: settings.t("More"),
                subtitle: settings.t("App settings and information"),
                statusText: manager.zzStatus(language: settings.language).text,
                statusColor: manager.zzStatus(language: settings.language).color
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        ZZSectionHeader(title: settings.t("Language"))

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

                    VStack(alignment: .leading, spacing: 10) {
                        ZZSectionHeader(title: settings.t("GPS connection"))

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

                            settingsRow(
                                icon: "externaldrive.fill",
                                title: settings.t("Saved records"),
                                value: "\(manager.savedModules.count)",
                                showsChevron: false
                            )
                        }
                        .zzCard(cornerRadius: 16)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ZZSectionHeader(title: settings.t("Bluetooth records"))

                        VStack(spacing: 0) {
                            Button {
                                showClearConfirmation = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.zzRed)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(Color.zzRedSoft))

                                    Text(settings.t("Clear all saved records"))
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

                        Text(settings.t("Clearing records does not disconnect the active GPS module."))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.zzTertiary)
                            .padding(.horizontal, 4)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ZZSectionHeader(title: settings.t("About"))

                        VStack(spacing: 0) {
                            settingsRow(
                                icon: "info.circle",
                                title: settings.t("Version"),
                                value: "1.9",
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
            settings.t("Clear all saved Bluetooth records?"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(settings.t("Clear records"), role: .destructive) {
                manager.clearSavedRecords()
            }
            Button(settings.t("Cancel"), role: .cancel) {}
        } message: {
            Text(settings.t("This removes every saved GPS record from this iPhone."))
        }
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
