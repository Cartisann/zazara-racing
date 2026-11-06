//
//  PhoneWatchSync.swift
//  ZAZARA RACING
//
//  iPhone side of the watch link: manually pushes the selected track and
//  merges sessions uploaded by the watch into the lap history.
//

#if os(iOS)
import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchSync: NSObject, ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    @Published private(set) var lastPushStatus: String?
    @Published private(set) var watchStatus: WatchStatusPayload?

    private let encoder = JSONEncoder()
    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    func requestWatchUpload() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["action": "requestUpload"], replyHandler: nil, errorHandler: nil)
    }

    private func handleStatusData(_ data: Data) {
        guard let status = try? JSONDecoder().decode(WatchStatusPayload.self, from: data) else { return }
        watchStatus = status
    }

    func pushTrack(_ track: LapTrackConfig, deviceHardwareID: String? = nil) {
        guard let session else {
            lastPushStatus = "WCSession unsupported"
            return
        }
        guard session.activationState == .activated else {
            lastPushStatus = "WCSession inactive (\(session.activationState.rawValue))"
            return
        }
        guard session.isPaired else {
            lastPushStatus = "No paired watch"
            return
        }
        guard let data = try? encoder.encode(track) else {
            lastPushStatus = "Encode failed"
            return
        }
        var payload: [String: Any] = ["track": data]
        if let deviceHardwareID, !deviceHardwareID.isEmpty {
            payload["deviceHardwareID"] = deviceHardwareID
        }
        do {
            try session.updateApplicationContext(payload)
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
            }
            // Queued delivery: arrives even when the watch app is backgrounded
            // or the application context is unchanged.
            session.transferUserInfo(payload)
            lastPushStatus = "已推送到手表"
        } catch {
            lastPushStatus = "Push failed: \(error.localizedDescription)"
        }
    }

    private func handleReceivedFile(_ file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL),
              let record = try? JSONDecoder().decode(LapSession.self, from: data) else { return }
        print("[SYNC] received file id=\(record.id.uuidString.prefix(8)) track=\(record.trackName) laps=\(record.laps.count) started=\(record.startedAt)")
        LapSessionStore.save(record)
        // transferUserInfo is queued by the system, so the ack also arrives
        // when the watch app is in the background (sendMessage would not).
        if let session, session.activationState == .activated {
            session.transferUserInfo(["receivedSessions": [record.id.uuidString]])
        }
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        Task { @MainActor in self.handleReceivedFile(file) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message["watchStatus"] as? Data {
            Task { @MainActor in self.handleStatusData(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["watchStatus"] as? Data {
            Task { @MainActor in self.handleStatusData(data) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["watchStatus"] as? Data {
            Task { @MainActor in self.handleStatusData(data) }
        }
    }
}
#endif
