import Foundation
import HealthKit

/// Apple Health. Workouts logged in Metastory show up in the Health app and
/// count toward the Activity rings; body, nervous-system, nutrition and
/// symptom signals come back the other way so people aren't typing numbers
/// they've already recorded.
///
/// Apple Health is the reason Metastory works with a ring, a watch, a strap, a
/// cuff, a scale, a CGM or a food app without integrating with any of them
/// directly: Oura, Whoop, Garmin, Polar, Fitbit, Withings, Omron, Qardio,
/// Dexcom, Libre, Eight Sleep, MyFitnessPal, Cronometer and the Apple Watch all
/// write here. Reading Health well is the integration.
///
/// Everything read below is used: resting heart rate, HRV, respiratory rate and
/// sleep drive the nervous-system picture; steps, energy, distance and exercise
/// minutes drive the activity picture; nutrition, caffeine, water and glucose
/// drive the food and blood-sugar picture; the symptom categories are the
/// person's own records of the things this app exists to help with. A health
/// app that asks for more than it uses is the fastest way to a rejection.
final class HealthKitModule: BridgeModule {

    private let store = HKHealthStore()

    private var typesToShare: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    // MARK: - What gets read

    /// How a day's worth of samples collapses into one number. A day's steps
    /// are a total; a day's resting heart rate is an average; walking
    /// steadiness is a level, so the most recent reading is the honest one.
    private enum Agg { case sum, avg, recent }

    private struct DailyQ {
        let key: String
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
        let agg: Agg
        init(_ key: String, _ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ agg: Agg) {
            self.key = key; self.id = id; self.unit = unit; self.agg = agg
        }
    }

    private static let bpm = HKUnit.count().unitDivided(by: HKUnit.minute())
    private static let mgPerDl = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    /// Movement, energy and the cardiovascular picture.
    private static let activityQuantities: [DailyQ] = [
        DailyQ("steps",         .stepCount,                  HKUnit.count(),       .sum),
        DailyQ("activeKcal",    .activeEnergyBurned,         HKUnit.kilocalorie(), .sum),
        DailyQ("basalKcal",     .basalEnergyBurned,          HKUnit.kilocalorie(), .sum),
        DailyQ("exerciseMin",   .appleExerciseTime,          HKUnit.minute(),      .sum),
        DailyQ("standMin",      .appleStandTime,             HKUnit.minute(),      .sum),
        DailyQ("moveMin",       .appleMoveTime,              HKUnit.minute(),      .sum),
        DailyQ("distanceMi",    .distanceWalkingRunning,     HKUnit.mile(),        .sum),
        DailyQ("flights",       .flightsClimbed,             HKUnit.count(),       .sum),
        DailyQ("restingHR",     .restingHeartRate,           HealthKitModule.bpm,                  .avg),
        DailyQ("heartRate",     .heartRate,                  HealthKitModule.bpm,                  .avg),
        DailyQ("walkingHR",     .walkingHeartRateAverage,    HealthKitModule.bpm,                  .avg),
        DailyQ("hrRecovery",    .heartRateRecoveryOneMinute, HealthKitModule.bpm,                  .avg),
        DailyQ("hrvMs",         .heartRateVariabilitySDNN,   HKUnit.secondUnit(with: .milli), .avg),
        DailyQ("respRate",      .respiratoryRate,            HealthKitModule.bpm,                  .avg),
        DailyQ("spo2",          .oxygenSaturation,           HKUnit.percent(),     .avg),
        DailyQ("steadinessPct", .appleWalkingSteadiness,     HKUnit.percent(),     .recent)
    ]

    /// The body itself: pressure and temperature, from a cuff or a thermometer.
    /// Blood pressure comes from Omron, Withings and Qardio.
    private static let bodyQuantities: [DailyQ] = [
        DailyQ("bpSys",      .bloodPressureSystolic,         HKUnit.millimeterOfMercury(), .avg),
        DailyQ("bpDia",      .bloodPressureDiastolic,        HKUnit.millimeterOfMercury(), .avg),
        DailyQ("bodyTempF",  .bodyTemperature,               HKUnit.degreeFahrenheit(),    .avg),
        DailyQ("basalTempF", .basalBodyTemperature,          HKUnit.degreeFahrenheit(),    .avg),
        DailyQ("wristTempC", .appleSleepingWristTemperature, HKUnit.degreeCelsius(),       .avg)
    ]

