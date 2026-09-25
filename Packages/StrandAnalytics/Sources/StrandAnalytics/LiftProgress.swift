import Foundation
import WhoopStore

// LiftProgress.swift — personal build: progression, records and push/pull balance for the Lift Log.
//
// Same rules as `LiftMetrics`: PURE (rows in, numbers out), every figure re-derivable by hand from the
// logged sets, nothing folded into Effort. What this adds is the part a lifter running a push/pull split
// asks between sessions: "what do I put on the bar next time", "am I actually getting stronger" and "is
// my pulling keeping up with my pushing".
//
// The progression rule is DOUBLE PROGRESSION, stated rather than hidden: keep the weight until every
// working set reaches the top of the rep range (without going past the set's max RPE), then add a fixed
// increment and work back up from the bottom of the range. It is a rule the lifter can check against the
// numbers on screen, not a model.

public enum LiftProgress {

    // MARK: - Push / pull balance

    /// Which side of a push/pull split a muscle's sets land on.
    public enum Side: String, CaseIterable, Sendable {
        case push, pull, legs, trunk
    }

    /// The side a muscle's sets count toward in a push/pull balance.
    ///
    /// Identical to `LiftMuscle.region` except for rear delts. The region grouping (the picker's order)
    /// files them with the other delts under push, but they are trained by horizontal PULLING — rows, face
    /// pulls, reverse flys — so a balance that counted them as push would make a lifter who trains them
    /// look push-heavy for doing exactly the work that balances pressing.
    public static func side(of muscle: LiftMuscle) -> Side {
        if muscle == .rearDelts { return .pull }
        switch muscle.region {
        case .push:  return .push
        case .pull:  return .pull
        case .legs:  return .legs
        case .trunk: return .trunk
        }
    }

    public struct Balance: Equatable, Sendable {
        public let push: Double
        public let pull: Double
        public let legs: Double
        public let trunk: Double

        public init(push: Double, pull: Double, legs: Double, trunk: Double) {
            self.push = push
            self.pull = pull
            self.legs = legs
            self.trunk = trunk
        }

        /// Pull sets per push set. Nil until both sides have work (a ratio against zero says nothing).
        public var pullPerPush: Double? {
            guard push > 0, pull > 0 else { return nil }
            return pull / push
        }

        public var total: Double { push + pull + legs + trunk }
    }

    /// Fractional weekly sets (from `LiftMetrics.muscleCounts(...).fractional` or
    /// `WhoopStore.liftSetCounts(...).fractional`) summed by side.
    public static func balance(_ fractional: [LiftMuscle: Double]) -> Balance {
        var sums: [Side: Double] = [:]
        for (muscle, sets) in fractional where sets > 0 {
            sums[side(of: muscle), default: 0] += sets
        }
        return Balance(push: sums[.push] ?? 0, pull: sums[.pull] ?? 0,
                       legs: sums[.legs] ?? 0, trunk: sums[.trunk] ?? 0)
    }

    // MARK: - Double progression

    public enum SuggestionKind: String, Sendable {
        /// Every working set reached the top of the range at or under the max RPE: add weight.
        case addWeight
        /// Inside the range: same weight, one more rep where it is there.
        case addReps
        /// Reached the reps but above the max RPE, or fell short of the bottom of the range: repeat.
        case hold
    }

    public struct Suggestion: Equatable, Sendable {
        public let kind: SuggestionKind
        /// The weight to put on the bar next time, kilograms.
        public let weightKg: Double
        /// The rep range to aim for next time.
        public let repsLow: Int
        public let repsHigh: Int
        /// What the rule looked at: the working weight last time and the reps each working set got there.
        public let lastWeightKg: Double
        public let lastReps: [Int]
        /// The increment the rule adds when it adds weight.
        public let incrementKg: Double

        public init(kind: SuggestionKind, weightKg: Double, repsLow: Int, repsHigh: Int,
                    lastWeightKg: Double, lastReps: [Int], incrementKg: Double) {
            self.kind = kind
            self.weightKg = weightKg
            self.repsLow = repsLow
            self.repsHigh = repsHigh
            self.lastWeightKg = lastWeightKg
            self.lastReps = lastReps
            self.incrementKg = incrementKg
        }
    }

    /// The usual smallest jump: 5 kg for the lower body's big movers, 2.5 kg for everything else.
    public static func incrementKg(for primary: LiftMuscle?) -> Double {
        guard let primary else { return 2.5 }
        return primary.region == .legs && primary != .calves ? 5.0 : 2.5
    }

