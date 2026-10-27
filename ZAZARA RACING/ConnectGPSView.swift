//
//  ConnectGPSView.swift
//  ZAZARA RACING
//
//  Devices tab: connect and manage multiple Bluetooth GPS modules.
//

import SwiftUI

struct DevicesView: View {
    @ObservedObject var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings

    @Environment(\.scenePhase) private var scenePhase
    @State private var showLinkDetails = false

    var body: some View {
        GeometryReader { proxy in
            page(
                isWide: proxy.size.width >= 740,
                compactHeight: proxy.size.height < 730
            )
        }
        .background(Color.zzCanvas)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: manager.linkState)
        .animation(.easeInOut(duration: 0.2), value: manager.alert)
        .zzScreenCover(isPresented: $showLinkDetails) {
            LinkedView(manager: manager)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            autoScanSavedDevices()
        }
        .zzOnChange(of: manager.isConnected) { connected in
            if !connected {
                autoScanSavedDevices()
            }
        }
        .zzOnChange(of: manager.linkState) { state in
            if state == .idle {
                autoScanSavedDevices()
            }
        }
        .zzOnChange(of: scenePhase) { phase in
            if phase == .background {
                manager.stopScan()
            } else if phase == .active {
                manager.refreshConnectionHealth()
                autoScanSavedDevices()
            }
        }
    }

    // MARK: - Page layout

    private func autoScanSavedDevices() {
        guard !manager.savedModules.isEmpty,
              !manager.isConnected,
              !manager.isConnecting,
              !manager.isScanning else { return }
        manager.startScan()
    }

    private var hasAnyDeviceContent: Bool {
        manager.isConnected || manager.isScanning || !manager.savedModules.isEmpty
    }

    private func page(isWide: Bool, compactHeight: Bool) -> some View {
        ZStack {
            Color.zzCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let alert = manager.alert {
                            ZZNoticeCard(
                                tone: .error,
                                icon: "exclamationmark.triangle.fill",
                                title: alert.title,
                                message: alert.message,
                                onDismiss: { manager.dismissAlert() }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        statusNotice

                        if isWide && hasAnyDeviceContent {
                            wideContent(compactHeight: compactHeight)
                        } else {
                            compactContent(compactHeight: compactHeight)
                        }
                    }
                    .padding(.horizontal, isWide ? 24 : 18)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: isWide ? 980 : 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .background(Color.zzCanvas)
            }
        }
    }

    @ViewBuilder
    private func compactContent(compactHeight: Bool) -> some View {
        mainContent(compactHeight: compactHeight)

        if shouldShowNearby {
            nearbySection
                .padding(.top, 2)
        }

        if !manager.savedModules.isEmpty {
            savedSection
                .padding(.top, 6)
        }
    }

    private func wideContent(compactHeight: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                if manager.isConnected, let module = manager.connectedModule {
                    liveCard(module)
                } else if manager.isScanning {
                    scanningCard
                } else {
                    emptyState(compactHeight: true)
                        .padding(12)
                        .zzCard(cornerRadius: 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(spacing: 16) {
                if shouldShowNearby {
                    nearbySection
                }

                if !manager.savedModules.isEmpty {
                    savedSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZZScreenHeader(
            title: settings.t("Devices"),
            subtitle: headerSubtitle,
            statusText: manager.zzStatus(language: settings.language).text,
            statusColor: manager.zzStatus(language: settings.language).color
        ) {
            if !manager.isConnected && !manager.isConnecting {
                Button {
                    if manager.isScanning {
                        manager.stopScan()
                    } else {
                        manager.startScan()
                    }
                } label: {
                    Image(systemName: manager.isScanning ? "stop.fill" : "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.zzRed))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    settings.t(manager.isScanning ? "Stop scanning" : "Add GPS device")
                )
            }
        }
    }

    private var headerSubtitle: String? {
        if manager.isConnected, let module = manager.connectedModule {
            return settings.t("%@ connected", module.name)
        }
        if manager.isScanning {
            return settings.t("Scanning for nearby ZAZARA GPS")
        }

        if manager.savedModules.isEmpty {
            return settings.t("Bluetooth GPS modules")
        }
        return nil
    }

    // MARK: - Notices

    @ViewBuilder
    private var statusNotice: some View {
        switch manager.bluetoothState {
        case .poweredOff:
            ZZNoticeCard(
                tone: .error,
                icon: "bolt.slash.fill",
                title: settings.t("Bluetooth is off"),
                message: settings.t("Turn on Bluetooth, then connect your GPS module."),
                actionTitle: settings.t("Open Settings"),
                action: ZZPlatform.openBluetoothSettings
            )

        case .unauthorized:
            ZZNoticeCard(
                tone: .error,
                icon: "lock.fill",
                title: settings.t("Bluetooth access needed"),
                message: settings.t("Allow Bluetooth access so ZAZARA RACING can find your GPS module."),
                actionTitle: settings.t("Open Settings"),
                action: ZZPlatform.openBluetoothSettings
            )

        case .unsupported:
            ZZNoticeCard(
                tone: .info,
                icon: "exclamationmark.triangle.fill",
                title: settings.t("Bluetooth LE unavailable"),
                message: settings.t("This device can’t scan for Bluetooth GPS modules.")
            )

        default:
            EmptyView()
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func mainContent(compactHeight: Bool) -> some View {
        if manager.isConnected, let module = manager.connectedModule {
            liveCard(module)
        } else if manager.isScanning {
            scanningCard
        } else if manager.savedModules.isEmpty {
            emptyState(compactHeight: compactHeight)
        }
    }

    private func emptyState(compactHeight: Bool) -> some View {
        VStack(spacing: compactHeight ? 14 : 20) {
            Spacer(minLength: compactHeight ? 10 : 42)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: compactHeight ? 38 : 46, weight: .ultraLight))
                .foregroundStyle(Color.zzRed)

            VStack(spacing: 7) {
                Text(settings.t("No devices connected"))
                    .font(.system(size: compactHeight ? 16 : 17, weight: .semibold))
                    .foregroundStyle(Color.zzRed)

                Text(settings.t("Connect a ZAZARA GPS receiver to get started."))
                    .font(.system(size: compactHeight ? 12.5 : 13, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                manager.startScan()
            } label: {
                Text(settings.t("Connect Now"))
            }
            .buttonStyle(ZZPrimaryButtonStyle())
            .frame(maxWidth: 300)

            Text(settings.t("Multiple GPS modules can be saved as records."))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.zzTertiary)

            Spacer(minLength: compactHeight ? 10 : 42)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: compactHeight ? 0 : 490)
        .padding(.horizontal, 8)
        .padding(.vertical, compactHeight ? 18 : 0)
    }

    private var scanningCard: some View {
        VStack(spacing: 13) {
            HStack(spacing: 13) {
                ZZScanRadar()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(settings.t("Scanning for ZAZARA GPS"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.zzInk)

                        ZZAnimatedDots()
                    }

                    Text(scanCountLabel)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Color.zzSecondary)
                }

                Spacer(minLength: 8)
            }

            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)

            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))

                Text(settings.t("Keep your GPS module powered on and within 3 m."))

                Spacer(minLength: 8)

                Text("BLE")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color.zzTertiary)
        }
        .padding(15)
        .zzCard(cornerRadius: 18)
    }

    private var scanCountLabel: String {
        let count = manager.discoveredModules.count
        if count == 0 {
            return settings.t("Listening for ZAZARA GPS")
        }
        return settings.devicesInRangeText(count)
    }

    // MARK: - Live card

    private func liveCard(_ module: SavedGPSModule) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZZModuleGlyph(active: true, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(module.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.zzInk)
                            .lineLimit(1)

                        Text("#\(module.shortID)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.zzTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.zzMutedSurface))
                    }

                    HStack(spacing: 6) {
                        ZZPulseDot(color: .zzGreen, size: 4)
                        Text(settings.t("Connected"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.zzGreen)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    ZZSignalBars(level: manager.connectedSignalLevel, tint: .zzGreen)
                    Text(rssiText(manager.connectedRSSI))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.zzSecondary)
                }
            }
            .padding(16)

            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)

            HStack(spacing: 0) {
                metric(
                    title: settings.t("Signal"),
                    value: settings.signalLabel(level: manager.connectedSignalLevel).uppercased()
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                verticalDivider

                metric(
                    title: settings.t("Battery"),
                    value: manager.batteryLevel.map { "\($0)%" } ?? "—"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

                verticalDivider

                metric(title: settings.t("Link"), value: "BLE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.zzLine)
                .frame(height: 0.5)

            HStack(spacing: 12) {
                Text(settings.lastLinkedText(module.lastLinkedAt))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Color.zzTertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    showLinkDetails = true
                } label: {
                    Text(settings.t("Details"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                Button {
                    manager.disconnect()
                } label: {
                    Text(settings.t("Disconnect"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.zzRed)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .zzCard(cornerRadius: 20)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.zzTertiary)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Color.zzLine)
            .frame(width: 0.5, height: 36)
    }

    // MARK: - Nearby

    private var shouldShowNearby: Bool {
        !manager.isConnected && (manager.isScanning || !manager.discoveredModules.isEmpty)
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZZSectionHeader(
                title: settings.t("New ZAZARA GPS"),
                detail: manager.isScanning
                    ? settings.foundCountText(manager.discoveredModules.count)
                    : settings.t("Last scan")
            )

            if manager.discoveredModules.isEmpty {
                searchingPlaceholder
            } else {
                ForEach(manager.discoveredModules) { device in
                    nearbyRow(device)
                }
            }
        }
    }

    private var searchingPlaceholder: some View {
        HStack(spacing: 12) {
            ZZModuleGlyph(size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t("Searching for ZAZARA GPS"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.zzInk)

                Text(settings.t("Only ZAZARA RACING GPS modules are shown."))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
            }

            Spacer(minLength: 8)

            ZZAnimatedDots()
        }
        .padding(14)
        .zzCard(cornerRadius: 16)
    }

    private func nearbyRow(_ device: DiscoveredGPSModule) -> some View {
        let isSaved = manager.savedModules.contains { $0.id == device.id }
        let level = GPSLinkManager.signalLevel(for: device.rssi)

        return Button {
            manager.connect(device)
        } label: {
            HStack(spacing: 12) {
                ZZModuleGlyph(size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.zzInk)
                            .lineLimit(1)

                        Text("#\(device.shortID)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.zzTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.zzMutedSurface))
                    }

                    HStack(spacing: 6) {
                        Text(settings.t("Bluetooth LE"))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.zzSecondary)

                        if isSaved {
                            Text(settings.t("SAVED"))
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(Color.zzRed)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.zzRedSoft))
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    ZZSignalBars(level: level)
                    Text(rssiText(device.rssi))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.zzSecondary)
                }

                ZStack {
                    Circle()
                        .fill(Color.zzRedSoft)
                        .frame(width: 32, height: 32)

                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.zzRed)
                }
            }
            .padding(13)
            .zzCard(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ZZCardButtonStyle())
        .disabled(manager.isConnecting || manager.isConnected)
        .accessibilityLabel(settings.t("%@, nearby GPS device", device.name))
        .accessibilityHint(settings.t("Connects to this GPS module"))
    }

    // MARK: - Saved records

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZZSectionHeader(
                title: settings.t("Connection records"),
                detail: manager.isConnected
                    ? settings.t("Disconnect to switch")
                    : settings.savedCountText(manager.savedModules.count)
            )

            ForEach(manager.savedModules) { module in
                ZZSwipeToDelete(
                    deleteTitle: settings.t("Delete"),
                    onDelete: { manager.forget(module) },
                    onTap: {
                        guard !manager.isConnected, !manager.isConnecting else { return }
                        manager.connect(module)
                    },
                    isDimmed: manager.isConnected && manager.connectedModule?.id != module.id
                ) {
                    ZZSavedRecordContent(manager: manager, module: module)
                }
            }
        }
    }

    // MARK: - Helpers

    private func rssiText(_ rssi: Int?) -> String {
        guard let rssi else { return "— dBm" }
        return "\(rssi) dBm"
    }
}

