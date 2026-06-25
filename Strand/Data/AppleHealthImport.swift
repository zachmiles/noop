import Foundation
import WhoopStore
import StrandImport

/// Maps a parsed + aggregated Apple Health export into the on-device store under its own
/// source id ("apple-health"), so it sits BESIDE Whoop for the per-source pages and cross-source
/// consensus. Populates appleDaily, dailyMetric, the generic metricSeries, and workouts.
nonisolated enum AppleHealthImport {
    struct Outcome {
        var summary: ImportSummary
        var profile: AppleHealthProfile?
    }

    enum ProgressEvent: Sendable {
        case cacheLookup
        case cacheHit(days: Int, records: Int)
        case cacheMiss
        case parsing(AppleHealthImporter.ParseProgress)
        case mapping
        case caching
        case writing(step: String, completed: Int?, total: Int?)
    }

    private static let cacheVersion = 4

    private struct CachePayload: Codable {
        var version: Int
        var fingerprint: String
        var summary: ImportSummary
        var profile: AppleHealthProfile?
        var appleRows: [AppleDaily]
        var dailyMetrics: [DailyMetric]
        var metricPoints: [MetricPoint]
        var sleepSessions: [CachedSleepSession]
        var workouts: [WorkoutRow]
    }

    @discardableResult
    static func importExport(url: URL, into store: WhoopStore, deviceId: String,
                             progress: (@Sendable (ProgressEvent) -> Void)? = nil) async throws -> Outcome {
        progress?(.cacheLookup)
        let fingerprint = try cacheFingerprint(for: url)
        if let cached = loadCache(fingerprint: fingerprint) {
            progress?(.cacheHit(days: cached.dailyMetrics.count, records: cached.summary.recordCount))
            try await write(cached, into: store, deviceId: deviceId, progress: progress)
            return Outcome(summary: cached.summary, profile: cached.profile)
        }
        progress?(.cacheMiss)

        // retainRawSamples:false — a multi-year export is millions of HealthSample
        // structs (hundreds of MB to >1 GB); iOS jetsam-kills the app if we hold
        // them all (issue #355). The importer folds them into per-day aggregates
        // incrementally and drops the raw array; `aggregate` consumes the
        // pre-folded `sampleDailies`.
        let result = try ImportCoordinator().importAppleHealth(from: url, retainRawSamples: false) { snapshot in
            progress?(.parsing(snapshot))
        }
        progress?(.mapping)
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

        // Real Apple sleep intervals from export.xml. Daily aggregates are enough for long-range
        // trends, but sessions need actual stage windows so the Sleep screen can show honest bed/wake
        // timing for nights that came from Apple Watch.
        let sleepSessions = sleepSessions(from: result.sleepIntervals)

        // Everything, generically, for the metric explorer.
        let points = AppleHealthAggregator.metricPoints(daily)
            .map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }

        // Workouts.
        let workouts = result.workouts.map { w in
            WorkoutRow(startTs: Int(w.start.timeIntervalSince1970),
                       endTs: Int(w.end.timeIntervalSince1970),
                       sport: w.activityType, source: WorkoutSource.appleHealthSource,
                       durationS: w.durationS, energyKcal: w.energyKcal,
                       avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: w.distanceM, zonesJSON: nil, notes: nil)
        }

        let payload = CachePayload(version: cacheVersion, fingerprint: fingerprint, summary: result.summary,
                                   profile: result.profile,
                                   appleRows: appleRows, dailyMetrics: dm, metricPoints: points,
                                   sleepSessions: sleepSessions, workouts: workouts)
        progress?(.caching)
        saveCache(payload)
        try await write(payload, into: store, deviceId: deviceId, progress: progress)
        return Outcome(summary: payload.summary, profile: payload.profile)
    }

    private static func write(_ payload: CachePayload, into store: WhoopStore, deviceId: String,
                              progress: (@Sendable (ProgressEvent) -> Void)?) async throws {
        progress?(.writing(step: "Writing daily Apple Health rows", completed: 0, total: 5))
        try await store.upsertAppleDaily(payload.appleRows, deviceId: deviceId)
        progress?(.writing(step: "Writing sleep and health summaries", completed: 1, total: 5))
        try await store.upsertDailyMetrics(payload.dailyMetrics, deviceId: deviceId)
        progress?(.writing(step: "Writing Apple sleep sessions", completed: 2, total: 5))
        try await store.upsertSleepSessions(payload.sleepSessions, deviceId: deviceId)
        progress?(.writing(step: "Writing metric explorer series", completed: 3, total: 5))
        try await store.upsertMetricSeries(payload.metricPoints, deviceId: deviceId)
        progress?(.writing(step: "Writing Apple workouts", completed: 4, total: 5))
        try await store.upsertWorkouts(payload.workouts, deviceId: deviceId)
        progress?(.writing(step: "Import rows written", completed: 5, total: 5))
    }

    private static func loadCache(fingerprint: String) -> CachePayload? {
        let url = cacheURL(fingerprint: fingerprint)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
              payload.version == cacheVersion,
              payload.fingerprint == fingerprint else { return nil }
        return payload
    }

    private static func saveCache(_ payload: CachePayload) {
        let url = cacheURL(fingerprint: payload.fingerprint)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            try encoder.encode(payload).write(to: url, options: [.atomic])
        } catch {
            NSLog("AppleHealthImport cache save failed: \(error)")
        }
    }

    private static func cacheURL(fingerprint: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("noop-apple-health-import-cache", isDirectory: true)
            .appendingPathComponent("v\(cacheVersion)", isDirectory: true)
            .appendingPathComponent("\(fingerprint).json")
    }

    private static func cacheFingerprint(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values.isDirectory == true {
            return "dir-\(url.path.hashValue)"
        }
        let size = values.fileSize ?? 0
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        func mix(_ string: String) {
            for byte in string.utf8 { mix(byte) }
        }
        mix("noop-apple-health-cache-v\(cacheVersion)-\(size)")

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let sampleSize = 1 << 20
        let head = try handle.read(upToCount: min(sampleSize, size)) ?? Data()
        for byte in head { mix(byte) }
        if size > sampleSize {
            try handle.seek(toOffset: UInt64(max(0, size - sampleSize)))
            let tail = try handle.read(upToCount: sampleSize) ?? Data()
            for byte in tail { mix(byte) }
        }
        return String(format: "%016llx-%lld", hash, Int64(size))
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
