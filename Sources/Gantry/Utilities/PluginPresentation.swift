import SwiftUI
import GantryCore

enum PluginPresentation {
    static func symbol(for kind: PluginKind) -> String {
        kind.symbol
    }

    static func tint(for kind: PluginKind) -> Color {
        switch kind {
        case .github: return Palette.ink
        case .gitlab: return Palette.accent
        case .gitea: return Palette.success
        }
    }

    static func summary(for plugin: PluginConnection) -> String {
        let account = plugin.accountName.isEmpty ? plugin.name : "@\(plugin.accountName)"
        return "\(account) · \(plugin.serverHost)"
    }

    static func checkTint(for state: PluginCheckState) -> Color {
        switch state {
        case .success: return Palette.success
        case .failure: return Palette.danger
        case .pending: return Palette.warning
        case .neutral, .skipped: return Palette.tertiaryInk
        case .cancelled, .unknown: return Palette.faintInk
        }
    }

    static func checkSymbol(for state: PluginCheckState) -> String {
        switch state {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .pending: return "clock.fill"
        case .neutral: return "minus.circle.fill"
        case .skipped: return "forward.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    static func checkSummary(_ checks: [PluginCheck]) -> (text: String, tint: Color)? {
        guard !checks.isEmpty else { return nil }
        let failures = checks.filter { $0.state == .failure }.count
        let pending = checks.filter { $0.state == .pending }.count
        if failures > 0 {
            return ("\(failures) failing", Palette.danger)
        }
        if pending > 0 {
            return ("\(pending) pending", Palette.warning)
        }
        return ("\(checks.count) passed", Palette.success)
    }
}
