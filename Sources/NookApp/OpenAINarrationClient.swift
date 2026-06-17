import Foundation
import Security

enum ReactionStyle: String, Codable, CaseIterable {
    case descriptive, sarcastic, overhyped, philosophical
    case mentor, dramatic, gossip, tired, conspiracy, impressedWrong

    static func random() -> ReactionStyle { allCases.randomElement()! }

    // Tone fragment composed into NPC instructions — same fragment works for
    // both promptReaction (user prompt) and liveComment (session activity).
    var tone: String {
        switch self {
        case .descriptive:    return "Be calm and specific."
        case .sarcastic:      return "Use dry humor and light mockery. Subtly snarky, affectionate."
        case .overhyped:      return "Be ridiculously excited. Caps OK. Pure hype energy."
        case .philosophical:  return "Make an absurd, slightly profound observation."
        case .mentor:         return "Give a wise but dubious programming maxim. Unsolicited advice."
        case .dramatic:       return "Treat this as a catastrophic, world-shaking event."
        case .gossip:         return "Gossip. Treat files, bugs, and functions as drama characters."
        case .tired:          return "Sound exhausted and resigned. Max 35 chars. Very flat."
        case .conspiracy:     return "Spot a suspicious hidden pattern. Sound mildly paranoid."
        case .impressedWrong: return "Be impressed by a completely irrelevant detail. Miss the point."
        }
    }
}

struct OpenAINarrationClient {
    enum ClientError: Error {
        case missingAPIKey
        case invalidResponse
    }

    var apiKeyProvider: () -> String?
    var session: URLSession = .shared
    var model: String = "gpt-4.1-mini"

    init(apiKeyProvider: @escaping () -> String? = OpenAIAPIKeyStore.load, session: URLSession = .shared, model: String = "gpt-4.1-mini") {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.model = model
    }

