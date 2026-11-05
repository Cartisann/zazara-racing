//
//  WatchWorkoutSession.swift
//  ZAZARA RACING Watch
//
//  Keeps the watch app running in the background while a stint is recorded.
//

import Foundation
import HealthKit

@MainActor
final class WatchWorkoutSession: NSObject, ObservableObject {
    @Published private(set) var isRunning = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }

        let workoutType = HKObjectType.workoutType()
        store.requestAuthorization(toShare: [workoutType], read: [workoutType]) { [weak self] success, _ in
            guard success else { return }
            Task { @MainActor in
                self?.beginSession()
            }
        }
    }

    private func beginSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            session.delegate = self
            self.session = session
            session.startActivity(with: Date())
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        session?.end()
        session = nil
        isRunning = false
    }
}

extension WatchWorkoutSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}
