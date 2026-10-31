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

    var body: some View {
        VStack(spacing: 8) {
            speedCard

            HStack(spacing: 6) {
                metricCard(settings.t("This lap"), value: "—")
                metricCard(settings.t("Best result"), value: "—")
            }

            timeDifferenceCard
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(WatchTheme.canvas)
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

            Text("\(Int(speed.rounded()))")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(WatchTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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
    private var timeDifference: Double? {
        nil
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
