import Combine
import Foundation

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

struct LapGate: Codable, Equatable {
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

struct LapTrackConfig: Codable, Equatable, Identifiable {
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

    static func delete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            let url = sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
            try? FileManager.default.removeItem(at: url)
        }
        if let latest = decode(latestURL), ids.contains(latest.id) {
            try? FileManager.default.removeItem(at: latestURL)
        }
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
        guard time.isFinite, time >= 0 else { return "—" }
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

