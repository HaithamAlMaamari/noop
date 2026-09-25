import XCTest
@testable import StrandAnalytics

/// Personal build: imported WHOOP history is put on NOOP's scale before it seeds Charge.
final class ImportCalibrationTests: XCTestCase {

    /// "2026-09-01" + n days.
    private func day(_ n: Int) -> String {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 1
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let d = cal.date(byAdding: .day, value: n, to: cal.date(from: c)!)!
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func series(_ range: Range<Int>, _ value: (Int) -> Double) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: range.map { (day($0), value($0)) })
    }

    func testNoScaleUntilNoopHasEnoughNights() {
        let imported = series(0..<30) { _ in 50 }
        XCTAssertNil(ImportCalibration.hrvRatio(imported: imported, device: series(30..<33) { _ in 90 }))
        XCTAssertNotNil(ImportCalibration.hrvRatio(imported: imported, device: series(30..<34) { _ in 90 }))
    }

    func testAdjacentPeriodsGiveTheMethodRatio() {
        // WHOOP read ~50 ms for a month; NOOP's first nights read ~90 ms on the same wearer.
        let imported = series(0..<60) { i in i % 2 == 0 ? 48 : 52 }
        let device = series(60..<70) { i in i % 2 == 0 ? 88 : 92 }
        let r = ImportCalibration.hrvRatio(imported: imported, device: device)
        XCTAssertEqual(r ?? 0, 90.0 / 50.0, accuracy: 0.001)
    }

    func testPairedNightsWinWhenBothSourcesMeasured() {
        // Overlap nights: NOOP reads exactly 1.6x; the adjacent medians would say something else.
        let imported = series(0..<20) { i in 40 + Double(i) }
        var device = series(15..<20) { i in (40 + Double(i)) * 1.6 }
        device.merge(series(20..<30) { _ in 200 }) { a, _ in a }
        XCTAssertEqual(ImportCalibration.hrvRatio(imported: imported, device: device) ?? 0, 1.6, accuracy: 0.0001)
    }

    func testRestingHROffset() {
        let imported = series(0..<30) { _ in 52 }
        let device = series(30..<40) { _ in 58 }
        XCTAssertEqual(ImportCalibration.restingHROffset(imported: imported, device: device) ?? 0, 6, accuracy: 0.0001)
    }

    func testImplausibleScalesAreRefused() {
        let imported = series(0..<30) { _ in 20 }
        XCTAssertNil(ImportCalibration.hrvRatio(imported: imported, device: series(30..<40) { _ in 200 }),
                     "a 10x ratio is not a method difference")
        XCTAssertNil(ImportCalibration.restingHROffset(imported: series(0..<30) { _ in 40 },
                                                       device: series(30..<40) { _ in 90 }))
    }

    func testEmptyImportGivesNoScale() {
        XCTAssertNil(ImportCalibration.hrvRatio(imported: [:], device: series(0..<10) { _ in 60 }))
    }

    /// The value stored for `day` (nil for an empty slot or a missing day; the key lists tell those apart).
    private func slot(_ history: [String: Double?], _ day: String) -> Double? { history[day] ?? nil }

    func testCalibratedHistoryScalesTheImportAndLetsNoopWin() {
        let imported: [String: Double?] = ["2026-09-01": 50, "2026-09-02": nil, "2026-09-03": 60]
        let device: [String: Double?] = ["2026-09-03": 100, "2026-09-04": 95, "2026-09-05": nil]
        let out = ImportCalibration.calibratedHistory(imported: imported, device: device,
                                                      calibrate: ImportCalibration.scaling(1.8))
        XCTAssertEqual(out.keys.sorted(), ["2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"])
        XCTAssertEqual(slot(out, "2026-09-01"), 90, "imported value on NOOP's scale")
        XCTAssertNil(slot(out, "2026-09-02"), "an imported night without a value stays a gap")
        XCTAssertEqual(slot(out, "2026-09-03"), 100, "NOOP's own value takes its day")
        XCTAssertEqual(slot(out, "2026-09-04"), 95)
        XCTAssertNil(slot(out, "2026-09-05"))
    }

    func testCalibratedHistoryWithoutAScaleLeavesTheImportOut() {
        let imported: [String: Double?] = ["2026-09-01": 52, "2026-09-02": 54]
        let device: [String: Double?] = ["2026-09-03": 58]
        let out = ImportCalibration.calibratedHistory(imported: imported, device: device, calibrate: nil)
        XCTAssertEqual(out.keys.sorted(), ["2026-09-03"])
        let shifted = ImportCalibration.calibratedHistory(imported: imported, device: device,
                                                          calibrate: ImportCalibration.shifting(6))
        XCTAssertEqual(slot(shifted, "2026-09-01"), 58)
        XCTAssertNil(ImportCalibration.scaling(nil))
        XCTAssertNil(ImportCalibration.shifting(nil))
    }

    func testMedian() {
        XCTAssertEqual(ImportCalibration.median([3, 1, 2]), 2)
        XCTAssertEqual(ImportCalibration.median([4, 1, 2, 3]), 2.5)
        XCTAssertNil(ImportCalibration.median([]))
    }
}
