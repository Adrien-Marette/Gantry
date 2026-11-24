import Foundation

/// Cumulative token usage for a single model, as reported by Claude Code's
/// `modelUsage` object. Claude Code reports these values cumulatively for the
/// session, so per-turn cost is the difference between two snapshots.
public struct ModelTokenUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    /// Claude Code's own cost estimate for this model. Used only when Gantry
    /// has no published pricing for the model.
    public var reportedCostUSD: Double

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        reportedCostUSD: Double = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reportedCostUSD = reportedCostUSD
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// The portion of this usage that occurred after `previous`.
    public func subtracting(_ previous: ModelTokenUsage) -> ModelTokenUsage {
        ModelTokenUsage(
            inputTokens: max(0, inputTokens - previous.inputTokens),
            outputTokens: max(0, outputTokens - previous.outputTokens),
            cacheReadTokens: max(0, cacheReadTokens - previous.cacheReadTokens),
            cacheCreationTokens: max(0, cacheCreationTokens - previous.cacheCreationTokens),
            reportedCostUSD: max(0, reportedCostUSD - previous.reportedCostUSD)
        )
    }
}

/// Per-million-token list prices for one model.
public struct ModelPricing: Hashable, Sendable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    public var cacheReadPerMillion: Double
    public var cacheWritePerMillion: Double

    public init(
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheReadPerMillion: Double? = nil,
        cacheWritePerMillion: Double? = nil
    ) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        // Anthropic charges cache reads at 10% of input and 5-minute cache
        // writes at 125% of input. Callers override the models that differ.
        self.cacheReadPerMillion = cacheReadPerMillion ?? inputPerMillion * 0.1
        self.cacheWritePerMillion = cacheWritePerMillion ?? inputPerMillion * 1.25
    }

    public func cost(for usage: ModelTokenUsage) -> Double {
        let total =
            Double(usage.inputTokens) * inputPerMillion
            + Double(usage.outputTokens) * outputPerMillion
            + Double(usage.cacheReadTokens) * cacheReadPerMillion
            + Double(usage.cacheCreationTokens) * cacheWritePerMillion
        return total / 1_000_000
    }

    func multiplied(by multiplier: Double) -> ModelPricing {
        ModelPricing(
            inputPerMillion: inputPerMillion * multiplier,
            outputPerMillion: outputPerMillion * multiplier,
            cacheReadPerMillion: cacheReadPerMillion * multiplier,
            cacheWritePerMillion: cacheWritePerMillion * multiplier
        )
    }
}

/// Published list pricing keyed by the model that actually served the request.
/// Claude Code's own `total_cost_usd` is based on its internal assumptions and
/// is wrong or zero for many Anthropic-compatible providers, so Gantry prices
/// the reported token usage itself whenever it knows the model.
public enum ModelPricingTable {
    private struct Rate {
        var prefix: String
        var pricing: ModelPricing
    }

    // Anthropic first-party prices, USD per million tokens. Cache read and
    // write prices follow the defaults in `ModelPricing` where not supplied.
    // Haiku 5.5's published $0.10/$0.50 rates apply up to 100K-token prompts;
    // longer prompts cost more, which token totals alone cannot distinguish.
    private static let anthropicRates: [Rate] = [
        Rate(prefix: "claude-fable-5-2", pricing: ModelPricing(
            inputPerMillion: 8, outputPerMillion: 40,
            cacheReadPerMillion: 0.20, cacheWritePerMillion: 10
        )),
        Rate(prefix: "claude-mythos-5-2", pricing: ModelPricing(
            inputPerMillion: 8, outputPerMillion: 40,
            cacheReadPerMillion: 0.20, cacheWritePerMillion: 10
        )),
        Rate(prefix: "claude-fable-5-1", pricing: ModelPricing(
            inputPerMillion: 10, outputPerMillion: 50
        )),
        Rate(prefix: "claude-fable-5", pricing: ModelPricing(
            inputPerMillion: 10, outputPerMillion: 50
        )),
        Rate(prefix: "claude-opus-5-5", pricing: ModelPricing(
            inputPerMillion: 4, outputPerMillion: 20,
            cacheReadPerMillion: 0.20, cacheWritePerMillion: 5
        )),
        Rate(prefix: "claude-opus-5", pricing: ModelPricing(
            inputPerMillion: 5, outputPerMillion: 25
        )),
        Rate(prefix: "claude-opus-4-8", pricing: ModelPricing(
            inputPerMillion: 5, outputPerMillion: 25
        )),
        Rate(prefix: "claude-opus-4-7", pricing: ModelPricing(
            inputPerMillion: 5, outputPerMillion: 25
        )),
        Rate(prefix: "claude-opus-4-6", pricing: ModelPricing(
            inputPerMillion: 5, outputPerMillion: 25
        )),
        Rate(prefix: "claude-sonnet-5-5", pricing: ModelPricing(
            inputPerMillion: 2, outputPerMillion: 10,
            cacheReadPerMillion: 0.10, cacheWritePerMillion: 2.5
        )),
        Rate(prefix: "claude-sonnet-5", pricing: ModelPricing(
            inputPerMillion: 2, outputPerMillion: 10
        )),
        Rate(prefix: "claude-sonnet-4-6", pricing: ModelPricing(
            inputPerMillion: 3, outputPerMillion: 15
        )),
        Rate(prefix: "claude-haiku-5-5", pricing: ModelPricing(
            inputPerMillion: 0.10, outputPerMillion: 0.50,
            cacheReadPerMillion: 0.01, cacheWritePerMillion: 0.125
        )),
        Rate(prefix: "claude-haiku-4-5", pricing: ModelPricing(
            inputPerMillion: 1, outputPerMillion: 5
        ))
    ]

