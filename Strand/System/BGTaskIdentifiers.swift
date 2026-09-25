import Foundation

/// Personal build: background-task identifiers resolved from the running bundle's Info.plist.
///
/// Every scheduler used to derive its identifier from `Bundle.main.bundleIdentifier`. A sideloader
/// (AltStore, Sideloadly) re-signs the app under its own bundle id, e.g. `com.noopapp.noop.ABCDE12345`,
/// but leaves `BGTaskSchedulerPermittedIdentifiers` as it was built (`com.noopapp.noop.rescore`, …). The
/// derived id was then not a permitted one, `register` returned false, `submit` threw into a `try?`, and
/// the background re-score / Apple Health write-back / debug export never ran; scores only caught up when
/// the app was opened. Reading the permitted list and picking the entry by its suffix gives the id iOS
/// will actually accept, whichever way the sideloader treated the plist.
enum BGTaskIdentifiers {

    /// The permitted identifier ending in `.<suffix>`; the bundle-derived id when none is listed
    /// (unchanged behaviour for a task that was never permitted, such as the coach brief).
    static func identifier(suffix: String) -> String {
        let permitted = (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
            as? [String]) ?? []
        return resolve(suffix: suffix, permitted: permitted, bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// Pure core of `identifier(suffix:)`.
    static func resolve(suffix: String, permitted: [String], bundleIdentifier: String?) -> String {
        let bundleDerived = (bundleIdentifier ?? "com.noopapp.noop") + "." + suffix
        if permitted.contains(bundleDerived) { return bundleDerived }
        if let match = permitted.first(where: { $0.hasSuffix("." + suffix) }) { return match }
        return bundleDerived
    }
}
