import Foundation

enum RouteDisplay {
    static func distance(metres: Double) -> String {
        String(format: "%.2f mi", metres / 1609.344)
    }

    static func duration(seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 min" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
