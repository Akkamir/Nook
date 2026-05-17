import Foundation

print("[NookDaemon] Starting Nook background daemon...")

let ledger = Ledger.production
var state = ledger.load()

let watcher = ClaudeWatcher { event, agentName in
    ledger.apply(event: event, agentName: agentName, to: &state)
    do {
        try ledger.save(state)
        let bits = String(format: "%.1f", event.bits)
        let agent = agentName ?? "global"
        print("[NookDaemon] +\(bits) Bits → \(agent) | Total: \(String(format: "%.1f", state.totalBits))")
    } catch {
        print("[NookDaemon] Failed to save ledger: \(error)")
    }
}

watcher.start()
RunLoop.main.run()
