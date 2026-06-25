import XCTest
import WhoopStore
@testable import Strand

final class WorkoutRowIdentityTests: XCTestCase {
    func testStableListIDDoesNotDependOnArrayOffset() {
        let running = WorkoutRow(
            startTs: 1_780_000_000,
            endTs: 1_780_003_600,
            sport: "Running",
            source: "apple-health",
            durationS: 3_600,
            energyKcal: 640,
            avgHr: 148,
            maxHr: 176,
            strain: nil,
            distanceM: 10_000,
            zonesJSON: nil,
            notes: nil)
        let cycling = WorkoutRow(
            startTs: 1_780_010_000,
            endTs: 1_780_013_000,
            sport: "Cycling",
            source: "manual",
            durationS: 3_000,
            energyKcal: nil,
            avgHr: nil,
            maxHr: nil,
            strain: nil,
            distanceM: 18_000,
            zonesJSON: nil,
            notes: nil)

        let firstOrder = [running, cycling].map(\.stableListID)
        let secondOrder = [cycling, running].map(\.stableListID)

        XCTAssertEqual(firstOrder[0], secondOrder[1])
        XCTAssertEqual(firstOrder[1], secondOrder[0])
        XCTAssertNotEqual(firstOrder[0], firstOrder[1])
    }
}
