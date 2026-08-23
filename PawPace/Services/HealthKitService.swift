import Foundation
import HealthKit

@MainActor
final class HealthKitService: ObservableObject {
    enum AuthorizationState: Equatable {
        case notRequested
        case unavailable
        case authorized
        case denied
    }

    @Published private(set) var authorizationState: AuthorizationState = .notRequested

    private let store = HKHealthStore()

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return
        }

        var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            shareTypes.insert(distance)
            readTypes.insert(distance)
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HealthKitError.authorizationDenied)
                    }
                }
            }
            authorizationState = .authorized
        } catch {
            authorizationState = .denied
        }
    }

    func latestHeartRate() async -> Int? {
        guard
            authorizationState == .authorized,
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return nil }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: Int(value.rounded()))
            }
            store.execute(query)
        }
    }

    func saveRun(_ summary: RunSummary) async throws {
        guard authorizationState == .authorized else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: summary.startedAt)

        if let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: summary.distanceMeters),
                start: summary.startedAt,
                end: summary.endedAt
            )
            try await builder.addSamples([distanceSample])
        }

        try await builder.endCollection(at: summary.endedAt)
        _ = try await builder.finishWorkout()
    }
}

private enum HealthKitError: Error {
    case authorizationDenied
}
