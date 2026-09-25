import XCTest
import WhoopStore
@testable import StrandImport

/// Personal build: sets, reps, rest and effort written the way lifters actually write them.
final class LiftProgramNotationTests: XCTestCase {

    private func parse(_ csv: String) throws -> LiftProgramImportResult {
        try LiftProgramSheetImporter.parse(data: Data(csv.utf8))
    }

    func testRepRangesKeepBothEnds() throws {
        let r = try parse("Exercise,Sets,Reps\nBench press,4,8-10\nRow,3,12–15\nCurl,3,10 to 12\nDips,3,10+\n")
        let lines = r.programs[0].lines
        XCTAssertEqual(lines[0].targetReps, 8); XCTAssertEqual(lines[0].targetRepsHigh, 10)
        XCTAssertEqual(lines[1].targetReps, 12); XCTAssertEqual(lines[1].targetRepsHigh, 15)
        XCTAssertEqual(lines[2].targetReps, 10); XCTAssertEqual(lines[2].targetRepsHigh, 12)
        XCTAssertEqual(lines[3].targetReps, 10); XCTAssertNil(lines[3].targetRepsHigh)
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
    }

    func testSetsByRepsInEitherColumn() throws {
        let r = try parse("Exercise,Sets,Reps\nSquat,5x5,\nPress,,3 x 8-10\nPulldown,4,3×12\n")
        let l = r.programs[0].lines
        XCTAssertEqual(l[0].targetSets, 5); XCTAssertEqual(l[0].targetReps, 5); XCTAssertNil(l[0].targetRepsHigh)
        XCTAssertEqual(l[1].targetSets, 3); XCTAssertEqual(l[1].targetReps, 8); XCTAssertEqual(l[1].targetRepsHigh, 10)
        // An explicit Sets cell wins over the sets written in the Reps cell.
        XCTAssertEqual(l[2].targetSets, 4); XCTAssertEqual(l[2].targetReps, 12)
    }

    func testRestFormats() throws {
        let r = try parse("Exercise,Rest sec\nA,90\nB,1:30\nC,2 min\nD,90s\nE,1.5 min\nF,3\nG,2'30\n")
        XCTAssertEqual(r.programs[0].lines.map(\.restSec), [90, 90, 120, 90, 90, 180, 150])
        XCTAssertEqual(r.warnings.count, 1, "only the bare '3' is a guess worth reporting: \(r.warnings)")
        XCTAssertTrue(r.warnings[0].hasPrefix("Row 7:"))
    }

    /// Ranges keep their lower bound (the shortest rest the plan allows), and minutes-plus-seconds written
    /// out in words or letters add up, instead of being read digit by digit.
    func testRestRangesAndCompoundTimes() {
        func rest(_ raw: String) -> Int? { LiftProgramSheetImporter.restSeconds(raw)?.seconds }
        XCTAssertEqual(rest("2-3 min"), 120)
        XCTAssertEqual(rest("2 to 3 min"), 120)
        XCTAssertEqual(rest("3-2 min"), 120)
        XCTAssertEqual(rest("60-90s"), 60)
        XCTAssertEqual(rest("90s-2min"), 90)
        XCTAssertEqual(rest("90 sec - 2 min"), 90)
        XCTAssertEqual(rest("1-1.5 min"), 60)
        XCTAssertEqual(rest("2-3'"), 120)
        XCTAssertEqual(rest("1m30s"), 90)
        XCTAssertEqual(rest("1 min 30 sec"), 90)
        XCTAssertEqual(rest("2m 30"), 150)
        XCTAssertEqual(rest("1,5 min"), 90)
        XCTAssertEqual(rest("2 minutes"), 120)
        XCTAssertEqual(rest("90\""), 90)
        XCTAssertEqual(rest("1:30:00"), 90, "a time of day the spreadsheet made out of 1:30")
        XCTAssertEqual(rest("Rest 90"), 90)
        XCTAssertNil(rest("as needed"))
        // A bare range is still a guess when it is small, and is reported like a bare "3".
        XCTAssertEqual(LiftProgramSheetImporter.restSeconds("2-3")?.seconds, 120)
        XCTAssertEqual(LiftProgramSheetImporter.restSeconds("2-3")?.readAsMinutes, true)
        XCTAssertEqual(LiftProgramSheetImporter.restSeconds("60-90")?.seconds, 60)
        XCTAssertEqual(LiftProgramSheetImporter.restSeconds("60-90")?.readAsMinutes, false)
    }

    func testRestRangeInASheetNeedsNoWarning() throws {
        let r = try parse("Exercise,Rest\nSquat,2-3 min\nRow,1m30s\nCurl,2-3\n")
        XCTAssertEqual(r.programs[0].lines.map(\.restSec), [120, 90, 120])
        XCTAssertEqual(r.warnings.count, 1, "only the unit-less '2-3' is a guess: \(r.warnings)")
    }

    func testRpeRangeIsItsCeilingAndRirFillsIn() throws {
        let r = try parse("Exercise,RPE,RIR\nSquat,7-8,\nBench,,2\nRow,,1-2\nCurl,9,3\n")
        XCTAssertEqual(r.programs[0].lines.map(\.targetMaxRpe), [8, 8, 9, 9],
                       "an explicit RPE wins over RIR; RIR 1-2 caps at the harder end")
    }