    /// Next session's target for one exercise, from its last session's sets and its program line.
    ///
    /// Looks at the WORKING sets done at the heaviest weight used last time (lighter back-off sets do not
    /// decide whether the top weight is mastered). Nil when there is nothing to reason from: no performed
    /// working set with both a weight and reps, or no rep target at all.
    ///
    /// - Parameters:
    ///   - lastSets: the exercise's sets from its most recent session (any order; warm-ups ignored).
    ///   - repsLow/repsHigh: the program line's rep target; a single count may arrive in either field.
    ///   - maxRpe: the line's max RPE. A set left unrated is not held against the rule.
    public static func suggestion(lastSets: [LiftSetRow], repsLow: Int?, repsHigh: Int?,
                                  maxRpe: Double?, primaryMuscle: LiftMuscle?) -> Suggestion? {
        guard let low = repsLow ?? repsHigh, let high = repsHigh ?? repsLow, low > 0, high >= low else {
            return nil
        }
        let working = lastSets.filter { s in
            guard !s.isWarmup, LiftMetrics.isPerformed(reps: s.reps),
                  let w = s.weightKg, w > 0, let r = s.reps, r > 0 else { return false }
            return true
        }
        guard let top = working.compactMap(\.weightKg).max() else { return nil }
        let atTop = working
            .filter { abs(($0.weightKg ?? 0) - top) < 0.001 }
            .sorted { $0.setIndex < $1.setIndex }
        let reps = atTop.compactMap(\.reps)
        guard !reps.isEmpty else { return nil }

        let increment = incrementKg(for: primaryMuscle)
        let allAtTopOfRange = reps.allSatisfy { $0 >= high }
        let withinRpe = atTop.allSatisfy { s in
            guard let ceiling = maxRpe, let rpe = s.rpe else { return true }
            return rpe <= ceiling + 0.001
        }
        let anyBelowRange = reps.contains { $0 < low }

        let kind: SuggestionKind
        let nextWeight: Double
        if allAtTopOfRange && withinRpe {
            kind = .addWeight
            nextWeight = top + increment
        } else if allAtTopOfRange || anyBelowRange {
            kind = .hold
            nextWeight = top
        } else {
            kind = .addReps
            nextWeight = top
        }
        return Suggestion(kind: kind, weightKg: nextWeight, repsLow: low, repsHigh: high,
                          lastWeightKg: top, lastReps: reps, incrementKg: increment)
    }

    // MARK: - Estimated-1RM progress and records

    public struct Point: Equatable, Sendable {
        /// Session start, unix seconds.
        public let ts: Int
        /// The session's best Epley estimate for the exercise, kilograms.
        public let e1rmKg: Double

        public init(ts: Int, e1rmKg: Double) {
            self.ts = ts
            self.e1rmKg = e1rmKg
        }
    }

    public struct ExerciseProgress: Equatable, Sendable {
        public let exercise: String
        /// One point per session that had a set able to support an estimate, oldest first.
        public let points: [Point]
        public let bestKg: Double
        /// When the best estimate was set (the first session that reached it).
        public let bestTs: Int
        /// True when the most recent session beat every earlier one (and there was an earlier one).
        public let latestIsRecord: Bool
        /// Latest estimate minus the estimate from the last session at least 28 days before it.
        /// Nil when the history does not reach back that far.
        public let changeOver4WeeksKg: Double?

        public var latestKg: Double { points.last?.e1rmKg ?? 0 }
        public var latestTs: Int { points.last?.ts ?? 0 }
    }

    /// Per-exercise estimated-1RM history across sessions, most recently trained exercise first.
    ///
    /// Each session contributes its best estimate per exercise (Epley, sets of up to
    /// `LiftMetrics.oneRepMaxRepCeiling` reps, warm-ups excluded) — the same estimate the session detail
    /// shows, so the trend and the session read back the same number.
    public static func progress(sessions: [(startTs: Int, sets: [LiftSetRow])]) -> [ExerciseProgress] {
        var series: [String: [Point]] = [:]
        for session in sessions.sorted(by: { $0.startTs < $1.startTs }) {
            var best: [String: Double] = [:]
            for s in session.sets where !s.isWarmup && LiftMetrics.isPerformed(reps: s.reps) {
                guard let e = LiftMetrics.estimatedOneRepMaxKg(weightKg: s.weightKg, reps: s.reps) else { continue }
                best[s.exercise] = max(best[s.exercise] ?? 0, e)
            }
            for (exercise, e) in best {
                series[exercise, default: []].append(Point(ts: session.startTs, e1rmKg: e))
            }
        }
        let fourWeeks = 28 * 86_400
        let out: [ExerciseProgress] = series.compactMap { exercise, points in
            guard let last = points.last else { return nil }
            var bestKg = 0.0
            var bestTs = last.ts
            for p in points where p.e1rmKg > bestKg + 0.001 {
                bestKg = p.e1rmKg
                bestTs = p.ts
            }
            let earlier = points.dropLast()
            let previousBest = earlier.map(\.e1rmKg).max()
            let latestIsRecord = previousBest.map { last.e1rmKg > $0 + 0.001 } ?? false
            let reference = points.last { $0.ts <= last.ts - fourWeeks }
            return ExerciseProgress(
                exercise: exercise, points: points, bestKg: bestKg, bestTs: bestTs,
                latestIsRecord: latestIsRecord,
                changeOver4WeeksKg: reference.map { last.e1rmKg - $0.e1rmKg })
        }
        return out.sorted { a, b in
            a.latestTs != b.latestTs ? a.latestTs > b.latestTs : a.exercise < b.exercise
        }
    }
}
