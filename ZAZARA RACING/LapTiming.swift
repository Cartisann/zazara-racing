//
//  LapTiming.swift
//  ZAZARA RACING
//
//  Lap timing: automatic lap detection, session recording and the
//  Details / Timeline pages.
//

import AVFoundation
import Charts
import Combine
import CoreTransferable
import Foundation
import MapKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Video

struct LapVideoClip: Equatable {
    let url: URL
    let videoDuration: TimeInterval
    var lapOffset: TimeInterval
}

struct MovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ZAZARAVideo", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(
                UUID().uuidString + "." + received.file.pathExtension
            )
            do {
                try FileManager.default.moveItem(at: received.file, to: destination)
            } catch {
                try FileManager.default.copyItem(at: received.file, to: destination)
            }
            return MovieTransferable(url: destination)
        }
    }
}

#if os(iOS)
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#else
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerContainerNSView {
        let view = PlayerContainerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerContainerNSView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerContainerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
#endif

// MARK: - Metric

enum LapMetric: String, CaseIterable, Identifiable {
    case speed
    case lateralG
    case longitudinalG
    case altitude
    case satellites

    var id: String { rawValue }

    func title(_ settings: AppSettings) -> String {
        switch self {
        case .speed: return settings.t("Speed")
        case .lateralG: return settings.t("Lateral G")
        case .longitudinalG: return settings.t("Longitudinal G")
        case .altitude: return settings.t("Altitude")
        case .satellites: return settings.t("Satellites")
        }
    }

    var unit: String {
        switch self {
        case .speed: return "km/h"
        case .lateralG, .longitudinalG: return "g"
        case .altitude: return "m"
        case .satellites: return "SVs"
        }
    }

    var color: Color {
        switch self {
        case .speed: return Color.zzRed
        case .lateralG: return Color.zzAmber
        case .longitudinalG: return Color.zzGreen
        case .altitude: return Color.zzInk
        case .satellites: return Color.zzSecondary
        }
    }

    func value(_ sample: LapTelemetrySample) -> Double {
        switch self {
        case .speed: return sample.speedKPH
        case .lateralG: return sample.lateralG
        case .longitudinalG: return sample.longitudinalG
        case .altitude: return sample.altitude ?? 0
        case .satellites: return Double(sample.satellites ?? 0)
        }
    }
}

// MARK: - Details page (L1)

struct LapAnalysisView: View {
    let session: LapSession
    var autoPlay: Bool = true
    @EnvironmentObject private var settings: AppSettings
    @State private var metric: LapMetric = .speed

    private var referenceLap: LapRecord? {
        session.bestLap ?? session.laps.first
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 700 && proxy.size.width > proxy.size.height
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            sessionHeader
                            lapList
                        }
                        .frame(width: 340)

                        VStack(alignment: .leading, spacing: 14) {
                            chartCard
                            statsGrid
                        }
                    }
                    .padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        sessionHeader
                        lapStrip
                        chartCard
                        statsGrid
                    }
                    .padding(16)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.zzCanvas.ignoresSafeArea())
        .navigationTitle(settings.t("Details"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .onAppear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.trackName.isEmpty ? settings.t("Track") : session.trackName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.zzInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(sessionDateText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.zzTertiary)
                }

                Spacer(minLength: 8)

                Text(verbatim: "\(session.laps.count)")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.zzInk)

                Text(settings.t("Laps"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 10) {
                summaryChip(
                    title: settings.t("Best lap"),
                    value: session.bestLap.map { LapSessionRecorder.formatLapTime($0.duration) } ?? "—",
                    color: Color.zzGreen
                )
                summaryChip(
                    title: settings.t("Total"),
                    value: String(format: "%.2f km", session.totalDistanceKm),
                    color: Color.zzInk
                )
                summaryChip(
                    title: settings.t("Session"),
                    value: Self.durationText(session.totalDuration),
                    color: Color.zzInk
                )
            }
        }
        .padding(14)
        .zzCard(cornerRadius: 18)
    }

    private var sessionDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language == .chinese ? "zh_CN" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.startedAt)
    }

    private func summaryChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.zzTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zzMutedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var lapStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(session.laps) { lap in
                    lapLink(lap, compact: true)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var lapList: some View {
        VStack(spacing: 8) {
            ForEach(session.laps) { lap in
                lapLink(lap, compact: false)
            }
        }
    }

    private func lapLink(_ lap: LapRecord, compact: Bool) -> some View {
        NavigationLink {
            LapTimelineView(lap: lap, bestLap: session.bestLap, autoPlay: autoPlay)
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: "\(lap.id)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.zzInk)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(
                            lap.id == session.bestLap?.id
                                ? Color.zzRed.opacity(0.22)
                                : Color.zzMutedSurface
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(LapSessionRecorder.formatLapTime(lap.duration))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.zzInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    if let delta = deltaText(lap) {
                        Text(delta)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(lap.duration >= (session.bestLap?.duration ?? lap.duration) ? Color.zzRed : Color.zzGreen)
                    } else if lap.id == session.bestLap?.id {
                        Text(settings.t("Best lap"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.zzGreen)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.zzTertiary)
            }
            .padding(11)
            .frame(maxWidth: compact ? 160 : .infinity, alignment: .leading)
            .zzCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private func deltaText(_ lap: LapRecord) -> String? {
        guard let best = session.bestLap, lap.id != best.id else { return nil }
        return String(format: "%+.2f", lap.duration - best.duration)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let lap = referenceLap {
                    Text("\(settings.t("Lap")) \(lap.id)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                } else {
                    Text(settings.t("No lap data yet"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                }

                Spacer(minLength: 6)

                if let lap = referenceLap, lap.id == session.bestLap?.id {
                    Text(settings.t("Best lap"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.zzGreen)
                }
            }

            Picker("", selection: $metric) {
                ForEach(LapMetric.allCases) { item in
                    Text(item.title(settings)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let lap = referenceLap, !lap.samples.isEmpty {
                Chart(lap.samples) { sample in
                    LineMark(
                        x: .value("Time", sample.elapsed),
                        y: .value(metric.unit, metric.value(sample))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(metric.color)
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.zzLine)
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(Self.shortTime(seconds))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.zzTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.zzLine)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0f", number))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.zzTertiary)
                            }
                        }
                    }
                }

                HStack {
                    Text(metric.unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.zzTertiary)
                    Spacer()
                    Text(settings.t("Tap a lap to open the timeline"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.zzTertiary)
                }
            } else {
                Text(settings.t("No lap data yet"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.zzTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .zzCard(cornerRadius: 18)
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            statCell(settings.t("Last lap"), session.lastLap.map { LapSessionRecorder.formatLapTime($0.duration) } ?? "—")
            statCell(settings.t("Laps"), "\(session.laps.count)")
            statCell(settings.t("Maximum"), session.laps.map(\.maxSpeedKPH).max().map { String(format: "%.0f km/h", $0) } ?? "—")
            statCell(settings.t("Average"), averageSpeedText)
        }
    }

    private var averageSpeedText: String {
        let speeds = session.laps.map(\.avgSpeedKPH)
        guard !speeds.isEmpty else { return "—" }
        return String(format: "%.0f km/h", speeds.reduce(0, +) / Double(speeds.count))
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.zzTertiary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 14)
    }

    nonisolated static func durationText(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "—" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    nonisolated static func shortTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - History page

struct LapHistoryView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var sessions: [LapSession] = []

    var body: some View {
        List {
            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.zzTertiary)
                    Text(settings.t("No lap records yet"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                    Text(settings.t("Finished laps are saved here automatically"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.zzSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
                .padding(.horizontal, 24)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        LapAnalysisView(session: session, autoPlay: false)
                    } label: {
                        historyRow(session)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            LapSessionStore.delete([session.id])
                            refresh()
                        } label: {
                            Label(settings.t("Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.zzCanvas.ignoresSafeArea())
        .navigationTitle(settings.t("Lap records"))
        .onAppear { refresh() }
        .refreshable { refresh() }
    }

    private func refresh() {
        sessions = LapSessionStore.allSessions()
    }

    private func historyRow(_ session: LapSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.trackName.isEmpty ? settings.t("Track") : session.trackName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.zzInk)
                        .lineLimit(1)
                    Text(Self.dateText(session.startedAt, settings: settings))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.zzTertiary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.zzTertiary)
            }

            HStack(spacing: 8) {
                historyChip(settings.t("Laps"), "\(session.laps.count)", color: Color.zzInk)
                historyChip(
                    settings.t("Best lap"),
                    session.bestLap.map { LapSessionRecorder.formatLapTime($0.duration) } ?? "—",
                    color: Color.zzGreen
                )
                historyChip(
                    settings.t("Total"),
                    String(format: "%.2f km", session.totalDistanceKm),
                    color: Color.zzInk
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 16)
    }

    private func historyChip(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.zzTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.zzMutedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private static func dateText(_ date: Date, settings: AppSettings) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language == .chinese ? "zh_CN" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Timeline page (L2)

struct LapTimelineView: View {
    let lap: LapRecord
    let bestLap: LapRecord?
    var autoPlay: Bool = true

    @EnvironmentObject private var settings: AppSettings
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var zoom: CGFloat = 1
    @State private var clip: LapVideoClip?
    @State private var player: AVPlayer?
    @State private var videoPickerItem: PhotosPickerItem?
    @State private var isImportingVideo = false
    @State private var clipDragStart: TimeInterval?
    @State private var videoControlsVisible = false
    @State private var hideVideoControlsTask: Task<Void, Never>?
    @State private var barScrubbing = false
    @State private var satelliteMap = false

    private let playbackTimer = Timer
        .publish(every: 1.0 / 15.0, on: .main, in: .common)
        .autoconnect()

    private var duration: TimeInterval {
        max(lap.duration, 0.1)
    }

    private var pointsPerSecond: CGFloat {
        let base = max(4.0, 360.0 / duration)
        return base * zoom
    }

    private var timelineWidth: CGFloat {
        max(CGFloat(duration) * pointsPerSecond, 1)
    }

    private var currentSample: LapTelemetrySample? {
        guard !lap.samples.isEmpty else { return nil }
        return lap.samples.min {
            abs($0.elapsed - currentTime) < abs($1.elapsed - currentTime)
        }
    }

    private var currentTimeText: String {
        LapSessionRecorder.formatLapTime(currentTime)
    }

    var body: some View {
        GeometryReader { proxy in
            let isNarrowLayout = proxy.size.width < 560

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if isNarrowLayout {
                        VStack(spacing: 10) {
                            videoPanel
                            lapMapPanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    } else {
                        HStack(alignment: .top, spacing: 10) {
                            videoPanel
                            lapMapPanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }

                if clip != nil {
                    videoAlignmentBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                    timelineEditor
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.zzCanvas.ignoresSafeArea())
        .navigationTitle("\(settings.t("Lap")) \(lap.id)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                importVideoButton
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                importVideoButton
            }
            #endif
        }
        .onAppear {
            currentTime = 0
            isPlaying = autoPlay
            showVideoControls()
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            isPlaying = false
            hideVideoControlsTask?.cancel()
            player?.pause()
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                syncPlayer()
            } else {
                player?.pause()
            }
        }
        .onChange(of: videoPickerItem) { _, item in
            guard let item else { return }
            Task { await importVideo(item) }
        }
        .onReceive(playbackTimer) { _ in
            guard isPlaying else { return }
            currentTime += 1.0 / 15.0
            if currentTime >= duration {
                currentTime = duration
                isPlaying = false
                player?.pause()
                return
            }
            syncVideoDrift()
        }
    }

    // MARK: Video

    private var importVideoButton: some View {
        PhotosPicker(selection: $videoPickerItem, matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared()) {
            Image(systemName: "video.badge.plus")
        }
        .accessibilityLabel(settings.t("Import video"))
    }

    private var videoPanel: some View {
        ZStack {
            Color.black

            if let player, let clip {
                if isVideoVisible(clip) {
                    PlayerLayerView(player: player)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 22, weight: .semibold))
                        Text(settings.t("Video not covering this moment"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.zzSecondary)
                }
            } else {
                VStack {
                    PhotosPicker(selection: $videoPickerItem, matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared()) {
                        VStack(spacing: 5) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                            Text(settings.t("Import video"))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.zzSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }

            if isImportingVideo {
                ProgressView()
                    .tint(Color.white)
            }

            videoHUD
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.zzLine, lineWidth: 0.5)
        )
        .overlay(alignment: .bottom) {
            if videoControlsVisible {
                videoProgressSlider
                    .transition(.opacity)
            }
        }
        .overlay {
            if videoControlsVisible {
                videoCenterControls
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                if videoControlsVisible {
                    hideVideoControlsTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        videoControlsVisible = false
                    }
                } else {
                    showVideoControls()
                }
            }
        )
    }

    private var videoCenterControls: some View {
        HStack(spacing: 18) {
            Button {
                if currentTime >= duration { currentTime = 0 }
                isPlaying.toggle()
                showVideoControls()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.black.opacity(0.42)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t(isPlaying ? "Pause" : "Play"))

            Button {
                currentTime = 0
                isPlaying = true
                syncPlayer()
                showVideoControls()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.black.opacity(0.42)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Restart"))
        }
    }

    private func secondsText(_ time: TimeInterval) -> String {
        let total = Int(max(0, time).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var videoProgressSlider: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(secondsText(currentTime))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .frame(minWidth: 30, alignment: .leading)
            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { currentTime = $0 }
                ),
                in: 0...max(duration, 0.01),
                onEditingChanged: { editing in
                    if editing {
                        isPlaying = false
                        barScrubbing = true
                        hideVideoControlsTask?.cancel()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            videoControlsVisible = true
                        }
                    } else {
                        barScrubbing = false
                        isPlaying = true
                        syncPlayer()
                        showVideoControls()
                    }
                }
            )
            .tint(Color.zzRed)
                Text(secondsText(duration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func showVideoControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            videoControlsVisible = true
        }
        hideVideoControlsTask?.cancel()
        hideVideoControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !barScrubbing else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    videoControlsVisible = false
                }
            }
        }
    }

    private var videoHUD: some View {
        ZStack {
            routeTrace
                .frame(width: 74, height: 74)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)

            timeAndGapView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(10)

            HStack(alignment: .bottom, spacing: 6) {
                gMeter
                speedGauge
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
        }
        .allowsHitTesting(false)
    }

    private var routeTrace: some View {
        Canvas { context, size in
            let samples = lap.samples
            guard samples.count >= 2 else { return }

            let latitudes = samples.map(\.latitude)
            let longitudes = samples.map(\.longitude)
            guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
                  let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }

            let midLat = (minLat + maxLat) / 2
            let lonScale = cos(midLat * .pi / 180)
            let spanX = max((maxLon - minLon) * lonScale, 0.0000001)
            let spanY = max(maxLat - minLat, 0.0000001)
            let padding: CGFloat = 9
            let drawWidth = max(size.width - padding * 2, 1)
            let drawHeight = max(size.height - padding * 2, 1)
            let scale = min(drawWidth / spanX, drawHeight / spanY)
            let offsetX = (size.width - spanX * scale) / 2
            let offsetY = (size.height - spanY * scale) / 2

            func point(latitude: Double, longitude: Double) -> CGPoint {
                let x = offsetX + (longitude - minLon) * lonScale * scale
                let y = size.height - (offsetY + (latitude - minLat) * scale)
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            for (index, sample) in samples.enumerated() {
                let position = point(latitude: sample.latitude, longitude: sample.longitude)
                if index == 0 {
                    path.move(to: position)
                } else {
                    path.addLine(to: position)
                }
            }
            context.stroke(
                path,
                with: .color(Color.white.opacity(0.92)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )

            guard let current = currentSample else { return }
            let position = point(latitude: current.latitude, longitude: current.longitude)
            let heading: Double
            if let sampleHeading = current.heading {
                heading = sampleHeading
            } else if let previous = samples.last(where: { $0.elapsed < current.elapsed }) {
                let previousPosition = point(latitude: previous.latitude, longitude: previous.longitude)
                heading = atan2(position.x - previousPosition.x, previousPosition.y - position.y) * 180 / .pi
            } else {
                heading = 0
            }

            context.drawLayer { layer in
                layer.translateBy(x: position.x, y: position.y)
                layer.rotate(by: .degrees(heading))
                let arrow = LapHeadingArrow().path(in: CGRect(x: -8, y: -8, width: 16, height: 16))
                layer.fill(arrow, with: .color(Color.zzRed))
                layer.stroke(
                    arrow,
                    with: .color(Color.black.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 0.8, lineJoin: .round)
                )
            }
        }
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var timeAndGapView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let gap = bestGap {
                Text(gap.text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(gap.color)
            } else {
                Text(settings.t("Best lap"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.zzGreen)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
    }

    private var gMeter: some View {
        let outerRadius: CGFloat = 23
        let lateral = currentSample?.lateralG ?? 0
        let longitudinal = currentSample?.longitudinalG ?? 0
        let dx = CGFloat(min(max(lateral / 2.0, -1), 1)) * outerRadius
        let dy = CGFloat(min(max(-longitudinal / 2.0, -1), 1)) * outerRadius

        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
            Circle()
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
            Circle()
                .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.8)
                .frame(width: outerRadius, height: outerRadius)
            Circle()
                .fill(Color.zzAmber)
                .frame(width: 5, height: 5)
                .offset(x: dx, y: dy)
                .animation(.easeOut(duration: 0.18), value: currentSample?.id)
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
    }

    private var speedGauge: some View {
        SpeedGaugeView(
            speed: currentSample?.speedKPH ?? 0,
            maxSpeed: max(lap.maxSpeedKPH + 20, 120)
        )
    }

    private var currentG: Double {
        let lateral = currentSample?.lateralG ?? 0
        let longitudinal = currentSample?.longitudinalG ?? 0
        return sqrt(lateral * lateral + longitudinal * longitudinal)
    }

    private struct GapInfo {
        let text: String
        let color: Color
    }

    private var bestGap: GapInfo? {
        guard let bestLap, lap.id != bestLap.id, let current = currentSample else { return nil }
        guard let bestTime = interpolatedElapsed(in: bestLap, at: current.distanceKm) else { return nil }
        let delta = current.elapsed - bestTime
        return GapInfo(
            text: String(format: "%+.2f", delta),
            color: delta <= 0 ? Color.zzGreen : Color.zzRed
        )
    }

    private func interpolatedElapsed(in record: LapRecord, at distance: Double) -> TimeInterval? {
        let samples = record.samples
        guard samples.count >= 2 else { return nil }
        for index in 1..<samples.count {
            let a = samples[index - 1]
            let b = samples[index]
            if distance >= a.distanceKm, distance <= b.distanceKm {
                let span = b.distanceKm - a.distanceKm
                let fraction = span > 0 ? (distance - a.distanceKm) / span : 0
                return a.elapsed + (b.elapsed - a.elapsed) * fraction
            }
        }
        return nil
    }

    private var lapMapPanel: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if satelliteMap {
                    Map(initialPosition: .automatic) {
                        lapMapContent()
                    }
                    .mapStyle(.imagery(elevation: .flat))
                } else {
                    Map(initialPosition: .automatic) {
                        lapMapContent()
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    satelliteMap.toggle()
                }
            } label: {
                Image(systemName: satelliteMap ? "globe.americas.fill" : "map.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .accessibilityLabel(settings.t(satelliteMap ? "Satellite" : "Standard"))
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.zzLine, lineWidth: 0.5)
        )
    }

    @MapContentBuilder
    private func lapMapContent() -> some MapContent {
        if mapRoute.count >= 2 {
            MapPolyline(coordinates: mapRoute)
                .stroke(Color.zzRed, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }

        if let start = lap.samples.first {
            Annotation(settings.t("Start"), coordinate: mapCoordinate(latitude: start.latitude, longitude: start.longitude)) {
                mapDot(color: Color.zzGreen)
            }
        }

        if let finish = lap.samples.last {
            Annotation(settings.t("Timing point"), coordinate: mapCoordinate(latitude: finish.latitude, longitude: finish.longitude)) {
                mapDot(color: Color.zzRed)
            }
        }

        ForEach(brakingPoints) { point in
            Annotation("", coordinate: mapCoordinate(latitude: point.latitude, longitude: point.longitude)) {
                speedBadge(point.speedKPH)
            }
        }

        if let current = currentSample {
            Annotation("", coordinate: mapCoordinate(latitude: current.latitude, longitude: current.longitude)) {
                mapCurrentArrow
            }
        }
    }

    private struct LapHeadingArrow: Shape {
        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: center.x + x * radius, y: center.y + y * radius)
            }
            var path = Path()
            path.move(to: point(0, -1))
            path.addLine(to: point(0.78, 0.78))
            path.addLine(to: point(0, 0.36))
            path.addLine(to: point(-0.78, 0.78))
            path.closeSubpath()
            return path
        }
    }

    private var mapCurrentArrow: some View {
        ZStack {
            LapHeadingArrow()
                .fill(Color.zzRed)
            LapHeadingArrow()
                .stroke(Color.black.opacity(0.55), lineWidth: 0.8)
        }
        .frame(width: 16, height: 16)
        .rotationEffect(.degrees(currentHeading))
        .shadow(color: Color.black.opacity(0.55), radius: 1.5)
        .animation(.easeOut(duration: 0.15), value: currentSample?.id)
    }

    private var currentHeading: Double {
        guard let current = currentSample else { return 0 }
        if let heading = current.heading {
            return heading
        }
        if let previous = lap.samples.last(where: { $0.elapsed < current.elapsed }) {
            let dLat = current.latitude - previous.latitude
            let dLon = (current.longitude - previous.longitude) * cos(current.latitude * .pi / 180)
            return atan2(dLon, dLat) * 180 / .pi
        }
        return 0
    }

    private var mapRoute: [CLLocationCoordinate2D] {
        lap.samples.map { mapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func mapCoordinate(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        ChinaMapAlignment.display(
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            enabled: settings.alignChinaMap
        )
    }

    private func mapDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    private func speedBadge(_ speed: Double) -> some View {
        Text(verbatim: "\(Int(speed.rounded()))")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.zzRed))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5))
    }

    private struct BrakingPoint: Identifiable {
        let id: Int
        let latitude: Double
        let longitude: Double
        let speedKPH: Double
    }

    /// Max speed reached right before each braking zone, for map labels.
    private var brakingPoints: [BrakingPoint] {
        let samples = lap.samples
        guard samples.count > 3 else { return [] }
        var points: [BrakingPoint] = []
        var index = 1
        while index < samples.count {
            if samples[index - 1].longitudinalG > -0.2, samples[index].longitudinalG <= -0.2 {
                var maxSpeed = samples[index - 1].speedKPH
                var back = index - 1
                while back >= 0 {
                    let sample = samples[back]
                    if sample.longitudinalG <= -0.2 { break }
                    maxSpeed = max(maxSpeed, sample.speedKPH)
                    if back == 0 { break }
                    back -= 1
                }
                points.append(BrakingPoint(
                    id: index,
                    latitude: samples[index].latitude,
                    longitude: samples[index].longitude,
                    speedKPH: maxSpeed
                ))
                var forward = index
                while forward < samples.count, samples[forward].longitudinalG <= -0.2 {
                    forward += 1
                }
                index = max(forward, index + 1)
            } else {
                index += 1
            }
        }
        return Array(points.prefix(5))
    }

    private var videoAlignmentBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "video")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)

            if let clip {
                Text(settings.t("Offset"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)
                Text(String(format: "%+.2fs", clip.lapOffset))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.zzInk)

                Button { adjustOffset(-0.1) } label: {
                    Text(verbatim: "−0.1")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }
                .buttonStyle(.plain)

                Button { adjustOffset(0.1) } label: {
                    Text(verbatim: "+0.1")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }
                .buttonStyle(.plain)

                Button { alignToPlayhead() } label: {
                    Text(settings.t("Align to playhead"))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }
                .buttonStyle(.plain)

                Button { resetClipOffset() } label: {
                    Text(settings.t("Reset"))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.zzMutedSurface))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button { removeVideo() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.zzRed)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.t("Remove"))
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.zzSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.zzLine, lineWidth: 0.5)
        )
    }

    private var videoLaneHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(settings.t("Video"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)
            Text(clip.map { LapSessionRecorder.formatLapTime($0.videoDuration) } ?? "—")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.zzTertiary)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var videoLaneGraph: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.zzMutedSurface.opacity(0.25))

            if let clip, let range = visibleRange(clip) {
                let startX = CGFloat(range.lowerBound) * pointsPerSecond
                let width = CGFloat(range.upperBound - range.lowerBound) * pointsPerSecond

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.zzRed.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.zzRed.opacity(0.7), lineWidth: 1)
                    )
                    .overlay(alignment: .leading) {
                        HStack(spacing: 4) {
                            Image(systemName: "video")
                                .font(.system(size: 9, weight: .semibold))
                            Text(LapSessionRecorder.formatLapTime(clip.videoDuration))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color.zzInk)
                        .padding(.horizontal, 6)
                    }
                    .frame(width: max(14, width), height: 38)
                    .offset(x: max(0, startX))
                    .gesture(clipDragGesture)
            } else {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $videoPickerItem, matching: .videos, preferredItemEncoding: .current, photoLibrary: .shared()) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text(settings.t("Import video"))
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.zzTertiary)
                    }
                    Text(settings.language == .chinese
                         ? "（\(settings.t("Import video to align it with the lap"))）"
                         : "(\(settings.t("Import video to align it with the lap")))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.zzTertiary)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
            }
        }
        .frame(height: 40)
    }

    private var clipDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if clipDragStart == nil {
                    clipDragStart = clip?.lapOffset ?? 0
                    isPlaying = false
                }
                guard var clip else { return }
                let delta = Double(value.translation.width / pointsPerSecond)
                clip.lapOffset = min(max((clipDragStart ?? 0) + delta, -duration), duration)
                self.clip = clip
                syncPlayer()
            }
            .onEnded { _ in
                clipDragStart = nil
                syncPlayer()
            }
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        isImportingVideo = true
        defer { isImportingVideo = false }

        guard let movie = try? await item.loadTransferable(type: MovieTransferable.self) else { return }
        let asset = AVURLAsset(url: movie.url)
        guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { return }

        let newClip = LapVideoClip(url: movie.url, videoDuration: duration.seconds, lapOffset: 0)
        let newPlayer = AVPlayer(url: movie.url)
        newPlayer.actionAtItemEnd = .pause
        clip = newClip
        player = newPlayer
        syncPlayer()
    }

    private func visibleRange(_ clip: LapVideoClip) -> ClosedRange<TimeInterval>? {
        let start = max(0, clip.lapOffset)
        let end = min(duration, clip.lapOffset + clip.videoDuration)
        return end > start ? start...end : nil
    }

    private func isVideoVisible(_ clip: LapVideoClip) -> Bool {
        visibleRange(clip)?.contains(currentTime) ?? false
    }

    private func syncPlayer() {
        guard let player, let clip, let range = visibleRange(clip) else {
            player?.pause()
            return
        }
        guard range.contains(currentTime) else {
            player.pause()
            return
        }
        let sourceTime = max(0, -clip.lapOffset) + (currentTime - range.lowerBound)
        player.seek(
            to: CMTime(seconds: sourceTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    private func syncVideoDrift() {
        guard let player, let clip, let range = visibleRange(clip) else { return }
        guard range.contains(currentTime) else {
            if player.rate != 0 { player.pause() }
            return
        }
        let expected = max(0, -clip.lapOffset) + (currentTime - range.lowerBound)
        let actual = player.currentTime().seconds
        if !actual.isFinite || abs(actual - expected) > 0.35 {
            player.seek(
                to: CMTime(seconds: expected, preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
            )
        }
        if player.rate == 0, isPlaying {
            player.play()
        }
    }

    private func adjustOffset(_ delta: TimeInterval) {
        guard var clip else { return }
        clip.lapOffset = min(max(clip.lapOffset + delta, -duration), duration)
        self.clip = clip
        syncPlayer()
    }

    private func alignToPlayhead() {
        guard var clip else { return }
        clip.lapOffset = min(max(currentTime, -duration), duration)
        self.clip = clip
        syncPlayer()
    }

    private func resetClipOffset() {
        guard var clip else { return }
        clip.lapOffset = 0
        self.clip = clip
        syncPlayer()
    }

    private func removeVideo() {
        player?.pause()
        clip = nil
        player = nil
    }

    // MARK: Timeline

    private var lanes: [LapLane] {
        let samples = lap.samples
        let speedMax = max(60, (samples.map(\.speedKPH).max() ?? 0) * 1.1)
        let altitudeValues = samples.compactMap(\.altitude)
        let altitudeMin = (altitudeValues.min() ?? 0) - 10
        let altitudeMax = max(altitudeMin + 1, (altitudeValues.max() ?? 0) + 10)
        let satelliteMax = max(8, Double(samples.compactMap(\.satellites).max() ?? 0))
        let gRange = -2.0...2.0

        return [
            LapLane(
                id: "speed",
                title: settings.t("Speed"),
                unit: "km/h",
                color: Color.zzRed,
                values: samples.map { ($0.elapsed, $0.speedKPH) },
                range: 0...speedMax
            ),
            LapLane(
                id: "lateralG",
                title: settings.t("Lateral G"),
                unit: "g",
                color: Color.zzAmber,
                values: samples.map { ($0.elapsed, $0.lateralG) },
                range: gRange
            ),
            LapLane(
                id: "longitudinalG",
                title: settings.t("Longitudinal G"),
                unit: "g",
                color: Color.zzGreen,
                values: samples.map { ($0.elapsed, $0.longitudinalG) },
                range: gRange
            ),
            LapLane(
                id: "altitude",
                title: settings.t("Altitude"),
                unit: "m",
                color: Color.zzInk,
                values: samples.compactMap { sample in
                    sample.altitude.map { (sample.elapsed, $0) }
                },
                range: altitudeMin...altitudeMax
            ),
            LapLane(
                id: "satellites",
                title: settings.t("Satellites"),
                unit: "SVs",
                color: Color.zzSecondary,
                values: samples.compactMap { sample in
                    sample.satellites.map { (sample.elapsed, Double($0)) }
                },
                range: 0...satelliteMax
            ),
        ]
    }

    private struct LapLane: Identifiable {
        let id: String
        let title: String
        let unit: String
        let color: Color
        let values: [(time: TimeInterval, value: Double)]
        let range: ClosedRange<Double>
    }

    private var timelineEditor: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 8) {
                Color.clear
                    .frame(height: 24)
                videoLaneHeader
                    .frame(height: 52)
                ForEach(lanes) { lane in
                    laneHeader(lane)
                        .frame(height: 52)
                }
            }
            .frame(width: 96)

            ScrollView(.horizontal) {
                VStack(spacing: 8) {
                    ruler
                        .frame(width: timelineWidth, height: 24)

                    videoLaneGraph
                        .frame(width: timelineWidth, height: 52)

                    ForEach(lanes) { lane in
                        laneGraph(lane)
                            .frame(width: timelineWidth, height: 52)
                    }
                }
                .overlay(alignment: .topLeading) {
                    playhead
                }
                .contentShape(Rectangle())
                .gesture(scrubGesture)
                .simultaneousGesture(zoomGesture)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, 12)
    }

    private var playhead: some View {
        Rectangle()
            .fill(Color.zzRed)
            .frame(width: 1.5)
            .frame(maxHeight: .infinity)
            .offset(x: CGFloat(currentTime) * pointsPerSecond)
            .allowsHitTesting(false)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isPlaying = false
                let time = Double(value.location.x / pointsPerSecond)
                currentTime = min(max(0, time), duration)
                syncPlayer()
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                zoom = min(3, max(0.5, zoom * value))
            }
    }

    private func laneHeader(_ lane: LapLane) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lane.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(lane.unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.zzTertiary)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func laneGraph(_ lane: LapLane) -> some View {
        Canvas { context, size in
            guard lane.values.count > 1 else { return }
            let lower = lane.range.lowerBound
            let upper = lane.range.upperBound
            let span = max(upper - lower, 0.0001)

            if lower < 0 && upper > 0 {
                let zeroY = size.height - CGFloat((0 - lower) / span) * size.height
                var zeroLine = Path()
                zeroLine.move(to: CGPoint(x: 0, y: zeroY))
                zeroLine.addLine(to: CGPoint(x: size.width, y: zeroY))
                context.stroke(
                    zeroLine,
                    with: .color(Color.zzLine.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                )
            }

            var path = Path()
            for (index, point) in lane.values.enumerated() {
                let x = CGFloat(point.time) * pointsPerSecond
                let y = size.height - CGFloat((point.value - lower) / span) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                path,
                with: .color(lane.color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )

            if let last = lane.values.last {
                let x = CGFloat(last.time) * pointsPerSecond
                let y = size.height - CGFloat((last.value - lower) / span) * size.height
                context.fill(
                    Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                    with: .color(lane.color)
                )
            }
        }
        .background(
            Color.zzMutedSurface.opacity(0.25),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var ruler: some View {
        Canvas { context, size in
            let step = tickStep
            var seconds = 0.0
            while seconds <= duration {
                let x = CGFloat(seconds) * pointsPerSecond
                var path = Path()
                path.move(to: CGPoint(x: x, y: 14))
                path.addLine(to: CGPoint(x: x, y: 24))
                context.stroke(
                    path,
                    with: .color(Color.zzTertiary.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 0.5)
                )

                let text = Text(LapAnalysisView.shortTime(seconds))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.zzTertiary)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: x + 12, y: 8),
                    anchor: .leading
                )
                seconds += step
            }
        }
    }

    private var tickStep: Double {
        let pixelsPerSecond = Double(pointsPerSecond)
        if pixelsPerSecond >= 24 { return 5 }
        if pixelsPerSecond >= 12 { return 10 }
        if pixelsPerSecond >= 6 { return 20 }
        return 30
    }
}

// MARK: - Speed gauge

private struct SpeedGaugeView: View {
    let speed: Double
    let maxSpeed: Double
    var size: CGFloat = 72

    private let startDegrees = 135.0
    private let sweepDegrees = 270.0

    var body: some View {
        let fraction = min(max(speed / max(maxSpeed, 1), 0), 1)

        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let radius = min(canvasSize.width, canvasSize.height) / 2 - size * 0.097

                var track = Path()
                track.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(startDegrees),
                    endAngle: .degrees(startDegrees + sweepDegrees),
                    clockwise: true
                )
                context.stroke(
                    track,
                    with: .color(Color.white.opacity(0.16)),
                    style: StrokeStyle(lineWidth: size * 0.042, lineCap: .round)
                )

                if fraction > 0.005 {
                    var active = Path()
                    active.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(startDegrees),
                        endAngle: .degrees(startDegrees + sweepDegrees * fraction),
                        clockwise: true
                    )
                    context.stroke(
                        active,
                        with: .color(Color.zzRed),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }

                for index in 0...6 {
                    let degrees = startDegrees + sweepDegrees * Double(index) / 6
                    let radians = degrees * .pi / 180
                    let inner = CGPoint(
                        x: center.x + cos(radians) * (radius - size * 0.07),
                        y: center.y + sin(radians) * (radius - size * 0.07)
                    )
                    let outer = CGPoint(
                        x: center.x + cos(radians) * (radius - size * 0.014),
                        y: center.y + sin(radians) * (radius - size * 0.014)
                    )
                    var tick = Path()
                    tick.move(to: inner)
                    tick.addLine(to: outer)
                    context.stroke(
                        tick,
                        with: .color(Color.white.opacity(0.35)),
                        style: StrokeStyle(lineWidth: max(1, size * 0.014), lineCap: .round)
                    )
                }
            }

            Capsule()
                .fill(Color.zzRed)
                .frame(width: max(2, size * 0.028), height: size * 0.26)
                .offset(y: -size * 0.13)
                .rotationEffect(.degrees(-135 + 270 * fraction))
                .shadow(color: Color.zzRed.opacity(0.6), radius: 2)

            VStack(spacing: -1) {
                Text(verbatim: "\(Int(speed.rounded()))")
                    .font(.system(size: size * 0.236, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("km/h")
                    .font(.system(size: size * 0.083, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
