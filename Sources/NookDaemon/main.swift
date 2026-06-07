import Foundation

setbuf(stdout, nil)  // unbuffered output so log file is written immediately
print("[NookDaemon] Starting Nook background daemon...")

let ledger = Ledger.production
var state = ledger.load()
let upgradeStore = UpgradeStore.production
var upgrades = upgradeStore.load()

@MainActor
func processUpgradeRequests() {
    do {
        let results = try upgradeStore.processRequests(ledger: state, upgrades: &upgrades)
        for result in results {
            print("[NookDaemon] Upgrade request: \(result)")
        }
    } catch {
        print("[NookDaemon] Failed to process upgrade requests: \(error)")
    }
}

let watcher = ClaudeWatcher(
    onEvent: { event, agentName in
        processUpgradeRequests()
        ledger.apply(event: event, agentName: agentName, upgrades: upgrades, to: &state)
        do {
            try ledger.save(state)
            let bits = String(format: "%.1f", event.bits * UpgradeEconomy.multiplier(for: agentName, upgrades: upgrades))
            let agent = agentName ?? "global"
            print("[NookDaemon] +\(bits) Bits → \(agent) | Total: \(String(format: "%.1f", state.totalBits))")
        } catch {
            print("[NookDaemon] Failed to save ledger: \(error)")
        }
    },
    onSubject: { entry, sessionId, projectPath, agentName in
        processUpgradeRequests()
        ledger.ingestSubject(entry: entry, sessionId: sessionId, projectPath: projectPath, agentName: agentName, to: &state)
        try? ledger.save(state)
    }
)

watcher.start()
RunLoop.main.run()