    /// Food and drink, from whatever the person actually logs in — Cronometer,
    /// MyFitnessPal, Lose It, or the Health app by hand. Caffeine matters to a
    /// nervous-system app and was the conspicuous blind spot before this.
    private static let intakeQuantities: [DailyQ] = [
        DailyQ("waterOz",      .dietaryWater,          HKUnit.fluidOunceUS(),        .sum),
        DailyQ("caffeineMg",   .dietaryCaffeine,       HKUnit.gramUnit(with: .milli), .sum),
        DailyQ("dietKcal",     .dietaryEnergyConsumed, HKUnit.kilocalorie(),         .sum),
        DailyQ("dietProtein",  .dietaryProtein,        HKUnit.gram(),                .sum),
        DailyQ("dietCarb",     .dietaryCarbohydrates,  HKUnit.gram(),                .sum),
        DailyQ("dietFat",      .dietaryFatTotal,       HKUnit.gram(),                .sum),
        DailyQ("dietFiber",    .dietaryFiber,          HKUnit.gram(),                .sum),
        DailyQ("dietSugar",    .dietarySugar,          HKUnit.gram(),                .sum),
        DailyQ("dietSodiumMg", .dietarySodium,         HKUnit.gramUnit(with: .milli), .sum)
    ]

    private static var dailyQuantities: [DailyQ] {
        activityQuantities + bodyQuantities + intakeQuantities
    }

    /// Read as "the most recent value", not a daily series.
    private static let latestQuantities: [(key: String, id: HKQuantityTypeIdentifier, unit: HKUnit)] = [
        ("weightLb",   .bodyMass,           HKUnit.pound()),
        ("bodyFatPct", .bodyFatPercentage,  HKUnit.percent()),
        ("leanMassLb", .leanBodyMass,       HKUnit.pound()),
        ("vo2max",     .vo2Max,             HKUnit(from: "ml/kg*min")),
        ("heightIn",   .height,             HKUnit.inch()),
        ("bmi",        .bodyMassIndex,      HKUnit.count()),
        ("waistIn",    .waistCircumference, HKUnit.inch())
    ]

    /// Symptoms the person recorded themselves, in the Health app or on their
    /// Watch. Self-reported, never inferred — and they happen to be exactly
    /// what this app is about.
    private static let symptomTypes: [(key: String, id: HKCategoryTypeIdentifier)] = [
        ("bloating",        .bloating),
        ("constipation",    .constipation),
        ("diarrhea",        .diarrhea),
        ("heartburn",       .heartburn),
        ("abdominalCramps", .abdominalCramps),
        ("nausea",          .nausea),
        ("headache",        .headache),
        ("fatigue",         .fatigue),
        ("moodChanges",     .moodChanges),
        ("appetiteChanges", .appetiteChanges),
        ("sleepChanges",    .sleepChanges)
    ]

