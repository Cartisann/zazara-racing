//
//  WatchConnectionView.swift
//  ZAZARA RACING Watch
//
//  BLE pairing page. Tapping Connect reveals the search button; the scan
//  uses the same ZAZARA service filter as the iPhone app.
//

import SwiftUI

struct WatchConnectionView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings

    @State private var isManualSearch = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                statusCard
                controls

                if isManualSearch {
                    ProgressView()
                        .tint(WatchTheme.ink)

                    Text(settings.t("Scanning"))
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.secondary)

                    if !manager.discoveredModules.isEmpty {
                        discoveredList
                    }
                }

                if !manager.savedModules.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(settings.t("Connection records"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(WatchTheme.tertiary)
                            .padding(.leading, 2)

                        savedList
                    }
                }

                if let alert = manager.alert {
                    Text(alert.message)
                        .font(.system(size: 10))
                        .foregroundStyle(WatchTheme.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .background(WatchTheme.canvas)
        .navigationTitle(settings.t("Connection"))
        .onAppear {
            // Keep the saved-device availability continuously refreshed while
            // this page is open. New devices stay hidden until Connect is tapped.
            if !manager.isConnected, !manager.isScanning {
                manager.startScan()
            }
        }
        .onChange(of: manager.isConnected) { _, connected in
            // Connecting stops the scan and clears availability; resume the
            // background scan after a disconnect so saved rows turn green again.
            if !connected, !manager.isScanning {
                manager.startScan()
            }
        }
        .overlay {
            if manager.isConnecting {
                VStack(spacing: 10) {
                    Text(settings.t("Connecting"))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(WatchTheme.ink)
                    ProgressView()
                        .tint(WatchTheme.ink)
                }
                .padding(22)
                .modifier(LiquidGlassCard())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.isConnected ? WatchTheme.green : WatchTheme.secondary)
                    .frame(width: 8, height: 8)

                Text(settings.t(manager.isConnected ? "Connected" : "Not connected"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
            }

            if let module = manager.connectedModule {
                Text(module.name)
                    .font(.system(size: 11))
                    .foregroundStyle(WatchTheme.secondary)
                    .lineLimit(1)
            }

            if manager.isConnected {
                HStack(spacing: 8) {
                    if let battery = manager.batteryLevel {
                        Text("\(battery)%")
                    }
                    if let rssi = manager.connectedRSSI {
                        Text("\(rssi) dBm")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(WatchTheme.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var controls: some View {
        if manager.isConnected {
            Button {
                manager.disconnect()
            } label: {
                Label(settings.t("Disconnect"), systemImage: "xmark.circle.fill")
            }
            .tint(WatchTheme.red)
        } else {
            Button {
                if isManualSearch {
                    // Only close the manual search; the background scan keeps
                    // refreshing saved-device availability.
                    isManualSearch = false
                } else {
                    isManualSearch = true
                    if !manager.isScanning {
                        manager.startScan()
                    }
                }
            } label: {
                Label(
                    settings.t(isManualSearch ? "Stop scanning" : "Connect"),
                    systemImage: isManualSearch ? "xmark.circle.fill" : "link"
                )
            }
            .tint(isManualSearch ? WatchTheme.red : WatchTheme.green)
        }
    }

    private var savedList: some View {
        VStack(spacing: 6) {
            ForEach(manager.savedModules) { module in
                Button {
                    manager.connect(module)
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WatchTheme.ink)
                                .lineLimit(1)

                            Text(module.lastLinkedDateText)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(WatchTheme.tertiary)
                        }

                        Spacer(minLength: 0)

                        let available = manager.availableSavedModuleIDs.contains(module.id)
                        ZStack {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(available ? WatchTheme.green : WatchTheme.red)
                            if !available {
                                Capsule()
                                    .fill(WatchTheme.red)
                                    .frame(width: 1.2, height: 14)
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var discoveredList: some View {
        VStack(spacing: 6) {
            ForEach(manager.discoveredModules) { device in
                Button {
                    manager.connect(device)
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WatchTheme.ink)
                                .lineLimit(1)

                            Text("#\(device.shortID)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(WatchTheme.tertiary)
                        }

                        Spacer(minLength: 0)

                        if let rssi = device.rssi {
                            Text("\(rssi)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(WatchTheme.secondary)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Liquid Glass

/// Uses the system Liquid Glass effect on watchOS 26+, with a material
/// fallback on older watchOS versions.
private struct LiquidGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 26.0, *) {
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        } else {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }
}
