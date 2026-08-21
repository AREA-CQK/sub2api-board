import SwiftUI

enum BoardTheme {
    static let canvas = Color(red: 0.025, green: 0.035, blue: 0.05)
    static let surface = Color(red: 0.045, green: 0.065, blue: 0.085)
    static let elevated = Color(red: 0.065, green: 0.09, blue: 0.11)
    static let border = Color(red: 0.12, green: 0.22, blue: 0.24)
    static let track = Color.white.opacity(0.09)
    static let accent = Color(red: 0.2, green: 0.9, blue: 0.76)
    static let signal = Color(red: 0.3, green: 0.68, blue: 1)
    static let healthy = Color(red: 0.28, green: 0.88, blue: 0.58)
    static let warning = Color(red: 1, green: 0.68, blue: 0.22)
    static let critical = Color(red: 1, green: 0.31, blue: 0.34)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.56)

    static func quotaColor(utilization: Double) -> Color {
        if utilization >= 100 { return critical }
        if utilization >= 80 { return warning }
        return accent
    }
}
