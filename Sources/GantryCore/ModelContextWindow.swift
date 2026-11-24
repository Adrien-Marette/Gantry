import Foundation

/// Context-window sizes Gantry assumes when it shows how full Claude's context
/// is. The stream protocol does not report the window size, but Claude Code
/// resolves a 1M model with a `[1m]` marker in `modelUsage` keys (for example
/// `deepseek-flash[1m]`), so the resolved model name is the best signal.
public enum ModelContextWindow {
    /// The standard window Claude Code uses for older Anthropic models.
    public static let standard = 200_000
    /// The extended window, marked by `[1m]` in the resolved model name.
    public static let extended = 1_000_000
    /// Claude Code assumes 1M for models its catalog does not describe, so
    /// Gantry does the same for custom providers.
    public static let fallback = extended

    /// Anthropic models that Claude Code serves with the standard window unless
    /// the resolved name carries a `[1m]` marker. Names are normalized first, so
    /// dated snapshots and provider prefixes match their family.
    private static let standardWindowNames: Set<String> = [
        "claude-opus-4",
        "claude-opus-4-0",
        "claude-opus-4-1",
        "claude-opus-4-5",
        "claude-sonnet-4",
        "claude-sonnet-4-0",
        "claude-sonnet-4-5",
        "claude-haiku-4-5"
    ]

    public static func limit(for model: String?) -> Int {
        guard let model else { return fallback }
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return fallback }
        if name.contains("[1m]") { return extended }

        let normalized = ModelPricingTable.normalized(name)
        if normalized.hasPrefix("claude-3-") || standardWindowNames.contains(normalized) {
            return standard
        }
        if normalized.hasPrefix("claude-") { return extended }
        return fallback
    }

    /// The share of the assumed window in use, clamped to 0...1 for drawing.
    public static func fraction(tokens: Int, model: String?) -> Double {
        let limit = limit(for: model)
        guard limit > 0, tokens > 0 else { return 0 }
        return min(1, Double(tokens) / Double(limit))
    }
}
