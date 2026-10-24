import Foundation

/// One-tap playback speeds offered for a route.
///
/// A preset stays highlighted for every speed from its own value up to the
/// next preset, so a custom speed of 100 mph still reads as `drive` rather
/// than clearing the selection. The slowest preset also covers anything below
/// its own speed.
enum SpeedPreset: String, CaseIterable, Identifiable {
    case walk = "Walk"
    case cycle = "Cycle"
    case drive = "Drive"

    var id: String { rawValue }

    /// Speed applied when the preset is tapped, and the lower bound of its band.
    var speedKmh: Double {
        switch self {
        case .walk: return 5
        case .cycle: return 18
        case .drive: return 50
        }
    }

    /// The preset whose band contains `speedKmh`.
    static func matching(speedKmh: Double) -> SpeedPreset {
        var match = allCases[0]
        for preset in allCases where speedKmh >= preset.speedKmh { match = preset }
        return match
    }
}
