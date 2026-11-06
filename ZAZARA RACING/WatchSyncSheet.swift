//
//  WatchSyncSheet.swift
//  ZAZARA RACING
//
//  Watch management sheet: sync GPS + track to the watch, list the watch's
//  recorded sessions, and pull them onto the phone.
//

#if os(iOS)
import SwiftUI

struct WatchSyncSheet: View {
    @ObservedObject var watchSync: PhoneWatchSync
    @ObservedObject var manager: GPSLinkManager
    let track: LapTrackConfig?
    let deviceHardwareID: String?
    @State private var availableTracks: [LapTrackConfig] = []
    @State private var selectedTrackID = ""
    @EnvironmentObject private var settings: AppSettings

    private var selectedTrack: LapTrackConfig? {
        availableTracks.first { $0.trackID == selectedTrackID } ?? track
    }

    private var status: WatchStatusPayload? { watchSync.watchStatus }
    private var sessions: [WatchSessionSummary] { watchSync.watchStatus?.sessions ?? [] }
    private var watchConnectedToModule: Bool { status?.moduleConnected == true }
    /// Paired Apple Watch. isWatchAppInstalled requires the system to recognise
    /// the embedded companion app, which is unreliable for a side-loaded watch
    /// app; the WCSession data channels still work when paired.
    private var watchAvailable: Bool { watchSync.isPaired }
    private var syncDisabled: Bool { !watchAvailable }

    var body: some View {
        GeometryReader { proxy in
                let _ = print("[SHEET] size=\(proxy.size) landscape=\(proxy.size.width > proxy.size.height)")
                if proxy.size.width > proxy.size.height, proxy.size.width >= 800 {
                    // Wide split device (Duo landscape): two columns — buttons
                    // left, watch history right. Slab phones stay vertical.
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            statusCard
                            trackPicker
                            syncButton
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        VStack(alignment: .leading, spacing: 14) {
                            historySection
                            syncToPhoneButton
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .padding(16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            statusCard
                            trackPicker
                            syncButton
                            historySection
                            syncToPhoneButton
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.zzCanvas.ignoresSafeArea())
            .navigationTitle(settings.t("Watch"))
            .navigationBarTitleDisplayMode(.inline)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(watchAvailable ? Color.zzGreen : Color.zzTertiary)
                    .frame(width: 9, height: 9)
                Text(watchAvailable
                     ? settings.t("Watch paired")
                     : settings.t("Watch not paired"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
            }

            Text(watchSync.isReachable
                 ? settings.t("Watch reachable")
                 : settings.t("Watch in background"))
                .font(.system(size: 11))
                .foregroundStyle(Color.zzSecondary)

            if let status {
                Text(status.moduleConnected
                     ? (status.moduleName ?? settings.t("Watch module connected"))
                     : settings.t("Watch module not connected"))
                    .font(.system(size: 12))
                    .foregroundStyle(status.moduleConnected ? Color.zzGreen : Color.zzSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zzSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var trackPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("Track"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)

            if availableTracks.isEmpty {
                Text(settings.t("No tracks available"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.zzTertiary)
            } else {
                NavigationLink {
                    WatchTrackPicker(
                        tracks: availableTracks,
                        selectedTrackID: $selectedTrackID
                    )
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedTrack?.name ?? settings.t("Select a track"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.zzInk)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.zzTertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.zzSurface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            guard availableTracks.isEmpty else { return }
            let loaded = TrackStore.load().compactMap { definition in
                LapTrackConfig.load(
                    jsonData: definition.jsonData,
                    name: definition.name,
                    trackID: definition.id
                )
            }
            availableTracks = loaded
            if selectedTrackID.isEmpty {
                selectedTrackID = (track ?? loaded.first)?.trackID ?? ""
            }
        }
    }

    private var syncButton: some View {
        VStack(alignment: .leading, spacing: 6) {
        Button {
            guard let track = selectedTrack else { return }
            watchSync.pushTrack(track, deviceHardwareID: deviceHardwareID)
            // The GPS module accepts a single BLE connection; release it so the
            // watch can connect right after the sync.
            if manager.isConnected {
                manager.disconnect()
            }
        } label: {
            Label(settings.t("Sync GPS and map to watch"), systemImage: "arrow.up.to.line")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(syncDisabled ? Color.zzTertiary : Color.zzGreen)
        .disabled(syncDisabled || selectedTrack == nil)

        if let statusText = watchSync.lastPushStatus, !statusText.isEmpty {
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(Color.zzSecondary)
        }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.t("Watch history"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)

            if sessions.isEmpty {
                Text(settings.t("No sessions on the watch"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.zzTertiary)
            } else {
                ForEach(sessions) { session in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.trackName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.zzInk)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.zzTertiary)
                        }
                        Spacer(minLength: 4)
                        Text("\(session.lapCount)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.zzSecondary)
                    }
                    .padding(10)
                    .background(Color.zzMutedSurface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var syncToPhoneButton: some View {
        Button {
            watchSync.requestWatchUpload()
        } label: {
            Label(settings.t("Sync to phone"), systemImage: "arrow.down.to.line")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(!watchAvailable || sessions.isEmpty ? Color.zzTertiary : Color.zzInk)
        .disabled(!watchAvailable || sessions.isEmpty)
    }
}
private struct WatchTrackPicker: View {
    let tracks: [LapTrackConfig]
    @Binding var selectedTrackID: String
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [LapTrackConfig] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return tracks }
        return tracks.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filtered) { track in
            Button {
                selectedTrackID = track.trackID
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text(track.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                    Spacer(minLength: 4)
                    if track.trackID == selectedTrackID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.zzGreen)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.zzSurface)
        }
        .scrollContentBackground(.hidden)
        .background(Color.zzCanvas.ignoresSafeArea())
        .searchable(text: $query, prompt: settings.t("Search tracks"))
        .navigationTitle(settings.t("Track"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