    // Enriches stored session memory with LLM-generated title, summary, and cachedLines.
    // pastSessions: recent memories for this agent, used for character continuity.
    @MainActor
    func enrich(
        sessionMemory: GeneratedSessionMemory,
        digest: SessionDigest,
        bond: Int,
        totalTokens: Int,
        pastSessions: [GeneratedSessionMemory],
        personality: String? = nil
    ) async throws -> GeneratedSessionMemory {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_output_tokens": 400,
            "text": ["format": ["type": "json_object"]],
            "instructions": "Return compact JSON for an emotionally warm NPC memory. Keys: title, shortSummary, narrativeBeats, relationshipNote, cachedLines. Title must be 'Theme · Project'. Each cachedLines entry must be a single spoken sentence under 80 characters — short, specific, in-character, in English. Reference the actual project or files when possible.",
            "input": enrichPrompt(memory: sessionMemory, digest: digest, bond: bond, totalTokens: totalTokens, pastSessions: pastSessions, personality: personality)
        ])

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[Nook] OpenAI enrich failed: status \((response as? HTTPURLResponse)?.statusCode ?? -1) — \(body.prefix(300))")
            throw ClientError.invalidResponse
        }
        guard let text = Self.outputText(from: data),
              let jsonData = Self.stripCodeFence(text).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            print("[Nook] OpenAI enrich: could not parse JSON from response")
            throw ClientError.invalidResponse
        }

        var enriched = sessionMemory
        enriched.title = object["title"] as? String ?? enriched.title
        enriched.shortSummary = object["shortSummary"] as? String ?? enriched.shortSummary
        enriched.narrativeBeats = object["narrativeBeats"] as? [String] ?? enriched.narrativeBeats
        enriched.relationshipNote = object["relationshipNote"] as? String ?? enriched.relationshipNote
        if let lines = object["cachedLines"] as? [String] {
            let sanitized = lines.map { Self.sanitizeSpokenLine($0) }.filter { !$0.isEmpty }
            if !sanitized.isEmpty { enriched.cachedLines = sanitized }
        }
        enriched.updatedAt = Date()
        return enriched
    }

    // Reacts to the user's latest prompt almost in real-time (triggered on PreToolUse).
    // Called before Claude responds, so the NPC can comment on what the user is asking.
    @MainActor
    func promptReaction(
        userMessage: String,
        bond: Int,
        totalTokens: Int,
        style: ReactionStyle = .random(),
        personality: String? = nil
    ) async throws -> String {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_output_tokens": 40,
            "text": ["format": ["type": "text"]],
            "instructions": "You are a coding NPC in a pixel village game. React to what the user just sent their AI. ONE sentence in English, max 60 chars. No quotes, no explanation, just the line. \(personalityInstruction(personality)) \(style.tone)",
            "input": "Bond \(bond)/10. User just asked their AI: \"\(String(userMessage.prefix(300)))\""
        ])

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClientError.invalidResponse }
        guard let text = Self.outputText(from: data) else { throw ClientError.invalidResponse }

        return Self.sanitizeSpokenLine(text.trimmingCharacters(in: .whitespacesAndNewlines), maxLength: 70)
    }

    // Reacts to the last assistant response after Claude finishes (triggered on Stop).
    @MainActor
    func responseReaction(
        assistantSnippet: String,
        bond: Int,
        totalTokens: Int,
        style: ReactionStyle = .random(),
        personality: String? = nil
    ) async throws -> String {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_output_tokens": 40,
            "text": ["format": ["type": "text"]],
            "instructions": "You are a coding NPC in a pixel village game. React to what your AI assistant just replied. ONE sentence in English, max 60 chars. No quotes, no explanation, just the line. \(personalityInstruction(personality)) \(style.tone)",
            "input": "Bond \(bond)/10. AI assistant just replied: \"\(String(assistantSnippet.prefix(300)))\""
        ])

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClientError.invalidResponse }
        guard let text = Self.outputText(from: data) else { throw ClientError.invalidResponse }

        return Self.sanitizeSpokenLine(text.trimmingCharacters(in: .whitespacesAndNewlines), maxLength: 70)
    }

    // Generates one short spoken line reacting to what the user is doing right now.
    // Used for live display during active sessions, independent of stored cachedLines.
    @MainActor
    func liveComment(
        digest: SessionDigest,
        bond: Int,
        totalTokens: Int,
        style: ReactionStyle = .random(),
        personality: String? = nil
    ) async throws -> String {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_output_tokens": 60,
            "text": ["format": ["type": "text"]],
            "instructions": "You are a coding NPC in a pixel village game commenting on the player's work. ONE sentence in English, max 60 chars. No quotes, no explanation, just the line. \(personalityInstruction(personality)) \(style.tone)",
            "input": livePrompt(digest: digest, bond: bond, totalTokens: totalTokens, personality: personality)
        ])

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ClientError.invalidResponse }
        guard let text = Self.outputText(from: data) else { throw ClientError.invalidResponse }

        return Self.sanitizeSpokenLine(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func enrichPrompt(
        memory: GeneratedSessionMemory,
        digest: SessionDigest,
        bond: Int,
        totalTokens: Int,
        pastSessions: [GeneratedSessionMemory],
        personality explicitPersonality: String?
    ) -> String {
        let personality = explicitPersonality ?? Self.traitDescription(for: totalTokens)
        let bondText = Self.bondDescription(bond)
        let pastBeats = pastSessions.flatMap { $0.narrativeBeats }.suffix(4).joined(separator: " | ")
        let relationshipNote = pastSessions.compactMap { $0.relationshipNote }.last ?? ""

        var parts: [String] = [
            "NPC personality: \(personality)",
            "Bond \(bond)/10 — \(bondText)",
        ]
        if !relationshipNote.isEmpty { parts.append("Relationship: \(relationshipNote)") }
        if !pastBeats.isEmpty { parts.append("Past themes: \(pastBeats)") }
        parts.append("Project: \(digest.project)")
        if let branch = digest.branch { parts.append("Branch: \(branch)") }
        if !digest.recentUserAsks.isEmpty { parts.append("Recent asks: \(digest.recentUserAsks.joined(separator: " | "))") }
        if !digest.files.isEmpty { parts.append("Files: \(digest.files.joined(separator: ", "))") }
        if !digest.commands.isEmpty { parts.append("Commands: \(digest.commands.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }

    private func livePrompt(digest: SessionDigest, bond: Int, totalTokens: Int, personality explicitPersonality: String?) -> String {
        let personality = explicitPersonality ?? Self.traitDescription(for: totalTokens)
        let bondText = Self.bondDescription(bond)
        var parts: [String] = [
            "You are: \(personality), \(bondText) with the player.",
            "Project: \(digest.project)\(digest.branch.map { " (\($0))" } ?? "")",
        ]
        if let ask = digest.recentUserAsks.first, !ask.isEmpty {
            parts.append("Player just asked: \"\(ask)\"")
        }
        if let file = digest.files.first {
            parts.append("Current file: \(file)")
        }
        return parts.joined(separator: "\n")
    }

    static func traitDescription(for totalTokens: Int) -> String {
        switch totalTokens {
        case ..<10_000:  return "a fresh, curious newcomer"
        case ..<50_000:  return "steady and reliable, growing in confidence"
        case ..<200_000: return "a deep thinker, intensely focused and methodical"
        default:         return "a seasoned expert, powerful and efficient"
        }
    }

    private func personalityInstruction(_ personality: String?) -> String {
        guard let personality, !personality.isEmpty else { return "" }
        return "Fixed personality: \(personality)"
    }

    static func bondDescription(_ bond: Int) -> String {
        switch bond {
        case 0...2: return "barely knows you"
        case 3...5: return "warming up, trust is forming"
        case 6...8: return "genuinely familiar, emotionally connected"
        default:    return "deeply bonded, feels like a true collaborator"
        }
    }

    static func sanitizeSpokenLine(_ raw: String, maxLength: Int = 75) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else { return collapsed }
        let clipped = collapsed.prefix(maxLength)
        if let lastSpace = clipped.lastIndex(of: " ") {
            return clipped[clipped.startIndex..<lastSpace].trimmingCharacters(in: .whitespaces) + "…"
        }
        return clipped + "…"
    }

    static func stripCodeFence(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        s.removeFirst(3)
        if let newline = s.firstIndex(of: "\n") {
            let firstLine = s[s.startIndex..<newline].trimmingCharacters(in: .whitespaces)
            if firstLine.isEmpty || firstLine.allSatisfy({ $0.isLetter }) {
                s = String(s[s.index(after: newline)...])
            }
        }
        if let fenceEnd = s.range(of: "```", options: .backwards) {
            s = String(s[s.startIndex..<fenceEnd.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func outputText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = object["output_text"] as? String { return text }
        guard let output = object["output"] as? [[String: Any]] else { return nil }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String { return text }
            }
        }
        return nil
    }
}

enum OpenAIAPIKeyStore {
    private static let service = "com.mchau.nook.openai"
    private static let account = "api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        var insert = query
        insert[kSecValueData as String] = data
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        if insertStatus != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(insertStatus)) }
    }
}
