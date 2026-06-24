import Foundation
import WhoopStore
import StrandImport

/// Maps a parsed + aggregated Apple Health export into the on-device store under its own
/// source id ("apple-health"), so it sits BESIDE Whoop for the per-source pages and cross-source
/// consensus. Populates appleDaily, dailyMetric, the generic metricSeries, and workouts.
enum AppleHealthImport {

    @discardableResult
    static func importExport(url: URL, into store: WhoopStore, deviceId: String) async throws -> ImportSummary {
        // retainRawSamples:false — a multi-year export is millions of HealthSample
        // structs (hundreds of MB to >1 GB); iOS jetsam-kills the app if we hold
        // them all (issue #355). The importer folds them into per-day aggregates
        // incrementally and drops the raw array; `aggregate` consumes the
        // pre-folded `sampleDailies`.
        let result = try ImportCoordinator().importAppleHealth(from: url, retainRawSamples: false)
        let daily = AppleHealthAggregator.aggregate(result)

        // Apple-specific daily aggregates (steps/energy/vo2/hr/weight).
        let appleRows = daily.map { d in
            AppleDaily(day: d.day,
                       steps: d.steps.map { Int($0) },
                       activeKcal: d.activeKcal, basalKcal: d.basalKcal, vo2max: d.vo2max,
                       avgHr: d.avgHr.map { Int($0.rounded()) },
                       maxHr: d.maxHr.map { Int($0.rounded()) },
                       walkingHr: d.walkingHr.map { Int($0.rounded()) },
                       weightKg: d.weightKg)
        }
        try await store.upsertAppleDaily(appleRows, deviceId: deviceId)

        // Recovery-relevant subset into dailyMetric (recovery/strain are nil — Apple doesn't compute them).
        let dm = daily.map { d in
            DailyMetric(day: d.day,
                        totalSleepMin: d.asleepMin, efficiency: nil,
                        deepMin: d.deepMin, remMin: d.remMin, lightMin: d.coreMin,
                        disturbances: nil,
                        restingHr: d.restingHr.map { Int($0.rounded()) },
                        avgHrv: d.hrvSDNN, recovery: nil, strain: nil, exerciseCount: nil,
                        spo2Pct: d.spo2Pct, skinTempDevC: nil, respRateBpm: d.respRate)
        }
        try await store.upsertDailyMetrics(dm, deviceId: deviceId)

        // Real Apple sleep intervals from export.xml. Daily aggregates are enough for long-range
        // trends, but sessions need actual stage windows so the Sleep screen can show honest bed/wake
        // timing for nights that came from Apple Watch.
        let sleepSessions = sleepSessions(from: result.sleepIntervals)
        try await store.upsertSleepSessions(sleepSessions, deviceId: deviceId)

        // Everything, generically, for the metric explorer.
        let points = AppleHealthAggregator.metricPoints(daily)
            .map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }
        try await store.upsertMetricSeries(points, deviceId: deviceId)

        // Workouts.
        let workouts = result.workouts.map { w in
            WorkoutRow(startTs: Int(w.start.timeIntervalSince1970),
                       endTs: Int(w.end.timeIntervalSince1970),
                       sport: w.activityType, source: WorkoutSource.appleHealthSource,
                       durationS: w.durationS, energyKcal: w.energyKcal,
                       avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: w.distanceM, zonesJSON: nil, notes: nil)
        }
        try await store.upsertWorkouts(workouts, deviceId: deviceId)

        return result.summary
    }

    private static func sleepSessions(from intervals: [SleepStageInterval]) -> [CachedSleepSession] {
        let sorted = intervals
            .filter { $0.stage != .unknown && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var groups: [[SleepStageInterval]] = []
        var current: [SleepStageInterval] = []
        var currentEnd: Date?
        let maxGap: TimeInterval = 3 * 60 * 60

        for interval in sorted {
            if let end = currentEnd, interval.start.timeIntervalSince(end) > maxGap, !current.isEmpty {
                groups.append(current)
                current = []
                currentEnd = nil
            }
            current.append(interval)
            currentEnd = max(currentEnd ?? interval.end, interval.end)
        }
        if !current.isEmpty { groups.append(current) }

        return groups.compactMap { group in
            let stageIntervals = group.filter { $0.stage != .inBed }
            let displayIntervals = stageIntervals.isEmpty ? group : stageIntervals
            let asleepSeconds = group.reduce(0.0) { sum, interval in
                isAsleep(interval.stage) ? sum + interval.end.timeIntervalSince(interval.start) : sum
            }
            guard asleepSeconds > 0,
                  let start = group.map(\.start).min(),
                  let end = group.map(\.end).max(),
                  end > start else { return nil }

            let totalSeconds = end.timeIntervalSince(start)
            let efficiency = totalSeconds > 0 ? asleepSeconds / totalSeconds : nil
            return CachedSleepSession(
                startTs: Int(start.timeIntervalSince1970),
                endTs: Int(end.timeIntervalSince1970),
                efficiency: efficiency,
                restingHr: nil,
                avgHrv: nil,
                stagesJSON: stagesJSON(from: displayIntervals),
                userEdited: false,
                startTsAdjusted: nil)
        }
    }

    private static func isAsleep(_ stage: SleepStage) -> Bool {
        switch stage {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        case .inBed, .awake, .unknown:
            return false
        }
    }

    private static func displayStage(_ stage: SleepStage) -> String {
        switch stage {
        case .asleepDeep: return "deep"
        case .asleepREM: return "rem"
        case .asleepCore, .asleepUnspecified: return "light"
        case .awake, .inBed, .unknown: return "wake"
        }
    }

    private static func stagesJSON(from intervals: [SleepStageInterval]) -> String? {
        let segments = intervals.compactMap { interval -> [String: Any]? in
            let start = Int(interval.start.timeIntervalSince1970)
            let end = Int(interval.end.timeIntervalSince1970)
            guard end > start else { return nil }
            return ["start": start, "end": end, "stage": displayStage(interval.stage)]
        }
        guard !segments.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: segments, options: []),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