    func testImplausibleValuesAreDroppedWithAWarning() throws {
        let r = try parse("Exercise,Sets,Reps,Weight kg,Rest sec\nSquat,40,46244,5000,7200\n")
        let l = r.programs[0].lines[0]
        XCTAssertNil(l.targetSets)
        XCTAssertNil(l.targetReps)
        XCTAssertNil(l.targetWeightKg)
        XCTAssertNil(l.restSec)
        XCTAssertEqual(r.warnings.count, 4, "\(r.warnings)")
        XCTAssertTrue(r.warnings.contains { $0.contains("date") }, "a date serial in Reps is named as such")
    }

    func testPlainTemplateValuesAreUnchanged() throws {
        let r = try parse("Exercise,Sets,Reps,Weight kg,Rest sec\nLeg press,3,10,\"40,5 kg\",60\n")
        let l = r.programs[0].lines[0]
        XCTAssertEqual(l.targetSets, 3)
        XCTAssertEqual(l.targetReps, 10)
        XCTAssertNil(l.targetRepsHigh)
        XCTAssertEqual(l.targetWeightKg, 40.5)
        XCTAssertEqual(l.restSec, 60)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    /// The push/pull template shipped with the personal build imports cleanly: four programs, rep ranges
    /// written "6 to 8" (Excel cannot turn that into a date), no warnings.
    func testPushPullTemplateImports() throws {
        let csv = """
Program,Program note,Exercise,Primary muscle,Secondary muscles,Sets,Reps,Weight kg,Rest sec,Target max RPE,Note
Push A,Heavy press day,Barbell Bench Press,Chest,"Front delts, Triceps",4,6 to 8,,180,8,"Shoulder blades pinned, 1 s pause on the chest"
Push A,,Seated DB Shoulder Press,Front delts,"Side delts, Triceps",3,8 to 10,,120,8,
Push A,,Incline DB Press,Chest,"Front delts, Triceps",3,8 to 12,,120,8,30° bench
Push A,,Cable Lateral Raise,Side delts,,3,12 to 15,,60,9,
Push A,,Triceps Rope Pushdown,Triceps,,3,10 to 12,,60,9,
Push A,,Overhead Cable Triceps Extension,Triceps,,2,12 to 15,,60,9,
Pull A,Heavy pull day,Weighted Pull-up,Lats,"Biceps, Upper back",4,6 to 8,,180,8,Weight = added load only
Pull A,,Chest-Supported Row,Upper back,"Lats, Rear delts, Biceps",3,8 to 10,,120,8,
Pull A,,Seated Cable Row,Upper back,"Lats, Biceps",3,10 to 12,,90,8,
Pull A,,Face Pull,Rear delts,"Upper back, Traps",3,12 to 15,,60,9,
Pull A,,EZ-Bar Curl,Biceps,Forearms,3,8 to 10,,90,9,
Pull A,,Hammer Curl,Biceps,Forearms,2,10 to 12,,60,9,
Push B,Volume press day,Incline Barbell Press,Chest,"Front delts, Triceps",4,8 to 10,,150,8,
Push B,,Machine Chest Press,Chest,"Front delts, Triceps",3,10 to 12,,90,9,
Push B,,DB Lateral Raise,Side delts,,4,12 to 15,,60,9,
Push B,,Cable Fly,Chest,Front delts,3,12 to 15,,60,9,
Push B,,Skull Crusher,Triceps,,3,10 to 12,,90,9,
Pull B,Volume pull day,Lat Pulldown,Lats,"Biceps, Upper back",4,8 to 10,,120,8,
Pull B,,One-Arm DB Row,Lats,"Upper back, Biceps",3,8 to 12,,90,8,
Pull B,,Reverse Pec Deck,Rear delts,Upper back,3,12 to 15,,60,9,
Pull B,,Straight-Arm Pulldown,Lats,,3,12 to 15,,60,9,
Pull B,,Incline DB Curl,Biceps,,3,10 to 12,,60,9,
"""
        let r = try parse(csv)
        XCTAssertEqual(r.programs.map(\.name), ["Push A", "Pull A", "Push B", "Pull B"])
        XCTAssertTrue(r.warnings.isEmpty, "\(r.warnings)")
        let bench = r.programs[0].lines[0]
        XCTAssertEqual(bench.exercise, "Barbell Bench Press")
        XCTAssertEqual(bench.targetSets, 4)
        XCTAssertEqual(bench.targetReps, 6)
        XCTAssertEqual(bench.targetRepsHigh, 8)
        XCTAssertEqual(bench.targetMaxRpe, 8)
        XCTAssertEqual(bench.restSec, 180)
        XCTAssertNil(bench.targetWeightKg)
        XCTAssertEqual(bench.primaryMuscle, .chest)
        XCTAssertEqual(bench.secondaryMuscles, [.frontDelts, .triceps])
        XCTAssertEqual(r.programs[1].lines.first?.secondaryMuscles, [.biceps, .upperBack])
    }

    func testPureHelpers() {
        XCTAssertEqual(LiftProgramSheetImporter.integerTokens("3 x 8-10"), [3, 8, 10])
        XCTAssertNil(LiftProgramSheetImporter.setsByReps("10 max"))
        XCTAssertNil(LiftProgramSheetImporter.repRange("AMRAP"))
        XCTAssertEqual(LiftProgramSheetImporter.restSeconds("45 sec")?.seconds, 45)
        XCTAssertEqual(LiftProgramSheetImporter.rpeCeiling("8,5"), 8.5)
        XCTAssertEqual(LiftProgramSheetImporter.rirFloor("2-3"), 2)
    }
}