    // DeepSeek peak rates, USD per million tokens. Off-peak is half price.
    // Legacy `deepseek-chat` / `deepseek-reasoner` names are served as Flash.
    private static let deepSeekFlash = ModelPricing(
        inputPerMillion: 0.30,
        outputPerMillion: 1.20,
        cacheReadPerMillion: 0.006,
        cacheWritePerMillion: 0.30
    )
    private static let deepSeekPro = ModelPricing(
        inputPerMillion: 1.32,
        outputPerMillion: 3.96,
        cacheReadPerMillion: 0.044,
        cacheWritePerMillion: 1.32
    )

    /// Returns list pricing for a model name, or nil when the model is unknown.
    /// Names may carry provider prefixes, date suffixes, or context-window
    /// markers; only the model family and generation matter here.
    public static func pricing(for model: String, at date: Date = .now) -> ModelPricing? {
        let name = normalized(model)
        guard !name.isEmpty else { return nil }

        if name.hasPrefix("deepseek-") {
            let peak = name.contains("-pro") ? deepSeekPro : deepSeekFlash
            // Chinese public holidays are also off-peak but are not modelled;
            // this can overestimate on those days.
            return isDeepSeekPeak(date) ? peak : peak.multiplied(by: 0.5)
        }

        for rate in anthropicRates where name.hasPrefix(rate.prefix) {
            return rate.pricing
        }
        return nil
    }

    /// Shared with `ModelContextWindow` so pricing and context-window lookups
    /// agree on model families.
    static func normalized(_ model: String) -> String {
        var name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Strip provider prefixes such as "anthropic.", "us.anthropic.", or
        // "openrouter/anthropic/".
        if let range = name.range(of: "claude-") {
            name = String(name[range.lowerBound...])
        } else if let range = name.range(of: "deepseek-") {
            name = String(name[range.lowerBound...])
        }
        // Drop dated snapshots, e.g. "claude-sonnet-4-5-20250929".
        if let range = name.range(of: #"[-@]\d{8}.*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    private static func isDeepSeekPeak(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let weekday = calendar.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false }
        let hour = calendar.component(.hour, from: date)
        return (hour >= 1 && hour < 4) || (hour >= 6 && hour < 10)
    }
}

/// Prices Claude Code usage using the model that actually served each request.
public enum ModelCostEstimator {
    /// Prices a complete cumulative `modelUsage` snapshot. Models with
    /// published pricing are priced from tokens; unknown models fall back to
    /// the cost Claude Code reported.
    public static func cost(
        of modelUsage: [String: ModelTokenUsage],
        at date: Date = .now
    ) -> Double? {
        guard !modelUsage.isEmpty else { return nil }
        return modelUsage.reduce(0) { total, entry in
            total + cost(of: entry.value, model: entry.key, at: date)
        }
    }

    /// Prices only the increase between two cumulative `modelUsage` snapshots.
    /// Returns nil when there is no baseline or when `current` looks like a
    /// fresh per-call snapshot rather than a cumulative one.
    public static func incrementalCost(
        from previous: [String: ModelTokenUsage]?,
        to current: [String: ModelTokenUsage],
        at date: Date = .now
    ) -> Double? {
        guard let previous, !current.isEmpty else { return nil }
        guard isCumulative(current, relativeTo: previous) else { return nil }
        return current.reduce(0) { total, entry in
            let prior = previous[entry.key] ?? ModelTokenUsage()
            return total + cost(of: entry.value.subtracting(prior), model: entry.key, at: date)
        }
    }

    /// Prices a per-turn aggregate usage row using the actual model name.
    /// This is the fallback when Claude Code does not report `modelUsage`.
    public static func cost(
        of usage: TurnUsage,
        model: String?,
        at date: Date = .now
    ) -> Double? {
        guard let model,
              let pricing = ModelPricingTable.pricing(for: model, at: date) else {
            return nil
        }
        return pricing.cost(for: ModelTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheCreationTokens: usage.cacheCreationTokens
        ))
    }

    private static func cost(
        of usage: ModelTokenUsage,
        model: String,
        at date: Date
    ) -> Double {
        if let pricing = ModelPricingTable.pricing(for: model, at: date) {
            return pricing.cost(for: usage)
        }
        return max(0, usage.reportedCostUSD)
    }

    private static func isCumulative(
        _ current: [String: ModelTokenUsage],
        relativeTo previous: [String: ModelTokenUsage]
    ) -> Bool {
        for (model, usage) in current {
            guard let prior = previous[model] else { continue }
            guard usage.inputTokens >= prior.inputTokens,
                  usage.outputTokens >= prior.outputTokens,
                  usage.cacheReadTokens >= prior.cacheReadTokens,
                  usage.cacheCreationTokens >= prior.cacheCreationTokens else {
                return false
            }
        }
        return true
    }
}
