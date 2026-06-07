import Foundation
import Security

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

    @MainActor
    func enrich(sessionMemory: GeneratedSessionMemory, digest: SessionDigest, bond: Int) async throws -> GeneratedSessionMemory {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_output_tokens": 350,
            // json_object guarantees raw, parseable JSON — without it the model
            // wraps output in a ```json fence that breaks JSONSerialization.
            "text": ["format": ["type": "json_object"]],
            "instructions": "Return compact JSON for an emotionally warm NPC memory. Keys: title, shortSummary, narrativeBeats, relationshipNote, cachedLines. Title must be 'Theme · Project'. Each cachedLines entry must be a single spoken sentence under 80 characters, the kind of short line the NPC says aloud in a speech bubble.",
            "input": prompt(memory: sessionMemory, digest: digest, bond: bond)
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

    private func prompt(memory: GeneratedSessionMemory, digest: SessionDigest, bond: Int) -> String {
        """
        Respond as raw JSON only.
        Existing title: \(memory.title)
        Project: \(digest.project)
        Branch: \(digest.branch ?? "unknown")
        Bond: \(bond)
        Recent asks: \(digest.recentUserAsks.joined(separator: " | "))
        Files: \(digest.files.joined(separator: ", "))
        Commands: \(digest.commands.joined(separator: ", "))
        Tools: \(digest.tools.joined(separator: ", "))
        """
    }

    /// Keep spoken lines short and single-line so they fit a speech bubble even
    /// if the model ignores the length instruction. Caps at ~90 chars on a word
    /// boundary so the bubble's safety-net truncation rarely triggers.
    static func sanitizeSpokenLine(_ raw: String, maxLength: Int = 90) -> String {
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

    /// Defensively unwrap a ```json … ``` (or bare ```) fence the model may emit
    /// despite json_object mode, returning the inner JSON text.
    static func stripCodeFence(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        s.removeFirst(3)
        if let newline = s.firstIndex(of: "\n") {
            // Drop an optional language tag on the first fence line (e.g. "json").
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
