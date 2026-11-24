import Foundation
import Testing
@testable import GantryCore

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(
        timeZone: calendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour
    ))!
}

@Test func pricesAnthropicUsageByModel() throws {
    let offPeak = utcDate(2026, 11, 23, 0)
    let sonnet = try #require(ModelCostEstimator.cost(
        of: ["claude-sonnet-5-5": ModelTokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000)],
        at: offPeak
    ))
    #expect(abs(sonnet - 12) < 0.0001)

    let opus = try #require(ModelCostEstimator.cost(
        of: ["claude-opus-5-5": ModelTokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000)],
        at: offPeak
    ))
    #expect(abs(opus - 24) < 0.0001)
}

@Test func pricesCacheTokensSeparately() throws {
    let cost = try #require(ModelCostEstimator.cost(
        of: ["claude-sonnet-5-5": ModelTokenUsage(
            cacheReadTokens: 1_000_000,
            cacheCreationTokens: 1_000_000
        )],
        at: utcDate(2026, 11, 23, 0)
    ))
    // $0.10 cache read + $2.50 cache write.
    #expect(abs(cost - 2.60) < 0.0001)
}

@Test func deepSeekPricingUsesPeakAndOffPeakRates() throws {
    let peak = utcDate(2026, 11, 23, 2)     // Monday, 02:00 UTC
    let offPeak = utcDate(2026, 11, 23, 0)  // Monday, 00:00 UTC
    let usage = ModelTokenUsage(inputTokens: 1_000_000, outputTokens: 1_000_000)

    let flashPeak = try #require(ModelCostEstimator.cost(of: ["deepseek-flash": usage], at: peak))
    let flashOffPeak = try #require(ModelCostEstimator.cost(of: ["deepseek-flash": usage], at: offPeak))
    #expect(abs(flashPeak - 1.50) < 0.0001)
    #expect(abs(flashOffPeak - 0.75) < 0.0001)

    let proPeak = try #require(ModelCostEstimator.cost(of: ["deepseek-v4-pro": usage], at: peak))
    let proOffPeak = try #require(ModelCostEstimator.cost(of: ["deepseek-v4-pro": usage], at: offPeak))
    #expect(abs(proPeak - 5.28) < 0.0001)
    #expect(abs(proOffPeak - 2.64) < 0.0001)
}

@Test func modelNameNormalizationHandlesPrefixesAndSnapshots() throws {
    let date = utcDate(2026, 11, 23, 0)
    let usage = ModelTokenUsage(inputTokens: 1_000_000)

    let opus = try #require(ModelCostEstimator.cost(
        of: ["anthropic/claude-opus-5-5": usage],
        at: date
    ))
    #expect(abs(opus - 4) < 0.0001)

    let haikuSnapshot = try #require(ModelCostEstimator.cost(
        of: ["claude-haiku-4-5-20251001": usage],
        at: date
    ))
    #expect(abs(haikuSnapshot - 1) < 0.0001)

    let deepSeekServedName = try #require(ModelCostEstimator.cost(
        of: ["DeepSeek-V4.1-Flash-1017": usage],
        at: date
    ))
    #expect(abs(deepSeekServedName - 0.15) < 0.0001)
}

@Test func incrementalCostPricesOnlyNewTokens() throws {
    let date = utcDate(2026, 11, 23, 0)
    let previous = ["claude-sonnet-5-5": ModelTokenUsage(inputTokens: 1_000_000)]
    let current = ["claude-sonnet-5-5": ModelTokenUsage(inputTokens: 2_000_000)]

    let incremental = try #require(ModelCostEstimator.incrementalCost(
        from: previous,
        to: current,
        at: date
    ))
    #expect(abs(incremental - 2) < 0.0001)

    let reset = ["claude-sonnet-5-5": ModelTokenUsage(inputTokens: 500_000)]
    #expect(ModelCostEstimator.incrementalCost(from: previous, to: reset, at: date) == nil)
    #expect(ModelCostEstimator.incrementalCost(from: nil, to: current, at: date) == nil)
}

@Test func incrementalCostPricesNewModelsFromZero() throws {
    let date = utcDate(2026, 11, 23, 0)
    let previous = ["claude-sonnet-5-5": ModelTokenUsage(inputTokens: 1_000_000)]
    let current = [
        "claude-sonnet-5-5": ModelTokenUsage(inputTokens: 1_500_000),
        "claude-opus-5-5": ModelTokenUsage(inputTokens: 1_000_000)
    ]

    let incremental = try #require(ModelCostEstimator.incrementalCost(from: previous, to: current, at: date))
    // Sonnet's 0.5M new input tokens at $2, plus Opus priced from zero at $4.
    #expect(abs(incremental - 5) < 0.0001)
}

@Test func incrementalCostMixesKnownAndUnknownModels() throws {
    let date = utcDate(2026, 11, 23, 0)
    let previous = [
        "claude-sonnet-5-5": ModelTokenUsage(inputTokens: 1_000_000),
        "gateway-main": ModelTokenUsage(inputTokens: 100, reportedCostUSD: 0.10)
    ]
    let current = [
        "claude-sonnet-5-5": ModelTokenUsage(inputTokens: 1_500_000),
        "gateway-main": ModelTokenUsage(inputTokens: 400, reportedCostUSD: 0.35)
    ]

    let incremental = try #require(ModelCostEstimator.incrementalCost(from: previous, to: current, at: date))
    // $1 of new Sonnet tokens plus the unknown model's $0.25 reported delta.
    #expect(abs(incremental - 1.25) < 0.0001)
}

