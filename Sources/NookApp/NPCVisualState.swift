import Foundation

enum NPCActivityKind: Equatable {
    case wandering
    case working(sessionCount: Int)
    case resting
}

enum NPCWorkTrait: String, Codable, Equatable {
    case newAgent
    case steady
    case deepThinker
    case powerUser
}

struct NPCVisualState: Equatable {
    let id: String
    let name: String
    let bond: Int
    let totalTokens: Int
    let totalBits: Double
    let activity: NPCActivityKind
    let trait: NPCWorkTrait
    let isNight: Bool

    var sessionCount: Int {
        if case let .working(count) = activity { return count }
        return 0
    }

    var isWorking: Bool {
        sessionCount > 0
    }

    var loadTier: Int {
        min(sessionCount, 3)
    }

    static func derive(
        from model: NPCModel,
        activeSessionCount: Int,
        dayPhase: DayPhase
    ) -> NPCVisualState {
        let activity: NPCActivityKind
        if activeSessionCount > 0 {
            activity = .working(sessionCount: activeSessionCount)
        } else if dayPhase == .night {
            activity = .resting
        } else {
            activity = .wandering
        }

        return NPCVisualState(
            id: model.id,
            name: model.name,
            bond: model.bond,
            totalTokens: model.totalTokens,
            totalBits: model.totalBits,
            activity: activity,
            trait: NPCVisualState.trait(for: model),
            isNight: dayPhase == .night
        )
    }

    private static func trait(for model: NPCModel) -> NPCWorkTrait {
        switch model.totalTokens {
        case ..<10_000:
            return .newAgent
        case ..<50_000:
            return .steady
        case ..<200_000:
            return .deepThinker
        default:
            return .powerUser
        }
    }
}
