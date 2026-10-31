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

    @State private var showSearch = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                statusCard
                controls

                Text(diagnosticText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(WatchTheme.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if manager.isScanning {
                    ProgressView()
                        .tint(WatchTheme.ink)

                    Text(settings.t("Scanning"))
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.secondary)
                }

                if !manager.discoveredModules.isEmpty {
                    discoveredList
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
                showSearch = true
            } label: {
                Label(settings.t("Connect"), systemImage: "link")
            }
            .tint(WatchTheme.green)

            if showSearch {
                Button {
                    if manager.isScanning {
                        manager.stopScan()
                    } else {
                        manager.startScan()
                    }
                } label: {
                    Label(
                        settings.t(manager.isScanning ? "Stop scanning" : "Search"),
                        systemImage: manager.isScanning ? "stop.circle.fill" : "magnifyingglass"
                    )
                }
                .tint(WatchTheme.ink)
            }
        }
    }

    private var diagnosticText: String {
        let state: String
        switch manager.bluetoothState {
        case .poweredOn: state = "BT on"
        case .poweredOff: state = "BT off"
        case .unauthorized: state = "BT denied"
        case .unsupported: state = "BT unsupported"
        case .resetting: state = "BT resetting"
        case .unknown: state = "BT unknown"
        @unknown default: state = "BT ?"
        }
        let auth: String
        switch manager.authorization {
        case .allowedAlways: auth = "allowed"
        case .denied: auth = "denied"
        case .restricted: auth = "restricted"
        case .notDetermined: auth = "pending"
        @unknown default: auth = "?"
        }
        return "\(state) · \(auth) · scan \(manager.isScanning ? "on" : "off") · \(manager.discoveredModules.count)"
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
