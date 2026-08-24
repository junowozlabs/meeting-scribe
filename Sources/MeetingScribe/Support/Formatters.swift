import Foundation

enum AppFormatters {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }

    static func timestamp(_ milliseconds: Int, srt: Bool = false) -> String {
        let value = max(0, milliseconds)
        let seconds = value / 1000
        return String(format: "%02d:%02d:%02d%@%03d", seconds / 3600, (seconds % 3600) / 60, seconds % 60, srt ? "," : ".", value % 1000)
    }
}
