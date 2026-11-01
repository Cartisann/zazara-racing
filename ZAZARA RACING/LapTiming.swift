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
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Models

struct LapTelemetrySample: Codable, Identifiable, Equatable {
    let id: Int
    let time: Date
    let latitude: Double
    let longitude: Double
    let speedKPH: Double
    let heading: Double?
    let altitude: Double?
    let satellites: Int?
    let hdop: Double?
    let vdop: Double?
    let fix: Int?
    let distanceKm: Double
    let elapsed: TimeInterval
    let lateralG: Double
    let longitudinalG: Double
}

struct LapRecord: Identifiable, Codable, Equatable {
    let id: Int
    let start: Date
    let end: Date
    let duration: TimeInterval
    let samples: [LapTelemetrySample]
    let maxSpeedKPH: Double
    let avgSpeedKPH: Double
    let distanceKm: Double
    let maxLateralG: Double
    let maxLongitudinalG: Double
    let isComplete: Bool

    static func build(
        number: Int,
        start: Date,
        end: Date,
        samples: [LapTelemetrySample]
    ) -> LapRecord {
        let speeds = samples.map(\.speedKPH)
        let distance = max(0, (samples.last?.distanceKm ?? 0) - (samples.first?.distanceKm ?? 0))
        return LapRecord(
            id: number,
            start: start,
            end: end,
            duration: max(0, end.timeIntervalSince(start)),
            samples: samples,
            maxSpeedKPH: speeds.max() ?? 0,
            avgSpeedKPH: speeds.isEmpty ? 0 : speeds.reduce(0, +) / Double(speeds.count),
            distanceKm: distance,
            maxLateralG: samples.map { abs($0.lateralG) }.max() ?? 0,
            maxLongitudinalG: samples.map { abs($0.longitudinalG) }.max() ?? 0,
            isComplete: true
        )
    }
}

struct LapSession: Codable, Equatable, Identifiable {
    var id: UUID
    var trackID: String
    var trackName: String
    var startedAt: Date
    var endedAt: Date?
    var laps: [LapRecord]

    var bestLap: LapRecord? {
        laps.filter(\.isComplete).min { $0.duration < $1.duration }
    }

    var lastLap: LapRecord? {
        laps.last(where: \.isComplete)
    }

    var totalDistanceKm: Double {
        laps.map(\.distanceKm).reduce(0, +)
    }

    var totalDuration: TimeInterval {
        laps.map(\.duration).reduce(0, +)
    }
}

// MARK: - Track gate

struct LapGate: Equatable {
    var latitude: Double
    var longitude: Double
    var heading: Double
    var widthMeters: Double

    private func localOffset(latitude: Double, longitude: Double) -> (east: Double, north: Double) {
        let cosLat = cos(self.latitude * .pi / 180)
        let east = (longitude - self.longitude) * 111_320 * cosLat
        let north = (latitude - self.latitude) * 110_540
        return (east, north)
    }

    func signedForward(latitude: Double, longitude: Double) -> Double {
        let offset = localOffset(latitude: latitude, longitude: longitude)
        let radians = heading * .pi / 180
        return offset.east * sin(radians) + offset.north * cos(radians)
    }

    func signedLateral(latitude: Double, longitude: Double) -> Double {
        let offset = localOffset(latitude: latitude, longitude: longitude)
        let radians = heading * .pi / 180
        return offset.east * cos(radians) - offset.north * sin(radians)
    }
}

struct LapTrackConfig: Equatable, Identifiable {
    var trackID: String
    var name: String
    var gate: LapGate

    var id: String { trackID }