@Test func incrementalCostRejectsPartiallyResetSnapshots() throws {
    let date = utcDate(2026, 11, 23, 0)
    let previous = [
        "claude-sonnet-5-5": ModelTokenUsage(inputTokens: 2_000_000),
        "gateway-main": ModelTokenUsage(inputTokens: 100)
    ]
    let current = [
        "claude-sonnet-5-5": ModelTokenUsage(inputTokens: 3_000_000),
        "gateway-main": ModelTokenUsage(inputTokens: 50)
    ]

    // One model grew while another reset, so this is not a cumulative pair.
    #expect(ModelCostEstimator.incrementalCost(from: previous, to: current, at: date) == nil)
}

@Test func pricingTablePrefersSpecificPrefixes() throws {
    let date = utcDate(2026, 11, 23, 0)
    let million = ModelTokenUsage(inputTokens: 1_000_000)

    let fable = try #require(ModelCostEstimator.cost(of: ["claude-fable-5-2": million], at: date))
    #expect(abs(fable - 8) < 0.0001)

    let opus = try #require(ModelCostEstimator.cost(of: ["claude-opus-5-0": million], at: date))
    #expect(abs(opus - 5) < 0.0001)

    let sonnet = try #require(ModelCostEstimator.cost(of: ["claude-sonnet-5-0": million], at: date))
    #expect(abs(sonnet - 2) < 0.0001)
}

@Test func unknownModelsFallBackToReportedCost() throws {
    let date = utcDate(2026, 11, 23, 0)
    let previous = ["gateway-main": ModelTokenUsage(
        inputTokens: 100,
        reportedCostUSD: 0.10
    )]
    let current = ["gateway-main": ModelTokenUsage(
        inputTokens: 400,
        reportedCostUSD: 0.25
    )]

    let cumulative = try #require(ModelCostEstimator.cost(of: current, at: date))
    #expect(abs(cumulative - 0.25) < 0.0001)

    let incremental = try #require(ModelCostEstimator.incrementalCost(
        from: previous,
        to: current,
        at: date
    ))
    #expect(abs(incremental - 0.15) < 0.0001)
}

@Test func parsesCumulativeModelUsageFromResult() throws {
    let line = """
    {"type":"result","subtype":"success","is_error":false,"duration_ms":1200,"result":"Done","session_id":"s1","total_cost_usd":0.05,"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10},"modelUsage":{"deepseek-chat":{"inputTokens":1000,"outputTokens":200,"cacheReadInputTokens":300,"cacheCreationInputTokens":40,"costUSD":0.004},"deepseek-reasoner":{"inputTokens":50,"outputTokens":10,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"costUSD":0.001}}}
    """
    let events = ClaudeStreamParser.parse(line: line)
    guard case .result(let result) = events.first else {
        Issue.record("Expected a result event")
        return
    }

    let chat = try #require(result.modelUsage["deepseek-chat"])
    #expect(chat.inputTokens == 1000)
    #expect(chat.outputTokens == 200)
    #expect(chat.cacheReadTokens == 300)
    #expect(chat.cacheCreationTokens == 40)
    #expect(abs(chat.reportedCostUSD - 0.004) < 0.0001)

    let reasoner = try #require(result.modelUsage["deepseek-reasoner"])
    #expect(reasoner.inputTokens == 50)
    #expect(reasoner.reportedCostUSD == 0.001)

    // The dominant model is the one reported for the session.
    #expect(result.usage.modelName == "deepseek-chat")
}

@Test func contextWindowFollowsModelFamily() {
    // Claude Code marks a resolved 1M model with `[1m]` in modelUsage keys.
    #expect(ModelContextWindow.limit(for: "deepseek-flash[1m]") == 1_000_000)
    #expect(ModelContextWindow.limit(for: "claude-sonnet-4-5-20250929[1m]") == 1_000_000)
    #expect(ModelContextWindow.limit(for: "claude-sonnet-5-5") == 1_000_000)
    #expect(ModelContextWindow.limit(for: "anthropic/claude-opus-5-5") == 1_000_000)
    // Standard-window generations stay at 200K without the marker.
    #expect(ModelContextWindow.limit(for: "claude-haiku-4-5-20251001") == 200_000)
    #expect(ModelContextWindow.limit(for: "claude-sonnet-4-5") == 200_000)
    #expect(ModelContextWindow.limit(for: "claude-opus-4-5") == 200_000)
    #expect(ModelContextWindow.limit(for: "claude-opus-4") == 200_000)
    #expect(ModelContextWindow.limit(for: "claude-sonnet-4") == 200_000)
    // Later generations have 1M by default.
    #expect(ModelContextWindow.limit(for: "claude-opus-4-6") == 1_000_000)
    #expect(ModelContextWindow.limit(for: "gateway-main") == ModelContextWindow.fallback)
    #expect(ModelContextWindow.limit(for: nil) == ModelContextWindow.fallback)
}

@Test func contextFractionIsClampedForTheMeter() {
    let fraction = ModelContextWindow.fraction(tokens: 169_718, model: "deepseek-flash[1m]")
    #expect(abs(fraction - 0.169_718) < 0.000_001)
    #expect(ModelContextWindow.fraction(tokens: 100_000, model: "claude-haiku-4-5") == 0.5)
    #expect(ModelContextWindow.fraction(tokens: 0, model: "claude-sonnet-5-5") == 0)
    #expect(ModelContextWindow.fraction(tokens: 2_000_000, model: "claude-sonnet-5-5") == 1)
}
