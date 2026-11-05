//
//  WatchSyncWireFormatTests.swift
//  ZAZARA RACINGTests
//
//  Verifies the data contracts shared with the watch app: the session wire
//  format used for uploads and the local file store delete-after-ack step.
//

import XCTest
@testable import ZAZARA_RACING

final class WatchSyncWireFormatTests: XCTestCase {
    func testSessionWireFormatRoundtrip() throws {
        let session = LapSession(
            id: UUID(),
            trackID: "tianma",
            trackName: "天马",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_060),
            laps: []
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LapSession.self, from: data)

        XCTAssertEqual(decoded, session)
    }

    func testTrackConfigWireFormatRoundtrip() throws {
        let track = LapTrackConfig(
            trackID: "tianma",
            name: "天马",
            gate: LapGate(latitude: 31.0, longitude: 121.0, heading: 90, widthMeters: 12)
        )

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(LapTrackConfig.self, from: data)

        XCTAssertEqual(decoded, track)
    }

    func testSessionUploadedThenDeletedFromWatchStore() {
        let session = LapSession(
            id: UUID(),
            trackID: "tianma",
            trackName: "天马",
            startedAt: Date(),
            endedAt: nil,
            laps: []
        )

        LapSessionStore.save(session)
        XCTAssertTrue(LapSessionStore.allSessions().contains { $0.id == session.id })

        // Phone acknowledged the upload -> watch removes its local copy.
        LapSessionStore.delete([session.id])
        XCTAssertFalse(LapSessionStore.allSessions().contains { $0.id == session.id })
    }
}
