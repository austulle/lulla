import Foundation

/// Typical awake time between sleeps by age, as commonly published in infant
/// sleep guidance. The first window of the day is the shortest, the one
/// before bedtime the longest; windows in between are interpolated.
/// These are typical ranges, not medical advice — every baby differs, which
/// is why `NapPredictor` blends in the baby's own history.
struct WakeWindowBand: Sendable, Equatable {
    /// Inclusive lower age bound in days (corrected age).
    let fromDays: Int
    let label: String
    /// Typical number of naps per day at this age.
    let naps: Int
    /// First window of the day (morning wake → first nap), minutes.
    let first: ClosedRange<Double>
    /// Last window of the day (last nap → bedtime), minutes.
    let last: ClosedRange<Double>
}

enum WakeWindows {
    static let bands: [WakeWindowBand] = [
        .init(fromDays: 0, label: "0–4 weeks", naps: 5, first: 35...50, last: 45...60),
        .init(fromDays: 28, label: "4–8 weeks", naps: 4, first: 50...70, last: 60...90),
        .init(fromDays: 56, label: "2–3 months", naps: 4, first: 60...75, last: 75...105),
        .init(fromDays: 91, label: "3–4 months", naps: 4, first: 75...90, last: 90...120),
        .init(fromDays: 122, label: "4–5 months", naps: 3, first: 90...105, last: 120...150),
        .init(fromDays: 152, label: "5–6 months", naps: 3, first: 105...120, last: 135...165),
        .init(fromDays: 183, label: "6–7 months", naps: 3, first: 120...135, last: 150...180),
        .init(fromDays: 213, label: "7–9 months", naps: 2, first: 135...165, last: 180...210),
        .init(fromDays: 274, label: "9–12 months", naps: 2, first: 165...195, last: 210...240),
        .init(fromDays: 365, label: "12–15 months", naps: 2, first: 180...210, last: 225...255),
        .init(fromDays: 456, label: "15–18 months", naps: 1, first: 270...330, last: 270...330),
        .init(fromDays: 548, label: "18–24 months", naps: 1, first: 300...330, last: 300...360),
        .init(fromDays: 730, label: "2–3 years", naps: 1, first: 330...360, last: 330...390),
    ]

    static func band(forAgeDays days: Int) -> WakeWindowBand {
        bands.last { days >= $0.fromDays } ?? bands[0]
    }

    /// Typical range (minutes) for wake window `index` of the day, where
    /// index 0 is morning → first nap and index `band.naps` is last nap →
    /// bedtime.
    static func range(for band: WakeWindowBand, index: Int) -> ClosedRange<Double> {
        let t: Double = band.naps == 0 ? 1 : Double(min(max(index, 0), band.naps)) / Double(band.naps)
        let lo = lerp(band.first.lowerBound, band.last.lowerBound, t)
        let hi = lerp(band.first.upperBound, band.last.upperBound, t)
        return lo...hi
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

extension ClosedRange where Bound == Double {
    var mid: Double { (lowerBound + upperBound) / 2 }
}
