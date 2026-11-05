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

    func pushTrack(_ track: LapTrackConfig) {
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
        guard session.isWatchAppInstalled else {
            lastPushStatus = "Watch app not installed"
            return
        }
        guard let data = try? encoder.encode(track) else {
            lastPushStatus = "Encode failed"
            return
        }
        do {
            try session.updateApplicationContext(["track": data])
            if session.isReachable {
                session.sendMessage(["track": data], replyHandler: nil, errorHandler: nil)
            }
            lastPushStatus = "已推送到手表"
        } catch {
            lastPushStatus = "Push failed: \(error.localizedDescription)"
        }
    }

    private func handleReceivedFile(_ file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL),
              let record = try? JSONDecoder().decode(LapSession.self, from: data) else { return }
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
}
#endif
