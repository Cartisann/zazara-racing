//
//  WatchTimingView.swift
//  ZAZARA RACING Watch
//
//  Combined live-data + timing page: speed, track, start/stop, laps and
//  locally stored sessions.
//

import SwiftUI

struct WatchTimingView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var phoneSync: WatchPhoneSync
    @StateObject private var recorder = LapSessionRecorder()
    @StateObject private var workout = WatchWorkoutSession()
    @State private var records: [LapSession] = []

    private var syncedTrack: LapTrackConfig? { phoneSync.syncedTrack }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                speedCard
                trackCard

                HStack(spacing: 6) {
                    startButton
                    if recorder.isRecording {
                        stopButton
                    }
                }

                if recorder.isRecording {
                    currentLapRow
                }

                if let session = recorder.session, !session.laps.isEmpty {
                    lapList(session)
                }

                if !records.isEmpty {
                    recordsSection
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .background(WatchTheme.canvas)
        .navigationTitle(settings.t("Timing"))
        .onChange(of: manager.trackTelemetry) { _, telemetry in
            recorder.ingest(telemetry)
        }
        .onAppear { reloadRecords() }
        .onChange(of: recorder.isRecording) { _, recording in
            if !recording { reloadRecords() }
        }
        .onChange(of: phoneSync.pendingTransferCount) { _, _ in
            reloadRecords()
        }
    }

    private var speedCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(settings.t("Speed"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTheme.secondary)
                Spacer(minLength: 0)
                Text("km/h")
                    .font(.system(size: 8))
                    .foregroundStyle(WatchTheme.tertiary)
            }
            Text("\(Int(speed.rounded()))")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var trackCard: some View {
        VStack(spacing: 2) {
            Text(settings.t("Track"))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(WatchTheme.tertiary)
            Text(syncedTrack?.name ?? settings.t("No track synced"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(syncedTrack == nil ? WatchTheme.secondary : WatchTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var startButton: some View {
        Button {
            guard let syncedTrack else { return }
            recorder.start(track: syncedTrack)
            workout.start()
        } label: {
            Label(settings.t("Begin"), systemImage: "play.fill")
        }
        .tint(WatchTheme.green)
        .disabled(syncedTrack == nil || recorder.isRecording)
    }

    private var stopButton: some View {
        Button {
            recorder.stop()
            workout.stop()
        } label: {
            Label(settings.t("End"), systemImage: "stop.fill")
        }
        .tint(WatchTheme.red)
    }

    private var currentLapRow: some View {
        HStack {
            Text(settings.t("This lap"))
                .font(.system(size: 9))
                .foregroundStyle(WatchTheme.secondary)
            Spacer(minLength: 4)
            Text(LapSessionRecorder.formatLapTime(recorder.currentLapElapsed))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(WatchTheme.ink)
        }
        .padding(8)
        .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 8))
    }

    private var speed: Double {
        max(0, manager.trackTelemetry.speedKPH ?? 0)
    }

    private func reloadRecords() {
        records = LapSessionStore.allSessions()
    }

    private func lapList(_ session: LapSession) -> some View {
        VStack(spacing: 4) {
            ForEach(session.laps) { lap in
                HStack {
                    Text("#\(lap.id)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(WatchTheme.tertiary)
                    Spacer(minLength: 4)
                    Text(LapSessionRecorder.formatLapTime(lap.duration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(lap.id == session.bestLap?.id ? WatchTheme.green : WatchTheme.ink)
                }
                .padding(7)
                .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(settings.t("Records"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchTheme.tertiary)
                Spacer(minLength: 4)
                if phoneSync.pendingTransferCount > 0 {
                    Text(settings.t("Pending upload"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WatchTheme.red)
                }
            }
            .padding(.horizontal, 2)

            ForEach(records) { record in
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.trackName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WatchTheme.ink)
                            .lineLimit(1)
                        Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(WatchTheme.tertiary)
                    }
                    Spacer(minLength: 2)
                    Text("\(record.laps.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WatchTheme.secondary)
                }
                .padding(7)
                .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
