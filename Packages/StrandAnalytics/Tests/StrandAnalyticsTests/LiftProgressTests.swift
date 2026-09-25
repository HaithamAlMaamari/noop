import XCTest
import WhoopStore
@testable import StrandAnalytics

/// Personal build: double progression, estimated-1RM records and push/pull balance.
final class LiftProgressTests: XCTestCase {

    private func set(_ index: Int, _ kg: Double?, _ reps: Int?, exercise: String = "Bench press",
                     rpe: Double? = nil, warmup: Bool = false,
                     muscle: LiftMuscle? = .chest) -> LiftSetRow {
        LiftSetRow(id: UUID().uuidString, deviceId: "d", sessionId: "s", ord: index,
                   exercise: exercise, primaryMuscle: muscle, setIndex: index,
                   weightKg: kg, reps: reps, rpe: rpe, isWarmup: warmup,
                   startTs: nil, endTs: nil, restSec: nil, note: nil)
    }

    // MARK: Double progression

    func testEverySetAtTheTopOfTheRangeAddsWeight() {
        let last = [set(0, 40, 10, warmup: true), set(1, 80, 10), set(2, 80, 10), set(3, 80, 10)]
        let s = LiftProgress.suggestion(lastSets: last, repsLow: 8, repsHigh: 10, maxRpe: 9, primaryMuscle: .chest)
        XCTAssertEqual(s?.kind, .addWeight)
        XCTAssertEqual(s?.weightKg, 82.5)
        XCTAssertEqual(s?.repsLow, 8)
        XCTAssertEqual(s?.lastReps, [10, 10, 10], "warm-ups never decide it")
    }

    func testLowerBodyAddsFive() {
        let last = [set(1, 100, 5, exercise: "Squat", muscle: .quads),
                    set(2, 100, 5, exercise: "Squat", muscle: .quads)]
        let s = LiftProgress.suggestion(lastSets: last, repsLow: 5, repsHigh: nil, maxRpe: nil, primaryMuscle: .quads)
        XCTAssertEqual(s?.kind, .addWeight)
        XCTAssertEqual(s?.weightKg, 105)
    }

    func testInsideTheRangeAddsReps() {
        let last = [set(1, 80, 10), set(2, 80, 9), set(3, 80, 8)]
        let s = LiftProgress.suggestion(lastSets: last, repsLow: 8, repsHigh: 10, maxRpe: nil, primaryMuscle: .chest)
        XCTAssertEqual(s?.kind, .addReps)
        XCTAssertEqual(s?.weightKg, 80)
    }

    func testAboveTheMaxRpeHolds() {
        let last = [set(1, 80, 10, rpe: 9.5), set(2, 80, 10, rpe: 10)]
        let s = LiftProgress.suggestion(lastSets: last, repsLow: 8, repsHigh: 10, maxRpe: 9, primaryMuscle: .chest)
        XCTAssertEqual(s?.kind, .hold)
        XCTAssertEqual(s?.weightKg, 80)
    }

    func testShortOfTheRangeHolds() {
        let last = [set(1, 80, 8), set(2, 80, 6)]
        let s = LiftProgress.suggestion(lastSets: last, repsLow: 8, repsHigh: 10, maxRpe: nil, primaryMuscle: .chest)
        XCTAssertEqual(s?.kind, .hold)
    }

    func testBackOffSetsDoNotDecide() {
        // Top sets all hit 6; the lighter back-off set (85 kg x 4) is ignored.
        let last = [set(1, 100, 6), set(2, 100, 6), set(3, 85, 4)]
        let s = LiftProgress.suggestion(lastSets: last, repsLow: 4, repsHigh: 6, maxRpe: nil, primaryMuscle: .chest)
        XCTAssertEqual(s?.kind, .addWeight)
        XCTAssertEqual(s?.lastWeightKg, 100)
        XCTAssertEqual(s?.lastReps, [6, 6])
    }

    func testNothingToReasonFrom() {
        XCTAssertNil(LiftProgress.suggestion(lastSets: [], repsLow: 8, repsHigh: 10, maxRpe: nil, primaryMuscle: nil))
        XCTAssertNil(LiftProgress.suggestion(lastSets: [set(1, 80, 10)], repsLow: nil, repsHigh: nil, maxRpe: nil, primaryMuscle: nil),
                     "no rep target, no rule")
        XCTAssertNil(LiftProgress.suggestion(lastSets: [set(1, nil, 10), set(2, 80, 0)], repsLow: 8, repsHigh: 10, maxRpe: nil, primaryMuscle: nil),
                     "a set without a weight, and a skipped (0-rep) set, give nothing to go on")
    }

    // MARK: Records

    func testProgressFindsRecordsAndFourWeekChange() {
        let day = 86_400
        var sessions: [(startTs: Int, sets: [LiftSetRow])] = []
        sessions.append((startTs: 0, sets: [set(1, 80, 8)]))                 // 101.33
        sessions.append((startTs: 10 * day, sets: [set(1, 82.5, 8)]))        // 104.5
        let row = set(1, 70, 10, exercise: "Row", muscle: .upperBack)
        sessions.append((startTs: 40 * day, sets: [set(1, 85, 8), row]))     // 107.67 — record
        let p = LiftProgress.progress(sessions: sessions)
        let bench = p.first { $0.exercise == "Bench press" }
        XCTAssertEqual(bench?.points.count, 3)
        XCTAssertEqual(bench?.latestIsRecord, true)
        XCTAssertEqual(bench?.bestTs, 40 * day)
        let epleyFactor: Double = 1.0 + 8.0 / 30.0
        let expectedChange: Double = (85.0 - 82.5) * epleyFactor
        let change: Double = bench?.changeOver4WeeksKg ?? 0
        XCTAssertEqual(change, expectedChange, accuracy: 0.001)
        let rowProgress = p.first { $0.exercise == "Row" }
        XCTAssertEqual(rowProgress?.latestIsRecord, false, "a first session is not a record against nothing")
        XCTAssertNil(rowProgress?.changeOver4WeeksKg)
    }

    func testHighRepSetsDoNotEstimate() {
        let only: [(startTs: Int, sets: [LiftSetRow])] = [(startTs: 0, sets: [set(1, 20, 20)])]
        let p = LiftProgress.progress(sessions: only)
        XCTAssertTrue(p.isEmpty, "over the 12-rep ceiling there is no estimate to trend")
    }

    // MARK: Balance

    func testRearDeltsCountAsPull() {
        let b = LiftProgress.balance([.chest: 10, .triceps: 3, .lats: 8, .rearDelts: 4, .quads: 6, .abs: 2])
        XCTAssertEqual(b.push, 13)
        XCTAssertEqual(b.pull, 12)
        XCTAssertEqual(b.legs, 6)
        XCTAssertEqual(b.trunk, 2)
        XCTAssertEqual(b.pullPerPush ?? 0, 12.0 / 13.0, accuracy: 0.0001)
        XCTAssertNil(LiftProgress.balance([.chest: 5]).pullPerPush)
    }
}
