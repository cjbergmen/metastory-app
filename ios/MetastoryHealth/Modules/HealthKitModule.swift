import Foundation
import HealthKit

/// Apple Health. Workouts logged in Metastory show up in the Health app and
/// count toward the Activity rings; weight and steps come back the other way
/// so people aren't typing numbers they've already recorded elsewhere.
///
/// Deliberately narrow: four data types, no background delivery, nothing read
/// that the app doesn't display. A health app asking for more than it uses is
/// the fastest way to a rejection.
final class HealthKitModule: BridgeModule {

    private let store = HKHealthStore()

    private var typesToShare: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    private var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let mass = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        return types
    }

    // MARK: - BridgeModule

    func handle(action: String, payload: [String: Any], reply: Reply) {
        guard HKHealthStore.isHealthDataAvailable() else {
            // iPad and the simulator on some SDKs. Answer honestly instead of
            // failing, so the page can just hide the Health row.
            if action == "isAvailable" {
                reply.success(false)
            } else {
                reply.failure("Apple Health isn't available on this device.")
            }
            return
        }

        switch action {
        case "isAvailable":
            reply.success(true)

        case "requestAuthorization":
            store.requestAuthorization(toShare: typesToShare, read: typesToRead) { granted, error in
                if let error {
                    reply.failure(error)
                } else {
                    // `granted` only means the sheet completed. Whether any
                    // individual type was allowed is deliberately not exposed
                    // for reads, so the page treats an empty read as "no data".
                    reply.success(granted)
                }
            }

        case "status":
            reply.success(writeStatus())

        case "saveWorkout":
            saveWorkout(payload: payload, reply: reply)

        case "latestBodyMass":
            latestBodyMass(reply: reply)

        case "stepsToday":
            stepsToday(reply: reply)

        default:
            reply.failure("Unknown health action '\(action)'.")
        }
    }

    /// Only the *write* permission can be read back; Apple hides read
    /// permissions so that an app can't infer that you have no data.
    private func writeStatus() -> String {
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return "granted"
        case .sharingDenied: return "denied"
        case .notDetermined: return "default"
        @unknown default: return "default"
        }
    }

    // MARK: - Writing workouts

    private func saveWorkout(payload: [String: Any], reply: Reply) {
        guard
            let startMillis = (payload["start"] as? NSNumber)?.doubleValue,
            let endMillis = (payload["end"] as? NSNumber)?.doubleValue,
            endMillis > startMillis
        else {
            reply.failure("A workout needs a start and an end.")
            return
        }

        let start = Date(timeIntervalSince1970: startMillis / 1000)
        let end = Date(timeIntervalSince1970: endMillis / 1000)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(payload["activity"] as? String)

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        builder.beginCollection(withStart: start) { [weak self] started, error in
            guard started else {
                reply.failure(error ?? Self.genericError)
                return
            }

            self?.addEnergy(payload: payload, to: builder, start: start, end: end) {
                builder.endCollection(withEnd: end) { ended, error in
                    guard ended else {
                        reply.failure(error ?? Self.genericError)
                        return
                    }
                    builder.finishWorkout { workout, error in
                        if let error {
                            reply.failure(error)
                        } else {
                            reply.success(workout != nil)
                        }
                    }
                }
            }
        }
    }

    /// Calories are optional — a strength session logged without them is still
    /// worth writing, it just won't fill the move ring.
    private func addEnergy(
        payload: [String: Any],
        to builder: HKWorkoutBuilder,
        start: Date,
        end: Date,
        completion: @escaping () -> Void
    ) {
        guard
            let kilocalories = (payload["calories"] as? NSNumber)?.doubleValue,
            kilocalories > 0,
            let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            completion()
            return
        }

        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
            start: start,
            end: end
        )

        builder.add([sample]) { _, _ in completion() }
    }

    private static func activityType(_ name: String?) -> HKWorkoutActivityType {
        switch name {
        case "running": return .running
        case "walking": return .walking
        case "cycling": return .cycling
        case "hiit": return .highIntensityIntervalTraining
        case "yoga": return .yoga
        case "coreTraining": return .coreTraining
        case "flexibility": return .flexibility
        case "crossTraining": return .crossTraining
        case "mindAndBody": return .mindAndBody
        default: return .traditionalStrengthTraining
        }
    }

    // MARK: - Reading

    private func latestBodyMass(reply: Reply) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            reply.failure("Body mass isn't available.")
            return
        }

        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        ) { _, samples, error in
            if let error {
                reply.failure(error)
                return
            }
            guard let sample = samples?.first as? HKQuantitySample else {
                // No data, or read access was declined — indistinguishable by
                // design, and the page treats both the same way.
                reply.success(NSNull())
                return
            }
            reply.success([
                "kg": sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                "lb": sample.quantity.doubleValue(for: .pound()),
                "date": sample.endDate.timeIntervalSince1970 * 1000
            ])
        }

        store.execute(query)
    }

    private func stepsToday(reply: Reply) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            reply.failure("Step count isn't available.")
            return
        }

        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if let error {
                reply.failure(error)
                return
            }
            guard let sum = statistics?.sumQuantity() else {
                reply.success(NSNull())
                return
            }
            reply.success(Int(sum.doubleValue(for: .count())))
        }

        store.execute(query)
    }

    private static var genericError: Error {
        NSError(
            domain: "MetastoryHealth",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Health couldn't save that workout."]
        )
    }
}