    private var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for entry in Self.dailyQuantities {
            if let type = HKQuantityType.quantityType(forIdentifier: entry.id) { types.insert(type) }
        }
        for entry in Self.latestQuantities {
            if let type = HKQuantityType.quantityType(forIdentifier: entry.id) { types.insert(type) }
        }
        if let glucose = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) { types.insert(glucose) }
        if #available(iOS 17.0, *) {
            if let daylight = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) { types.insert(daylight) }
        }
        for entry in Self.symptomTypes {
            if let type = HKObjectType.categoryType(forIdentifier: entry.id) { types.insert(type) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { types.insert(mindful) }
        if let flow = HKObjectType.categoryType(forIdentifier: .menstrualFlow) { types.insert(flow) }
        types.insert(HKObjectType.workoutType())
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

        case "summary":
            let days = (payload["days"] as? NSNumber)?.intValue ?? 30
            summary(days: max(1, min(days, 180)), reply: reply)

        case "sources":
            sources(reply: reply)

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

    // MARK: - The daily picture

    /// One object per calendar day, plus the latest body-composition values and
    /// the names of whatever wrote the data. Everything is best-effort: a type
    /// that was declined, or that nothing on this person's devices records,
    /// simply doesn't appear in the day it would have been part of.
    private func summary(days: Int, reply: Reply) {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) else {
            reply.failure("Couldn't work out the date range.")
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var byDay: [String: [String: Any]] = [:]
        var latest: [String: Any] = [:]

        func put(_ day: String, _ key: String, _ value: Any) {
            lock.lock()
            var entry = byDay[day] ?? [:]
            entry[key] = value
            byDay[day] = entry
            lock.unlock()
        }

        /// A daily series for one quantity type.
        func collect(_ entry: DailyQ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: entry.id) else { return }
            let options: HKStatisticsOptions
            switch entry.agg {
            case .sum:    options = .cumulativeSum
            case .avg:    options = .discreteAverage
            case .recent: options = .mostRecent
            }
            group.enter()
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                options: options,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity: HKQuantity?
                    switch entry.agg {
                    case .sum:    quantity = statistics.sumQuantity()
                    case .avg:    quantity = statistics.averageQuantity()
                    case .recent: quantity = statistics.mostRecentQuantity()
                    }
                    guard let quantity else { return }
                    var value = quantity.doubleValue(for: entry.unit)
                    if entry.unit == HKUnit.percent() { value *= 100 }
                    put(Self.key(statistics.startDate), entry.key, (value * 10).rounded() / 10)
                }
                group.leave()
            }
            store.execute(query)
        }

        for entry in Self.dailyQuantities { collect(entry) }

        for entry in Self.latestQuantities {
            guard let type = HKQuantityType.quantityType(forIdentifier: entry.id) else { continue }
            group.enter()
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                if let sample = samples?.first as? HKQuantitySample {
                    var value = sample.quantity.doubleValue(for: entry.unit)
                    if entry.unit == HKUnit.percent() { value *= 100 }
                    lock.lock()
                    latest[entry.key] = (value * 10).rounded() / 10
                    latest[entry.key + "Date"] = sample.endDate.timeIntervalSince1970 * 1000
                    lock.unlock()
                }
                group.leave()
            }
            store.execute(query)
        }

        // Blood glucose. A CGM writes hundreds of points a day, so the day is
        // kept as an average with its range — the spread is the interesting
        // part, and an average alone would hide every spike.
        if let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) {
            group.enter()
            let query = HKStatisticsCollectionQuery(
                quantityType: glucoseType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                options: [.discreteAverage, .discreteMin, .discreteMax],
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let average = statistics.averageQuantity() else { return }
                    let day = Self.key(statistics.startDate)
                    put(day, "bgAvg", average.doubleValue(for: Self.mgPerDl).rounded())
                    if let low = statistics.minimumQuantity() {
                        put(day, "bgMin", low.doubleValue(for: Self.mgPerDl).rounded())
                    }
                    if let high = statistics.maximumQuantity() {
                        put(day, "bgMax", high.doubleValue(for: Self.mgPerDl).rounded())
                    }
                }
                group.leave()
            }
            store.execute(query)
        }

        // Time in daylight — the circadian signal the app actively coaches, and
        // the one the Watch has been recording since iOS 17 without anyone
        // asking it to.
        if #available(iOS 17.0, *) {
            if let daylightType = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) {
                group.enter()
                let query = HKStatisticsCollectionQuery(
                    quantityType: daylightType,
                    quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                    options: .cumulativeSum,
                    anchorDate: calendar.startOfDay(for: start),
                    intervalComponents: DateComponents(day: 1)
                )
                query.initialResultsHandler = { _, collection, _ in
                    collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                        guard let sum = statistics.sumQuantity() else { return }
                        put(Self.key(statistics.startDate), "daylightMin", Int(sum.doubleValue(for: HKUnit.minute()).rounded()))
                    }
                    group.leave()
                }
                store.execute(query)
            }
        }

        // Sleep. Segments are grouped into nights and filed under the date the
        // night began, so "Friday's sleep" is the night that started Friday
        // even though most of it lands on Saturday's clock.
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(
                withStart: calendar.date(byAdding: .day, value: -1, to: start),
                end: end,
                options: []
            )
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var nights: [String: [String: Any]] = [:]
                for case let sample as HKCategorySample in samples ?? [] {
                    let night = Self.key(sample.endDate.addingTimeInterval(-12 * 3600))
                    let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
                    var entry = nights[night] ?? [:]

                    func add(_ k: String) { entry[k] = ((entry[k] as? Double) ?? 0) + minutes }

                    switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                        add("inBedMin")
                    case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                        add("asleepMin")
                    case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                        add("asleepMin"); add("coreMin")
                    case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                        add("asleepMin"); add("deepMin")
                    case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                        add("asleepMin"); add("remMin")
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        add("awakeMin")
                    default:
                        break
                    }

                    let startMs = sample.startDate.timeIntervalSince1970 * 1000
                    let endMs = sample.endDate.timeIntervalSince1970 * 1000
                    entry["start"] = min((entry["start"] as? Double) ?? startMs, startMs)
                    entry["end"] = max((entry["end"] as? Double) ?? endMs, endMs)
                    nights[night] = entry
                }
                for (night, var entry) in nights {
                    for (k, v) in entry where v is Double && k.hasSuffix("Min") {
                        entry[k] = Int(((v as? Double) ?? 0).rounded())
                    }
                    put(night, "sleep", entry)
                }
                group.leave()
            }
            store.execute(query)
        }

        // Mindful minutes — Metastory's own breathing work writes these on
        // other platforms, and so do Calm, Headspace and the Watch.
        if let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var minutes: [String: Double] = [:]
                for sample in samples ?? [] {
                    let day = Self.key(sample.startDate)
                    minutes[day] = (minutes[day] ?? 0) + sample.endDate.timeIntervalSince(sample.startDate) / 60
                }
                for (day, value) in minutes { put(day, "mindfulMin", Int(value.rounded())) }
                group.leave()
            }
            store.execute(query)
        }

        // Symptoms the person recorded themselves. Counted per day and per
        // kind; the page reports them back as their own records rather than as
        // anything the app worked out.
        for entry in Self.symptomTypes {
            guard let type = HKObjectType.categoryType(forIdentifier: entry.id) else { continue }
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                var perDay: [String: Int] = [:]
                for sample in samples ?? [] {
                    let day = Self.key(sample.startDate)
                    perDay[day] = (perDay[day] ?? 0) + 1
                }
                lock.lock()
                for (day, count) in perDay {
                    var dayEntry = byDay[day] ?? [:]
                    var symptoms = (dayEntry["symptoms"] as? [String: Any]) ?? [:]
                    symptoms[entry.key] = ["n": count]
                    dayEntry["symptoms"] = symptoms
                    byDay[day] = dayEntry
                }
                lock.unlock()
                group.leave()
            }
            store.execute(query)
        }

        // Cycle tracking. Only the flow is read — enough to see where in the
        // month a pattern sits, and nothing more.
        if let flowType = HKObjectType.categoryType(forIdentifier: .menstrualFlow) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: flowType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                for case let sample as HKCategorySample in samples ?? [] {
                    let label: String
                    switch sample.value {
                    case HKCategoryValueMenstrualFlow.light.rawValue:       label = "light"
                    case HKCategoryValueMenstrualFlow.medium.rawValue:      label = "medium"
                    case HKCategoryValueMenstrualFlow.heavy.rawValue:       label = "heavy"
                    case HKCategoryValueMenstrualFlow.unspecified.rawValue: label = "unspecified"
                    default: continue
                    }
                    put(Self.key(sample.startDate), "menstrualFlow", label)
                }
                group.leave()
            }
            store.execute(query)
        }

        group.notify(queue: .main) {
            let days = byDay
                .map { key, value -> [String: Any] in
                    var day = value
                    day["date"] = key
                    return day
                }
                .sorted { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }

            reply.success([
                "days": days,
                "latest": latest,
                "updated": Date().timeIntervalSince1970 * 1000
            ])
        }
    }

    /// What is actually feeding Health — "Oura", "WHOOP", "Apple Watch",
    /// "Omron", "Dexcom", "Cronometer". Shown in Settings so people can see
    /// their device is landing, rather than wondering whether Metastory
    /// supports it.
    private func sources(reply: Reply) {
        var wanted: [HKSampleType] = []
        let ids: [HKQuantityTypeIdentifier] = [
            .restingHeartRate, .heartRateVariabilitySDNN, .stepCount, .bodyMass,
            .bloodGlucose, .bloodPressureSystolic, .dietaryEnergyConsumed, .oxygenSaturation
        ]
        for id in ids {
            if let type = HKQuantityType.quantityType(forIdentifier: id) { wanted.append(type) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { wanted.append(sleep) }

        let group = DispatchGroup()
        let lock = NSLock()
        var names: Set<String> = []

        for type in wanted {
            group.enter()
            let query = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, _ in
                lock.lock()
                for source in sources ?? [] { names.insert(source.name) }
                lock.unlock()
                group.leave()
            }
            store.execute(query)
        }

        group.notify(queue: .main) {
            reply.success(names.sorted())
        }
    }

    private static func key(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
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
