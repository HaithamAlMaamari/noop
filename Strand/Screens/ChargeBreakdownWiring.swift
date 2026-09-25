import Foundation
import StrandAnalytics
import WhoopStore

// MARK: - Charge breakdown wiring (pure, testable)
//
// The fold-and-score wiring behind the "What shaped it" sheet, lifted out of the two views that had
// byte-identical private copies of it (TodayView.chargeBreakdown / CoupledView.chargeBreakdown). They
// differed only in which row they display and where their sleep-performance number comes from, both of
// which are inputs, so one function serves both.
//
// Extracted so it can be TESTED. Living inside a `View` struct as a private method meant the only way to
// exercise it was to render the view, so the iOS side of this path had no test at all while the Android
// twin did. Kotlin twin: `TodayScoring.recoveryChargeDrivers`.
//
// Pure: no SwiftUI state, no I/O, no store access. Nothing here invents a number. The drivers come from
// `RecoveryScorer.chargeDrivers` and the tier is SURFACED from `ScoreConfidence.charge` against the same
// folded HRV baseline the drivers scored with, so the header and the rows agree by construction.
enum ChargeBreakdownWiring {

    /// The ordered Charge driver rows for `row` plus its confidence tier, folded from the visible `days`
    /// history, or nil when the night cannot honestly score (missing HRV or resting HR, or an HRV
    /// baseline that is not yet usable) so the sheet hides rather than showing fabricated rows.
    ///
    /// `sleepPerfPercent` is the Rest composite on a 0-100 scale, divided by 100 here to match
    /// `AnalyticsEngine`'s `sleepPerf` form, so the Sleep row scores against the headline's own input.
    ///
    /// The resting-HR and respiration baselines are passed only when usable. `RecoveryScorer` and
    /// `chargeDrivers` both apply that gate themselves since #1990, so these are belt-and-braces rather
    /// than load-bearing; they are kept because they say the intent at the call site, which is where a
    /// reader looks first.
    ///
    /// Personal build: with `sourced` rows that include a WHOOP import and the scales the last re-score
    /// recorded (`calibration`), the baselines fold the SAME per-day series the engine scored the headline
    /// against (`ImportCalibration.calibratedHistory`): the import on NOOP's scale, NOOP's own nights taking
    /// their day. Folding the merged `days` as they are would pool WHOOP-scale HRV with NOOP's (~1.5-2x) and
    /// explain a Charge the headline never scored. A row whose value the merge took from the import is put
    /// on the same scale before it is compared. Without an import or a recorded calibration, `days` fold
    /// exactly as before.
    static func breakdown(days: [DailyMetric],
                          row: DailyMetric,
                          sleepPerfPercent: Double?,
                          hrvBaselineEpoch: Double = 0,
                          sourced: [SourcedDailyMetric] = [],
                          calibration: ImportCalibrationRecord? = nil) -> (drivers: [ChargeDriver], confidence: ScoreConfidence)? {
        guard row.avgHrv != nil, row.restingHr != nil else { return nil }
        let inputs = baselineInputs(days: days, row: row, sourced: sourced, calibration: calibration)
        guard let hrv = inputs.rowHrv, let rhr = inputs.rowRhr else { return nil }
        // PERF: one pass per series. The two private copies this replaces each re-folded the full history
        // per body evaluation of the open sheet; the guard above still runs before any fold.
        // #2315: fold with the recalibration epoch, exactly as the engine does. Without it these rows and
        // the confidence tier scored against the WHOLE history while the headline scored against the
        // post-Recalibrate nights, so the Charge page showed two baselines for one metric. `0` (no
        // recalibration) delegates to the plain fold, so a user who never recalibrated sees no change.
        let hrvBase = Baselines.foldHistory(inputs.hrv, dayKeys: inputs.hrvDays,
                                            cfg: Baselines.hrvCfg, baselineEpoch: hrvBaselineEpoch)
        guard hrvBase.usable else { return nil }
        let rhrBase = Baselines.foldHistory(inputs.rhr, cfg: Baselines.restingHRCfg)
        let respBase = Baselines.foldHistory(inputs.resp, cfg: Baselines.respCfg)
        let drivers = RecoveryScorer.chargeDrivers(
            hrv: hrv, rhr: rhr, resp: inputs.rowResp,
            hrvBaseline: hrvBase,
            rhrBaseline: rhrBase.usable ? rhrBase : nil,
            respBaseline: respBase.usable ? respBase : nil,
            sleepPerf: sleepPerfPercent.map { $0 / 100.0 },
            skinTempDev: row.skinTempDevC)
        return (drivers, ScoreConfidence.charge(recovery: row.recovery, hrvBaseline: hrvBase))
    }

