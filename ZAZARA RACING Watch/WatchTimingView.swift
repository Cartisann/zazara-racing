//
//  WatchTimingView.swift
//  ZAZARA RACING Watch
//
//  Standalone lap timing: records with the cached track config and stores
//  sessions locally until they are synced to the phone.
//

import SwiftUI

struct WatchTimingView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var recorder = LapSessionRecorder()
    @StateObject private var workout = WatchWorkoutSession()
    @StateObject private var phoneSync = WatchPhoneSync()
    @State private var records: [LapSession] = []

    private var syncedTrack: LapTrackConfig? {
        phoneSync.syncedTrack
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                trackCard
                controlButton

                if let session = recorder.session {
                    if recorder.isRecording {
                        currentLapRow
                    }
                    if !session.laps.isEmpty {
                        lapList(session)
                    }
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

    private var trackCard: some View {
        VStack(spacing: 3) {
            Text(settings.t("Track"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WatchTheme.tertiary)
            Text(syncedTrack?.name ?? settings.t("No track synced"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(syncedTrack == nil ? WatchTheme.secondary : WatchTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlButton: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
                workout.stop()
            } else if let syncedTrack {
                recorder.start(track: syncedTrack)
                workout.start()
            }
        } label: {
            Label(
                recorder.isRecording ? settings.t("End") : settings.t("Begin"),
                systemImage: recorder.isRecording ? "stop.fill" : "play.fill"
            )
        }
        .tint(recorder.isRecording ? WatchTheme.red : WatchTheme.green)
        .disabled(!recorder.isRecording && syncedTrack == nil)
    }

    private func reloadRecords() {
        records = LapSessionStore.allSessions()
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

    private var currentLapRow: some View {
        HStack {
            Text(settings.t("This lap"))
                .font(.system(size: 9))
                .foregroundStyle(WatchTheme.secondary)
            Spacer(minLength: 4)
            Text(LapSessionRecorder.formatLapTime(recorder.currentLapElapsed))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(WatchTheme.ink)
        }
        .padding(8)
        .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 8))
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
}
