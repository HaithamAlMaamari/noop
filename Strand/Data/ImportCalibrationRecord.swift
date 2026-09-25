import Foundation

/// Personal build: the import-calibration scales the last Charge re-score used (`IntelligenceEngine`,
/// `ImportCalibration`), kept so the "What shaped it" sheet (`ChargeBreakdownWiring`) folds its baselines
/// on the same scale as the headline it explains, instead of measuring a scale of its own from whatever
/// window of rows the screen happens to hold. Derived state only: the next re-score rewrites it, and it is
/// deliberately not part of the `.noopbak` settings whitelist.
struct ImportCalibrationRecord: Equatable {
    var hrvRatio: Double?
    var restingHROffset: Double?
    var respOffset: Double?

    private static let recordedKey = "noop.personal.importCalibration.recorded"
    private static let hrvKey = "noop.personal.importCalibration.hrvRatio"
    private static let rhrKey = "noop.personal.importCalibration.rhrOffset"
    private static let respKey = "noop.personal.importCalibration.respOffset"

    /// The scales the last re-score recorded, or nil before any has (the sheet then folds as upstream does).
    static func load(_ defaults: UserDefaults = .standard) -> ImportCalibrationRecord? {
        guard defaults.bool(forKey: recordedKey) else { return nil }
        return ImportCalibrationRecord(hrvRatio: defaults.object(forKey: hrvKey) as? Double,
                                       restingHROffset: defaults.object(forKey: rhrKey) as? Double,
                                       respOffset: defaults.object(forKey: respKey) as? Double)
    }

    func save(_ defaults: UserDefaults = .standard) {
        func put(_ value: Double?, _ key: String) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        put(hrvRatio, Self.hrvKey)
        put(restingHROffset, Self.rhrKey)
        put(respOffset, Self.respKey)
        defaults.set(true, forKey: Self.recordedKey)
    }
}
