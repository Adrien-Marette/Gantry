import SwiftUI
import GantryCore

enum ProviderPresentation {
    static func symbol(for preset: ProviderPreset) -> String {
        switch preset {
        case .claudeCode: return "terminal"
        case .anthropic: return "cloud"
        case .deepSeek: return "server.rack"
        case .custom: return "slider.horizontal.3"
        }
    }

    static func tint(for preset: ProviderPreset) -> Color {
        switch preset {
        case .claudeCode: return Palette.secondaryInk
        case .anthropic: return Palette.accent
        case .deepSeek: return Palette.info
        case .custom: return Palette.success
        }
    }

    static func summary(for provider: AIProvider) -> String {
        if provider.preset == .claudeCode {
            return "Uses your existing Claude Code setup"
        }
        let host = AIProvider.host(from: provider.baseURL) ?? provider.baseURL
        if provider.requiresAPIKey {
            return "\(host) · \(provider.authMode.title)"
        }
        return "\(host) · Claude Code login"
    }
}
