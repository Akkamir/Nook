import Foundation

setbuf(stdout, nil)  // unbuffered output so log file is written immediately
print("[NookDaemon] Starting Nook background daemon...")

let ledger = Ledger.production
var state = ledger.load()

let watcher = ClaudeWatcher(
    onEvent: { event, agentName in
        ledger.apply(event: event, agentName: agentName, to: &state)
        do {
            try ledger.save(state)
            let bits = String(format: "%.1f", event.bits)
            let agent = agentName ?? "global"
            print("[NookDaemon] +\(bits) raw Bits → \(agent) | Total raw: \(String(format: "%.1f", state.totalBitsRaw))")
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