    /// The baseline series (oldest first) and the row's own values, on one scale. See `breakdown`.
    struct BaselineInputs {
        var hrvDays: [String]
        var hrv: [Double?]
        var rhr: [Double?]
        var resp: [Double?]
        var rowHrv: Double?
        var rowRhr: Double?
        var rowResp: Double?
    }

    static func baselineInputs(days: [DailyMetric], row: DailyMetric, sourced: [SourcedDailyMetric],
                               calibration: ImportCalibrationRecord?) -> BaselineInputs {
        let rowRhr = row.restingHr.map(Double.init)
        guard let cal = calibration, sourced.contains(where: { $0.source == .whoopImport }) else {
            return BaselineInputs(hrvDays: days.map(\.day), hrv: days.map(\.avgHrv),
                                  rhr: days.map { $0.restingHr.map(Double.init) }, resp: days.map(\.respRateBpm),
                                  rowHrv: row.avgHrv, rowRhr: rowRhr, rowResp: row.respRateBpm)
        }
        var imported: [String: DailyMetric] = [:]
        var device: [String: DailyMetric] = [:]
        for r in sourced {
            switch r.source {
            case .whoopImport: imported[r.metric.day] = r.metric
            case .noopComputed: device[r.metric.day] = r.metric
            case .appleHealth, .localCache: break
            }
        }
        func history(_ value: (DailyMetric) -> Double?, _ calibrate: ((Double) -> Double)?) -> [String: Double?] {
            var imp: [String: Double?] = [:]
            var dev: [String: Double?] = [:]
            for (day, m) in imported { imp[day] = value(m) }
            for (day, m) in device { dev[day] = value(m) }
            return ImportCalibration.calibratedHistory(imported: imp, device: dev, calibrate: calibrate)
        }
        let hrvScale = ImportCalibration.scaling(cal.hrvRatio)
        let rhrShift = ImportCalibration.shifting(cal.restingHROffset)
        let respShift = ImportCalibration.shifting(cal.respOffset)
        let hrvByDay = history({ $0.avgHrv }, hrvScale)
        let rhrByDay = history({ $0.restingHr.map(Double.init) }, rhrShift)
        let respByDay = history({ $0.respRateBpm }, respShift)
        let hrvDays = hrvByDay.keys.sorted()
        // The merge takes a day's value from the import whenever the import has one; such a value is
        // WHOOP's, so it is compared on NOOP's scale like the history around it.
        func own(_ merged: Double?, _ value: (DailyMetric) -> Double?, _ calibrate: ((Double) -> Double)?) -> Double? {
            guard let merged, let imp = imported[row.day], let v = value(imp), v == merged else { return merged }
            return calibrate?(v) ?? merged
        }
        return BaselineInputs(
            hrvDays: hrvDays,
            hrv: hrvDays.map { hrvByDay[$0]! },                  // keys from the map itself
            rhr: rhrByDay.keys.sorted().map { rhrByDay[$0]! },
            resp: respByDay.keys.sorted().map { respByDay[$0]! },
            rowHrv: own(row.avgHrv, { $0.avgHrv }, hrvScale),
            rowRhr: own(rowRhr, { $0.restingHr.map(Double.init) }, rhrShift),
            rowResp: own(row.respRateBpm, { $0.respRateBpm }, respShift))
    }
}
