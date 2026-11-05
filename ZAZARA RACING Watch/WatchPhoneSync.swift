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
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isReachable = false
    @Published private(set) var pendingTransferCount = 0

    private let defaults = UserDefaults.standard
    private let trackKey = "watch.syncedTrackConfig"
    private let tracker = "track"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: WCSession?

    override init() {
        super.init()
        if let data = defaults.data(forKey: trackKey) {
            syncedTrack = try? decoder.decode(LapTrackConfig.self, from: data)
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func sendPendingSessions() {
        guard let session, session.activationState == .activated else { return }
        let pending = LapSessionStore.allSessions()
        pendingTransferCount = pending.count
        guard !pending.isEmpty else { return }
        for record in pending {
            guard let data = try? encoder.encode(record) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(record.id.uuidString).json")
            try? data.write(to: url, options: .atomic)
            _ = session.transferFile(url, metadata: ["sessionID": record.id.uuidString])
        }
    }

    private func handleTrackData(_ data: Data) {
        guard let track = try? decoder.decode(LapTrackConfig.self, from: data) else { return }
        syncedTrack = track
        lastSyncDate = Date()
        defaults.set(data, forKey: trackKey)
        sendPendingSessions()
    }

    private func handleAck(_ ids: [UUID]) {
        LapSessionStore.delete(ids)
        pendingTransferCount = LapSessionStore.allSessions().count
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
        guard let data = applicationContext["track"] as? Data else { return }
        Task { @MainActor in self.handleTrackData(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["track"] as? Data {
            Task { @MainActor in self.handleTrackData(data) }
        }
        if let acked = message["receivedSessions"] as? [String] {
            Task { @MainActor in
                self.handleAck(acked.compactMap(UUID.init(uuidString:)))
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {}

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let acked = userInfo["receivedSessions"] as? [String] {
            Task { @MainActor in
                self.handleAck(acked.compactMap(UUID.init(uuidString:)))
            }
        }
    }
}
