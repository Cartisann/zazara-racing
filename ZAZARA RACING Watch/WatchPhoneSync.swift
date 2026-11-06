//
//  WatchPhoneSync.swift
//  ZAZARA RACING Watch
//
//  Receives the manually pushed track config from the iPhone and uploads
//  recorded sessions; sessions are deleted after the phone acknowledges them.
//

import Foundation
import WatchConnectivity

@MainActor
final class WatchPhoneSync: NSObject, ObservableObject {
    @Published private(set) var syncedTrack: LapTrackConfig?
    @Published private(set) var syncedDeviceHardwareID: String?
    @Published private(set) var hasReceivedPush = false
    @Published private(set) var pushSequence = 0
    @Published private(set) var pauseToken = 0
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isReachable = false
    @Published private(set) var pendingTransferCount = 0

    private let defaults = UserDefaults.standard
    private let trackKey = "watch.syncedTrackConfig"
    private let deviceKey = "watch.syncedDeviceHardwareID"
    private let pushKey = "watch.hasReceivedPush"
    private let tracker = "track"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: WCSession?

    override init() {
        super.init()
        if let data = defaults.data(forKey: trackKey) {
            syncedTrack = try? decoder.decode(LapTrackConfig.self, from: data)
        }
        syncedDeviceHardwareID = defaults.string(forKey: deviceKey)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func requestPause() {
        pauseToken += 1
    }

    func sendStatus(moduleConnected: Bool, moduleName: String?, isRecording: Bool) {
        let sessions = LapSessionStore.allSessions().map {
            WatchSessionSummary(
                id: $0.id,
                trackName: $0.trackName,
                startedAt: $0.startedAt,
                lapCount: $0.laps.filter(\.isComplete).count,
                bestLapDuration: $0.bestLap?.duration
            )
        }
        let status = WatchStatusPayload(
            moduleConnected: moduleConnected,
            moduleName: moduleName,
            isRecording: isRecording,
            pendingCount: sessions.count,
            sessions: sessions
        )
        guard let data = try? encoder.encode(status) else { return }
        guard let session, session.activationState == .activated else { return }
        let payload: [String: Any] = ["watchStatus": data]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    func sendPendingSessions() {
        guard let session, session.activationState == .activated else {
            print("[SYNC] upload skipped: session not activated")
            return
        }
        let pending = LapSessionStore.allSessions()
        pendingTransferCount = pending.count
        print("[SYNC] pending sessions=\(pending.count) ids=\(pending.map { $0.id.uuidString.prefix(8) })")
        guard !pending.isEmpty else { return }
        for record in pending {
            guard let data = try? encoder.encode(record) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(record.id.uuidString).json")
            try? data.write(to: url, options: .atomic)
            _ = session.transferFile(url, metadata: ["sessionID": record.id.uuidString])
            print("[SYNC] transferFile id=\(record.id.uuidString.prefix(8)) track=\(record.trackName) laps=\(record.laps.count)")
        }
    }

    private func handleDeviceHardwareID(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        syncedDeviceHardwareID = trimmed
        defaults.set(trimmed, forKey: deviceKey)
        markPushed()
    }

    private func markPushed() {
        // Per app run: only a push received in this run may start Bluetooth.
        hasReceivedPush = true
        pushSequence += 1
    }

    private func handleTrackData(_ data: Data) {
        guard let track = try? decoder.decode(LapTrackConfig.self, from: data) else { return }
        syncedTrack = track
        lastSyncDate = Date()
        defaults.set(data, forKey: trackKey)
        markPushed()
        sendPendingSessions()
    }

    private func handleAck(_ ids: [UUID]) {
        print("[SYNC] ack ids=\(ids.map { $0.uuidString.prefix(8) })")
        LapSessionStore.delete(ids)
        let remaining = LapSessionStore.allSessions()
        pendingTransferCount = remaining.count
        print("[SYNC] after delete remaining=\(remaining.count) ids=\(remaining.map { $0.id.uuidString.prefix(8) })")
    }
}

extension WatchPhoneSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.sendPendingSessions()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.sendPendingSessions()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["track"] as? Data {
            Task { @MainActor in self.handleTrackData(data) }
        }
        if let id = applicationContext["deviceHardwareID"] as? String {
            Task { @MainActor in self.handleDeviceHardwareID(id) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["track"] as? Data {
            Task { @MainActor in self.handleTrackData(data) }
        }
        if let id = message["deviceHardwareID"] as? String {
            Task { @MainActor in self.handleDeviceHardwareID(id) }
        }
        if let acked = message["receivedSessions"] as? [String] {
            Task { @MainActor in
                self.handleAck(acked.compactMap(UUID.init(uuidString:)))
            }
        }
        if let action = message["action"] as? String, action == "requestUpload" {
            Task { @MainActor in self.sendPendingSessions() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {}

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["track"] as? Data {
            Task { @MainActor in self.handleTrackData(data) }
        }
        if let id = userInfo["deviceHardwareID"] as? String {
            Task { @MainActor in self.handleDeviceHardwareID(id) }
        }
        if let acked = userInfo["receivedSessions"] as? [String] {
            Task { @MainActor in
                self.handleAck(acked.compactMap(UUID.init(uuidString:)))
            }
        }
    }
}