// MARK: - Saved record content

private struct ZZSavedRecordContent: View {
    @ObservedObject var manager: GPSLinkManager
    let module: SavedGPSModule
    @EnvironmentObject private var settings: AppSettings

    private var isActive: Bool {
        manager.isConnected && manager.connectedModule?.id == module.id
    }

    private var isAvailable: Bool {
        !isActive && manager.availableSavedModuleIDs.contains(module.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZZModuleGlyph(active: isActive, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(module.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .lineLimit(1)

                    Text("#\(module.shortID)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.zzTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }

                Text(settings.lastLinkedText(module.lastLinkedAt))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.zzSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            if isActive {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.zzGreen)
                        .frame(width: 6, height: 6)

                    Text(settings.t("Connected"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.zzGreen)
                }
            } else if isAvailable {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.zzGreen)
                        .frame(width: 5, height: 5)

                    Text(settings.t("Available"))
                        .font(.system(size: 10.5, weight: .semibold))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.zzGreen)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.zzGreenSoft))
            } else {
                HStack(spacing: 4) {
                    Text(settings.t("Connect"))
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(
                    manager.isConnected ? Color.zzTertiary : Color.zzRed
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(manager.isConnected ? Color.zzMutedSurface : Color.zzRedSoft)
                )
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                manager.forget(module)
            } label: {
                Label(settings.t("Forget record"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(settings.t("%@, connection record", module.name))
        .accessibilityValue(
            settings.t(isActive ? "Connected" : (isAvailable ? "Available to connect" : "Saved"))
        )
        .accessibilityHint(
            settings.t(
                manager.isConnected
                    ? "Disconnect the active GPS module before connecting another"
                    : "Connects to this saved GPS module"
            )
        )
        .accessibilityAction {
            guard !manager.isConnected, !manager.isConnecting else { return }
            manager.connect(module)
        }
    }
}

// MARK: - Swipe to delete

private struct ZZSwipeToDelete<Content: View>: View {
    let deleteTitle: String
    let onDelete: () -> Void
    let onTap: () -> Void
    let isDimmed: Bool
    let content: Content

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var tapSuppressedUntil = Date.distantPast

    private let actionWidth: CGFloat = 84

    init(
        deleteTitle: String,
        onDelete: @escaping () -> Void,
        onTap: @escaping () -> Void,
        isDimmed: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.deleteTitle = deleteTitle
        self.onDelete = onDelete
        self.onTap = onTap
        self.isDimmed = isDimmed
        self.content = content()
    }

    private var revealProgress: CGFloat {
        min(1, max(0, -offset / actionWidth))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            content
                .padding(14)
                .zzCard(cornerRadius: 16, squareTrailing: offset < 0)
                .contentShape(Rectangle())
                .opacity(isDimmed ? 0.55 : 1)
                .offset(x: offset)
                .onTapGesture {
                    guard !isDragging, Date() >= tapSuppressedUntil else { return }
                    if offset < 0 {
                        close()
                    } else {
                        onTap()
                    }
                }
        }
        .background(alignment: .trailing) {
            ZStack {
                Color.zzRed

                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))

                    Text(deleteTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundStyle(Color.white)
            }
            .frame(width: actionWidth)
            .opacity(Double(revealProgress))
            .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) {
            if offset <= -actionWidth + 1 && !isDragging {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Color.clear
                        .frame(width: actionWidth)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(deleteTitle))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .simultaneousGesture(dragGesture)
        .accessibilityAction(named: Text(deleteTitle)) {
            onDelete()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard isHorizontal else { return }

                if !isDragging {
                    isDragging = true
                    dragStartOffset = offset
                }

                let proposed = dragStartOffset + value.translation.width
                offset = min(0, max(-actionWidth, proposed))
            }
            .onEnded { value in
                guard isDragging else { return }
                isDragging = false
                tapSuppressedUntil = Date().addingTimeInterval(0.2)

                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let shouldOpen = isHorizontal && offset < -actionWidth / 2
                withAnimation(.easeOut(duration: 0.34)) {
                    offset = shouldOpen ? -actionWidth : 0
                }
            }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.34)) {
            offset = 0
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Devices — empty") {
    AppShellView(
        manager: .preview(bluetoothState: .poweredOn)
    )
    .environmentObject(AppSettings(language: .english))
}

#Preview("Devices — records") {
    AppShellView(
        manager: .preview(
            savedModules: ZZPreviewData.savedModules,
            bluetoothState: .poweredOn
        )
    )
    .environmentObject(AppSettings(language: .english))
}

#Preview("Devices — scanning") {
    AppShellView(
        manager: .preview(
            savedModules: ZZPreviewData.savedModules,
            discoveredModules: ZZPreviewData.discoveredModules,
            isScanning: true,
            bluetoothState: .poweredOn
        )
    )
    .environmentObject(AppSettings(language: .english))
}

#Preview("Devices — connected") {
    AppShellView(
        manager: .preview(
            savedModules: ZZPreviewData.savedModules,
            bluetoothState: .poweredOn,
            connectedModule: ZZPreviewData.connectedModule,
            connectedRSSI: -58,
            batteryLevel: 87
        )
    )
    .environmentObject(AppSettings(language: .english))
}

#Preview("Devices — 中文") {
    AppShellView(
        manager: .preview(
            savedModules: ZZPreviewData.savedModules,
            bluetoothState: .poweredOn
        )
    )
    .environmentObject(AppSettings(language: .chinese))
}
#endif