    static func load(jsonData: Data, name: String, trackID: String) -> LapTrackConfig? {
        guard
            let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let track = root["track"] as? [String: Any],
            let traps = track["traps"] as? [[String: Any]]
        else { return nil }

        struct Candidate {
            let latitude: Double
            let longitude: Double
            let heading: Double
            let width: Double
            let priority: Int
        }

        var candidates: [Candidate] = []
        for trap in traps {
            guard
                let latitudeRaw = (trap["centerLatitude"] as? NSNumber)?.intValue,
                let longitudeRaw = (trap["centerLongitude"] as? NSNumber)?.intValue,
                latitudeRaw != 2147483647,
                longitudeRaw != 2147483647
            else { continue }

            let type = trap["type"] as? String ?? ""
            let priority: Int
            switch type {
            case "起始/终点线": priority = 0
            case "起始线": priority = 1
            case "终点线": priority = 2
            default: priority = 3
            }

            let heading = (trap["heading"] as? NSNumber)?.doubleValue ?? 0
            let width = (trap["width"] as? NSNumber)?.doubleValue ?? 20
            candidates.append(Candidate(
                latitude: Double(latitudeRaw) / 10_000_000,
                longitude: Double(longitudeRaw) / 10_000_000,
                heading: heading,
                width: max(4, width),
                priority: priority
            ))
        }

        guard let best = candidates.min(by: { $0.priority < $1.priority }) else { return nil }
        return LapTrackConfig(
            trackID: trackID,
            name: name,
            gate: LapGate(
                latitude: best.latitude,
                longitude: best.longitude,
                heading: best.heading,
                widthMeters: best.width
            )
        )
    }
}

struct LapCrossingDetector {
    let gate: LapGate
    private var previous: (latitude: Double, longitude: Double)?

    mutating func ingest(latitude: Double, longitude: Double) -> Bool {
        defer { previous = (latitude, longitude) }
        guard let previous else { return false }

        let from = gate.signedForward(latitude: previous.latitude, longitude: previous.longitude)
        let to = gate.signedForward(latitude: latitude, longitude: longitude)
        guard from < 0, to >= 0 else { return false }

        let fraction = from / (from - to)
        let crossingLatitude = previous.latitude + (latitude - previous.latitude) * fraction
        let crossingLongitude = previous.longitude + (longitude - previous.longitude) * fraction
        let lateral = gate.signedLateral(latitude: crossingLatitude, longitude: crossingLongitude)
        return abs(lateral) <= gate.widthMeters / 2
    }
}

// MARK: - Session store

enum LapSessionStore {
    private static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ZAZARALapSessions", isDirectory: true)
    }

    private static var sessionsDirectory: URL {
        rootDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    private static var latestURL: URL {
        rootDirectory.appendingPathComponent("latest.json")
    }

    private static func decode(_ url: URL) -> LapSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LapSession.self, from: data)
    }

    private static func encode(_ session: LapSession) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(session)
    }

    static func loadLatest() -> LapSession? {
        migrateIfNeeded()
        return decode(latestURL) ?? allSessions().first
    }

    static func save(_ session: LapSession) {
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        guard let data = encode(session) else { return }
        try? data.write(to: sessionURL(session), options: .atomic)
        try? data.write(to: latestURL, options: .atomic)
    }

    static func allSessions() -> [LapSession] {
        migrateIfNeeded()
        var sessions: [UUID: LapSession] = [:]
        if let latest = decode(latestURL) {
            sessions[latest.id] = latest
        }
        if let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "json" {
                if let session = decode(file) {
                    sessions[session.id] = session
                }
            }
        }
        return sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    private static func sessionURL(_ session: LapSession) -> URL {
        sessionsDirectory.appendingPathComponent("\(session.id.uuidString).json")
    }

    /// The first version kept only latest.json. Copy it into the sessions
    /// folder so history starts with the previously recorded session.
    private static func migrateIfNeeded() {
        try? FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        guard let latest = decode(latestURL) else { return }
        let destination = sessionURL(latest)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        if let data = encode(latest) {
            try? data.write(to: destination, options: .atomic)
        }
    }
}

// MARK: - Recorder

@MainActor
final class LapSessionRecorder: ObservableObject {
    @Published private(set) var track: LapTrackConfig?
    @Published private(set) var session: LapSession?
    @Published private(set) var isRecording = false
    @Published private(set) var currentLapElapsed: TimeInterval = 0

    private var detector: LapCrossingDetector?
    private var sessionStart: Date?
    private var lapStart: Date?
    private var lapSamples: [LapTelemetrySample] = []
    private var previousSample: (date: Date, speedMS: Double, heading: Double?)?
    private var filteredLateralG: Double = 0
    private var filteredLongitudinalG: Double = 0
    private var nextSampleID = 0
    private var nextLapNumber = 1
    // The receiver's RTC can be stale (e.g. a week behind); anchor record
    // timestamps to the device clock while keeping relative durations.
    private var timeAnchor: TimeInterval = 0
    private var timeAnchored = false

