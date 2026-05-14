import Foundation

/// Card-shaped finding the Memory Dashboard surfaces in the Insights
/// carousel. Produced by `InsightsEngine` — either from heuristics (Pass 1)
/// or from an opt-in LLM polish (Pass 2). The same value type is used in
/// both paths; only the `title`/`body` change.
struct Insight: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let kind: InsightKind
    var title: String
    var body: String
    let cta: InsightCTA
    /// Internal ranking score — higher signal surfaces first. Not shown.
    let signal: Double
}

enum InsightKind: String, Sendable, Codable, CaseIterable {
    case workflowDetected
    case automationOpportunity
    case memoryInsight
    case focusPattern

    var symbol: String {
        switch self {
        case .workflowDetected:       return "bolt.fill"
        case .automationOpportunity:  return "sparkles"
        case .memoryInsight:          return "rectangle.stack.fill"
        case .focusPattern:           return "scope"
        }
    }

    var headline: String {
        switch self {
        case .workflowDetected:       return "Workflow Detected"
        case .automationOpportunity:  return "Automation Opportunity"
        case .memoryInsight:          return "Memory Insight"
        case .focusPattern:           return "Focus Pattern"
        }
    }
}

/// Callback target for an insight card's primary button.
enum InsightCTA: Equatable, Sendable, Codable {
    case createSkill(seed: String)
    case createFlow(seed: String)
    case viewMemory(startedAt: Date, endedAt: Date)
    case seeDetails(insightID: UUID)

    var label: String {
        switch self {
        case .createSkill:  return "Create Skill"
        case .createFlow:   return "Create Flow"
        case .viewMemory:   return "View Memory"
        case .seeDetails:   return "See Details"
        }
    }
}
