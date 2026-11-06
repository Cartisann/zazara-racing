//
//  WatchDataView.swift
//  ZAZARA RACING Watch
//
//  Default page: live speed, this lap, best lap and time difference.
//

import SwiftUI

struct WatchDataView: View {
    @EnvironmentObject private var manager: GPSLinkManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var phoneSync: WatchPhoneSync
    @StateObject private var recorder = LapSessionRecorder()
    @StateObject private var workout = WatchWorkoutSession()

    private var syncedTrack: LapTrackConfig? { phoneSync.syncedTrack }

    var body: some View {
        VStack(spacing: 8) {
            speedCard


            HStack(spacing: 6) {
                metricCard(settings.t("Best result"), value: bestLapText)
            }

            timeDifferenceCard
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(WatchTheme.canvas)
        .onChange(of: manager.trackTelemetry) { _, telemetry in
            recorder.ingest(telemetry)
        }
        .onChange(of: recorder.isRecording) { _, _ in
            phoneSync.sendStatus(
                moduleConnected: manager.isConnected,
                moduleName: manager.connectedModule?.name,
                isRecording: recorder.isRecording
            )
        }
        .onChange(of: phoneSync.pauseToken) { _, _ in
            if recorder.isRecording {
                recorder.stop()
                workout.stop()
            }
            phoneSync.sendPendingSessions()
        }
        .onChange(of: phoneSync.pushSequence) { _, _ in
            guard phoneSync.hasReceivedPush, let track = phoneSync.syncedTrack, !recorder.isRecording else { return }
            recorder.start(track: track)
            workout.start()
        }
        .onAppear {
            guard phoneSync.hasReceivedPush,
                  let track = phoneSync.syncedTrack,
                  !recorder.isRecording else { return }
            recorder.start(track: track)
            workout.start()
        }
    }

    private var speedCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(settings.t("Speed"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WatchTheme.secondary)

                Spacer(minLength: 0)

                Text("km/h")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(speed.rounded()))")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(settings.t("This lap"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WatchTheme.tertiary)
                    Text(LapSessionRecorder.formatLapTime(recorder.currentLapElapsed))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WatchTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(WatchTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var timeDifferenceCard: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let fillWidth: CGFloat = timeDifference.map { diff in
                min(width * 0.5, width * CGFloat(abs(diff)) / 10)
            } ?? 0

            ZStack {
                if let diff = timeDifference, fillWidth > 0 {
                    Rectangle()
                        .fill(diff >= 0 ? WatchTheme.red : WatchTheme.green)
                        .frame(width: fillWidth, height: height)
                        .position(
                            x: diff >= 0
                                ? width / 2 - fillWidth / 2
                                : width / 2 + fillWidth / 2,
                            y: height / 2
                        )
                }

                Text(timeDifferenceText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                VStack(alignment: .leading, spacing: 0) {
                    Text(settings.t("Time difference"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WatchTheme.secondary)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: 64)
        .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// No lap-time source yet; the fill appears once a delta is available.
    private var bestLapText: String {
        guard let best = recorder.session?.bestLap else { return "—" }
        return LapSessionRecorder.formatLapTime(best.duration)
    }

    /// Difference between the running lap and the best completed lap.
    private var timeDifference: Double? {
        guard recorder.isRecording, let best = recorder.session?.bestLap else { return nil }
        return recorder.currentLapElapsed - best.duration
    }

    private var timeDifferenceText: String {
        guard let diff = timeDifference else { return "—" }
        return String(format: "%.2f", diff)
    }

    private func metricCard(_ title: String, value: String, wide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTheme.muted, in: RoundedRectangle(cornerRadius: 10))
    }

    private var speed: Double {
        max(0, manager.trackTelemetry.speedKPH ?? 0)
    }
}