    var bestLap: LapRecord? { session?.bestLap }
    var lastLap: LapRecord? { session?.lastLap }

    var bestLapText: String {
        session?.bestLap.map { Self.formatLapTime($0.duration) } ?? "—"
    }

    var lastLapText: String {
        session?.lastLap.map { Self.formatLapTime($0.duration) } ?? "—"
    }

    var currentLapText: String {
        guard lapStart != nil else { return "—" }
        return Self.formatLapTime(currentLapElapsed)
    }

    var timeDifference: Double? {
        guard
            let best = session?.bestLap,
            let last = session?.lastLap,
            last.id != best.id
        else { return nil }
        return last.duration - best.duration
    }

    nonisolated static func formatLapTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "—" }
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    func start(track: LapTrackConfig?) {
        self.track = track
        detector = track.map { LapCrossingDetector(gate: $0.gate) }
        sessionStart = Date()
        lapStart = nil
        lapSamples = []
        previousSample = nil
        filteredLateralG = 0
        filteredLongitudinalG = 0
        nextSampleID = 0
        nextLapNumber = 1
        currentLapElapsed = 0
        isRecording = true
        timeAnchor = 0
        timeAnchored = false

        session = LapSession(
            id: UUID(),
            trackID: track?.trackID ?? "",
            trackName: track?.name ?? "",
            startedAt: Date(),
            endedAt: nil,
            laps: []
        )
    }

    func stop() {
        isRecording = false
        guard var session, !session.laps.isEmpty else { return }
        session.endedAt = Date()
        self.session = session
        LapSessionStore.save(session)
    }

    func ingest(_ telemetry: TrackTelemetry) {
        guard isRecording else { return }
        guard let date = telemetry.date else { return }
        guard let latitude = telemetry.latitude, let longitude = telemetry.longitude else { return }

        if !timeAnchored {
            timeAnchor = Date().timeIntervalSince(date)
            timeAnchored = true
        }
        let sampleDate = date.addingTimeInterval(timeAnchor)

        let speedKPH = max(0, telemetry.speedKPH ?? 0)
        let speedMS = speedKPH / 3.6
        var lateral = 0.0
        var longitudinal = 0.0

        if let previousSample {
            let dt = date.timeIntervalSince(previousSample.date)
            if dt > 0.02, dt < 2 {
                longitudinal = (speedMS - previousSample.speedMS) / dt / 9.80665
                if let heading = telemetry.heading, let previousHeading = previousSample.heading {
                    var delta = heading - previousHeading
                    while delta > 180 { delta -= 360 }
                    while delta < -180 { delta += 360 }
                    lateral = speedMS * (delta * .pi / 180 / dt) / 9.80665
                }
            }
        }

        filteredLateralG = filteredLateralG * 0.7 + min(max(lateral, -4), 4) * 0.3
        filteredLongitudinalG = filteredLongitudinalG * 0.7 + min(max(longitudinal, -4), 4) * 0.3
        previousSample = (date, speedMS, telemetry.heading)

        let elapsed = lapStart.map { sampleDate.timeIntervalSince($0) } ?? 0
        let sample = LapTelemetrySample(
            id: nextSampleID,
            time: sampleDate,
            latitude: latitude,
            longitude: longitude,
            speedKPH: speedKPH,
            heading: telemetry.heading,
            altitude: telemetry.altitude,
            satellites: telemetry.satellites,
            hdop: telemetry.hdop,
            vdop: telemetry.vdop,
            fix: telemetry.fix,
            distanceKm: telemetry.distanceKm,
            elapsed: max(0, elapsed),
            lateralG: min(max(filteredLateralG, -4), 4),
            longitudinalG: min(max(filteredLongitudinalG, -4), 4)
        )
        nextSampleID += 1

        if let lapStart {
            lapSamples.append(sample)
            currentLapElapsed = sampleDate.timeIntervalSince(lapStart)
        }

        guard detector != nil else { return }
        let crossed = detector!.ingest(latitude: latitude, longitude: longitude)
        guard crossed else { return }

        if let start = lapStart {
            let duration = sampleDate.timeIntervalSince(start)
            guard duration >= 20 else { return }
            let lap = LapRecord.build(
                number: nextLapNumber,
                start: start,
                end: sampleDate,
                samples: lapSamples
            )
            nextLapNumber += 1
            var updated = session
            updated?.laps.append(lap)
            session = updated
            lapStart = sampleDate
            lapSamples = []
            currentLapElapsed = 0
            if let updated {
                LapSessionStore.save(updated)
            }
        } else {
            lapStart = sampleDate
            lapSamples = []
            currentLapElapsed = 0
        }
    }
}

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
            try FileManager.default.copyItem(at: received.file, to: destination)
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
        ScrollView {
            LazyVStack(spacing: 10) {
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
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            LapAnalysisView(session: session, autoPlay: false)
                        } label: {
                            historyRow(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
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

    private let playbackTimer = Timer
        .publish(every: 1.0 / 30.0, on: .main, in: .common)
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
            let isWide = proxy.size.width >= 700 && proxy.size.width > proxy.size.height
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if isWide {
                        HStack(alignment: .top, spacing: 14) {
                            videoPanel
                            VStack(spacing: 10) {
                                currentValuesPanel
                                lapInfoPanel
                            }
                            .frame(width: 300)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    } else {
                        videoPanel
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        currentValuesPanel
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                        lapInfoPanel
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    transportBar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    videoAlignmentBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

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
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            isPlaying = false
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
            currentTime += 1.0 / 30.0
            if currentTime >= duration {
                currentTime = duration
                isPlaying = false
                player?.pause()
                return
            }
            syncVideoDrift()
        }
    }

    private var currentValuesPanel: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.t("Speed"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.zzSecondary)
                Text(verbatim: "\(Int((currentSample?.speedKPH ?? 0).rounded()))")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.zzInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("km/h")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.zzTertiary)
            }

            VStack(alignment: .leading, spacing: 5) {
                valueRow(settings.t("Lateral G"), String(format: "%.2f g", currentSample?.lateralG ?? 0))
                valueRow(settings.t("Longitudinal G"), String(format: "%.2f g", currentSample?.longitudinalG ?? 0))
                valueRow(settings.t("Elapsed time"), currentTimeText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 18)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.zzSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
        }
        .frame(width: 150)
    }

    private var lapInfoPanel: some View {
        HStack(spacing: 10) {
            infoCell(settings.t("Lap time"), LapSessionRecorder.formatLapTime(lap.duration))
            infoCell(settings.t("Maximum"), String(format: "%.0f km/h", lap.maxSpeedKPH))
            if let bestLap, lap.id != bestLap.id {
                infoCell(settings.t("Time difference"), String(format: "%+.2f", lap.duration - bestLap.duration))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zzCard(cornerRadius: 16)
    }

    private func infoCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.zzTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(9)
        .frame(minWidth: 96, alignment: .leading)
        .background(Color.zzMutedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var transportBar: some View {
        HStack(spacing: 14) {
            Button {
                if currentTime >= duration { currentTime = 0 }
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.zzInk)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.zzMutedSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t(isPlaying ? "Pause" : "Play"))

            Button {
                currentTime = 0
                isPlaying = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.zzInk)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.zzMutedSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.t("Restart"))

            Text(currentTimeText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzInk)

            Text("/")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.zzTertiary)

            Text(LapSessionRecorder.formatLapTime(duration))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.zzSecondary)

            Spacer(minLength: 0)

            Text("1x")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.zzSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.zzMutedSurface))
        }
    }

    // MARK: Video

    private var importVideoButton: some View {
        PhotosPicker(selection: $videoPickerItem, matching: .videos, photoLibrary: .shared()) {
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
                PhotosPicker(selection: $videoPickerItem, matching: .videos, photoLibrary: .shared()) {
                    VStack(spacing: 8) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 26, weight: .semibold))
                        Text(settings.t("Import video"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.zzSecondary)
                }
            }

            if isImportingVideo {
                ProgressView()
                    .tint(Color.white)
            }

            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(currentTimeText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Spacer(minLength: 0)
                    if let clip {
                        Text(String(format: "%+.2fs", clip.lapOffset))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.zzLine, lineWidth: 0.5)
        )
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
                Text(settings.t("Import video to align it with the lap"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.zzTertiary)
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
                PhotosPicker(selection: $videoPickerItem, matching: .videos, photoLibrary: .shared()) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text(settings.t("Import video"))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.zzTertiary)
                    .padding(.leading, 12)
                }
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
