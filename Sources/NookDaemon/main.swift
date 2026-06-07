import Foundation

setbuf(stdout, nil)  // unbuffered output so log file is written immediately
print("[NookDaemon] Starting Nook background daemon...")

let ledger = Ledger.production
var state = ledger.load()
let economy = EconomyReader.production

let watcher = ClaudeWatcher(
    onEvent: { event, agentName in
        let multiplier = economy.multiplier(for: agentName)
        ledger.apply(event: event, agentName: agentName, multiplier: multiplier, to: &state)
        do {
            try ledger.save(state)
            let bits = String(format: "%.1f", event.bits * multiplier)
            let agent = agentName ?? "global"
            print("[NookDaemon] +\(bits) Bits → \(agent) | Total: \(String(format: "%.1f", state.totalBits))")
        } catch {
            print("[NookDaemon] Failed to save ledger: \(error)")
        }
    },
    onSubject: { entry, sessionId, projectPath, agentName in
        ledger.ingestSubject(entry: entry, sessionId: sessionId, projectPath: projectPath, agentName: agentName, to: &state)
        try? ledger.save(state)
    }
)

watcher.start()
RunLoop.main.run()
