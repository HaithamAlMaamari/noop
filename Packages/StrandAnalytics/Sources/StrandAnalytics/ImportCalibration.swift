import Foundation

// ImportCalibration.swift — personal build: put imported WHOOP history on NOOP's own scale before it seeds
// the Charge baselines.
//
// THE PROBLEM. An imported WHOOP export seeds the HRV, resting-HR and respiration baselines so Charge can
// score from the first NOOP night. But the export's numbers come from WHOOP's methods, NOOP's from its own:
// NOOP's whole-night RMSSD has read roughly 1.5-2x WHOOP's HRV on the same wearer (v8.5.1 notes,
// docs/RR-OPTIMIZATION.md), and NOOP's resting HR sits several bpm away from WHOOP's. Pooled into one
// baseline, the first weeks of NOOP nights read far above "normal", so Charge sits inflated — and once the
// baseline is mature, its outlier rejection keeps refusing the NOOP nights, so the inflation lasts for
// weeks. The code carries this as a known gap (`IntelligenceEngine`, #459 "still unwired for the HRV and
// resting-HR baselines").
//
// THE RULE. Imported values enter a baseline only after they have been put on NOOP's scale, and the scale
// is measured, not assumed:
//   • HRV is compared as a RATIO (method differences in RMSSD scale multiplicatively),
//   • resting HR and respiration as an OFFSET (bpm / breaths-per-minute shifts).
// Preferred evidence is nights both sources measured (paired, median of the per-night ratio/difference).
// Without enough of those, the first NOOP nights are compared with the last imported nights before them —
// adjacent periods of the same person. Until NOOP has `minDeviceNights` of its own, there is no scale, and
// the imported history is left out of the baseline rather than pooled unscaled.
//
// PURE: day-keyed dictionaries in, a number out. No store, no clock.

public enum ImportCalibration {

    /// NOOP nights needed before a scale is trusted. Matches `Baselines.minNightsSeed`, so the calibrated
    /// import joins the baseline on the same night a NOOP-only baseline would first become usable.
    public static let minDeviceNights = Baselines.minNightsSeed
    /// Nights both sources measured that make a paired estimate.
    public static let minPairedNights = 4
    /// How many of the first NOOP nights, and of the last imported nights, the adjacent estimate uses.
    public static let deviceHead = 14
    public static let importTail = 30

    /// Sanity bands. A scale outside them means the two sources are not measuring the same thing (or the
    /// data is broken), so the import is left out rather than forced onto a nonsensical scale.
    public static let hrvRatioBand: ClosedRange<Double> = 0.33...3.0
    public static let restingHROffsetBand: ClosedRange<Double> = -25...25
    public static let respOffsetBand: ClosedRange<Double> = -6...6

    /// Multiply imported HRV by this to put it on NOOP's scale. Nil = no trusted scale (leave the import out).
    public static func hrvRatio(imported: [String: Double], device: [String: Double]) -> Double? {
        let imp = imported.filter { $0.value > 0 }
        let dev = device.filter { $0.value > 0 }
        guard let r = estimate(imported: imp, device: dev, combine: { d, i in d / i }, pooled: { d, i in d / i }) else {
            return nil
        }
        return hrvRatioBand.contains(r) ? r : nil
    }

    /// Add this to imported resting HR to put it on NOOP's scale. Nil = no trusted scale.
    public static func restingHROffset(imported: [String: Double], device: [String: Double]) -> Double? {
        offset(imported: imported, device: device, band: restingHROffsetBand)
    }

    /// Add this to imported respiration to put it on NOOP's scale. Nil = no trusted scale.
    public static func respOffset(imported: [String: Double], device: [String: Double]) -> Double? {
        offset(imported: imported, device: device, band: respOffsetBand)
    }

    static func offset(imported: [String: Double], device: [String: Double],
                       band: ClosedRange<Double>) -> Double? {
        let imp = imported.filter { $0.value > 0 }
        let dev = device.filter { $0.value > 0 }
        guard let o = estimate(imported: imp, device: dev, combine: { d, i in d - i }, pooled: { d, i in d - i }) else {
            return nil
        }
        return band.contains(o) ? o : nil
    }

    /// Paired when enough nights overlap, else adjacent periods; nil without `minDeviceNights` NOOP nights.
    static func estimate(imported: [String: Double], device: [String: Double],
                         combine: (Double, Double) -> Double,
                         pooled: (Double, Double) -> Double) -> Double? {
        guard device.count >= minDeviceNights, !imported.isEmpty else { return nil }
        let shared = device.keys.filter { imported[$0] != nil }.sorted()
        if shared.count >= minPairedNights {
            return median(shared.compactMap { day in
                guard let d = device[day], let i = imported[day] else { return nil }
                return combine(d, i)
            })
        }
        // Adjacent periods: the first NOOP nights against the imported nights just before them. "yyyy-MM-dd"
        // keys sort chronologically as strings.
        let deviceDays = device.keys.sorted()
        guard let firstDevice = deviceDays.first else { return nil }
        let head = deviceDays.prefix(deviceHead).compactMap { device[$0] }
        var before = imported.keys.filter { $0 <= firstDevice }.sorted()
        if before.isEmpty { before = imported.keys.sorted() }      // import after NOOP: use what exists
        let tail = before.suffix(importTail).compactMap { imported[$0] }
        guard let dm = median(Array(head)), let im = median(Array(tail)) else { return nil }
        return pooled(dm, im)
    }

    static func median(_ xs: [Double]) -> Double? {
        let s = xs.filter { $0.isFinite }.sorted()
        guard !s.isEmpty else { return nil }
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }
}
