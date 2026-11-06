//
//  WatchStatusView.swift
//  ZAZARA RACING Watch
//
//  First page: only the Bluetooth module status and the track pushed by the phone.
//  The watch connects to the phone's module automatically by its hardware ID.
//

import SwiftUI

struct WatchStatusView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var phoneSync: WatchPhoneSync
    @State private var pauseHidden = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                bluetoothCard
                trackCard

                if phoneSync.hasReceivedPush, manager.isConnected, !pauseHidden {
                    pauseButton
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .background(WatchTheme.canvas)
        .navigationTitle(settings.t("Status"))
        .onAppear {
            startIfPushed()
            sendStatus()
        }
        .onChange(of: phoneSync.pushSequence) { _, _ in
            pauseHidden = false
            startIfPushed()
        }
        .onChange(of: manager.isConnected) { _, connected in
            if connected { pauseHidden = false }
            sendStatus()
        }
        .onChange(of: manager.availableSavedModuleIDs) { _, _ in
            _ = connectSavedIfNeeded()
        }
        .onChange(of: manager.discoveredModules) { _, devices in
            print("[WATCH] discovered=\(devices.count) " + devices.prefix(6).map { "\($0.name)#\($0.hardwareID ?? "-")" }.joined(separator: ", "))
            guard !manager.isConnected,
                  !manager.isConnecting,
                  let wanted = phoneSync.syncedDeviceHardwareID else { return }
            if let match = devices.first(where: { ($0.hardwareID ?? "").caseInsensitiveCompare(wanted) == .orderedSame }) {
                print("[WATCH] connecting to \(match.name)")
                manager.connect(match)
            } else {
                print("[WATCH] no match for wanted=\(wanted)")
            }
        }
    }

    private func sendStatus() {
        phoneSync.sendStatus(
            moduleConnected: manager.isConnected,
            moduleName: manager.connectedModule?.name,
            isRecording: false
        )
    }

    private var pauseButton: some View {
        Button {
            pauseHidden = true
            // Stop timing and upload the finished session to the phone, then
            // release the module and clear the route.
            phoneSync.requestPause()
            manager.disconnect()
            manager.clearTrackTelemetry()
        } label: {
            Label(settings.t("Pause"), systemImage: "pause.fill")
        }
        .tint(WatchTheme.red)
    }

    private func startIfPushed() {
        print("[WATCH] status appear pushed=\(phoneSync.hasReceivedPush) id=\(phoneSync.syncedDeviceHardwareID ?? "-") connected=\(manager.isConnected) cached=\(manager.hasCachedPeripheral) saved=\(manager.savedModules.count)")
        // Do not touch Bluetooth until the phone has pushed a track.
        guard phoneSync.hasReceivedPush else { return }
        if manager.isConnected { return }

        // An attempt is already running (or the page re-appeared mid-attempt):
        // do not restart it, otherwise cancel/connect can loop forever.
        if manager.isScanning || manager.isConnecting {
            return
        }

        // Parallel: keep scanning while also trying the cached/saved direct
        // reconnect; whichever link is established first wins.
        manager.startScan()
        if manager.reconnectCachedPeripheral() {
            return
        }
        if connectSavedIfNeeded() {
            return
        }
    }

    private func connectSavedIfNeeded() -> Bool {
        guard !manager.isConnected, !manager.isConnecting,
              let wanted = phoneSync.syncedDeviceHardwareID else { return false }
        guard let saved = manager.savedModules.first(where: {
            ($0.hardwareID ?? "").caseInsensitiveCompare(wanted) == .orderedSame
        }) else { return false }
        print("[WATCH] connecting to saved \(saved.name)")
        manager.connect(saved)
        return true
    }

    private var bluetoothCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.isConnected ? WatchTheme.green : WatchTheme.secondary)
                    .frame(width: 8, height: 8)
                Text(settings.t(manager.isConnected ? "Bluetooth connected" : "Bluetooth not connected"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if let module = manager.connectedModule {
                Text(module.name)
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var trackCard: some View {
        VStack(spacing: 3) {
            Text(settings.t("Track"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.tertiary)
            Text(phoneSync.syncedTrack?.name ?? settings.t("No track synced"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(phoneSync.syncedTrack == nil ? WatchTheme.secondary : WatchTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
