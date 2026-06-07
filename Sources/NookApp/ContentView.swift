import SwiftUI
import SpriteKit

struct ContentView: View {
    @Environment(VillageEngine.self) private var engine
    @State private var scene: VillageScene?
    @State private var selectedNPC: NPCSelection?
    @State private var localVillageAssetsAvailable = true
    @State private var isShopOpen = false
    @State private var shopAgentID: String?
    @State private var isAPIKeyOpen = false
    @State private var apiKeyDraft = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Day/night overlay
            Rectangle()
                .fill(engine.dayPhase.overlayColor)
                .opacity(engine.dayPhase.overlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 30), value: engine.dayPhase)

            // HUD overlay — SwiftUI is more reliable than SKCameraNode children on macOS
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    PixelIcon(kind: .bit, size: 14)
                    Text("\(engine.totalAvailableBits, specifier: "%.1f") Bits")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Button {
                    shopAgentID = defaultShopAgentID
                    isShopOpen = true
                } label: {
                    Image(systemName: "cart")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(isShopOpen ? .white.opacity(0.26) : .white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .disabled(engine.agents.isEmpty)
                .help("Bit Multiplier shop")

                Button {
                    apiKeyDraft = OpenAIAPIKeyStore.load() ?? ""
                    isAPIKeyOpen = true
                } label: {
                    Image(systemName: isAPIKeyOpen || OpenAIAPIKeyStore.load() != nil ? "key.fill" : "key")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenAIAPIKeyStore.load() != nil ? Color(red: 0.52, green: 0.92, blue: 0.62) : .white)
                .background(isAPIKeyOpen ? .white.opacity(0.26) : .white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .help("OpenAI API key")
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .cornerRadius(4)
                .padding(16)

            if isShopOpen {
                HStack {
                    UpgradeShopPanel(
                        selectedAgentID: shopAgentID,
                        activeAgentIDs: activeShopAgentIDs,
                        onSelectAgent: { shopAgentID = $0 },
                        onPurchase: { id in engine.requestBitMultiplierPurchase(for: id) },
                        onPurchaseBondDividend: { id in engine.requestBondDividendPurchase(for: id) },
                        onPurchaseTrickle: { id in engine.requestTricklePurchase(for: id) },
                        availableBits: { engine.availableBits(for: $0) },
                        nextCost: { engine.nextBitMultiplierCost(for: $0) },
                        nextBondDividendCost: { engine.nextBondDividendCost(for: $0) },
                        nextTrickleCost: { engine.nextTrickleCost(for: $0) },
                        upgradeState: engine.upgrades,
                        agents: engine.agents,
                        onClose: { isShopOpen = false }
                    )
                    Spacer()
                }
                .padding(.top, 58)
                .padding(.leading, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isAPIKeyOpen {
                HStack {
                    APIKeyPanel(
                        key: $apiKeyDraft,
                        onSave: {
                            try? OpenAIAPIKeyStore.save(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            isAPIKeyOpen = false
                        },
                        onClose: { isAPIKeyOpen = false }
                    )
                    Spacer()
                }
                .padding(.top, isShopOpen ? 250 : 58)
                .padding(.leading, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !localVillageAssetsAvailable {
                HStack {
                    Spacer()
                    Text("Local village assets missing")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62))
                        .cornerRadius(4)
                }
                .padding(16)
                .allowsHitTesting(false)
            }

            if let selectedNPC {
                HStack {
                    Spacer()
                    NPCInspectorPanel(selection: selectedNPC) {
                        self.selectedNPC = nil
                        scene?.clearSelection()
                    }
                }
                .padding(.vertical, 16)
                .padding(.trailing, 16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: selectedNPC)
        .animation(.easeOut(duration: 0.16), value: isShopOpen)
        .animation(.easeOut(duration: 0.16), value: isAPIKeyOpen)
        .onAppear {
            guard scene == nil else { return }
            engine.start()  // start before scene creation so totalBits is populated on first frame
            let s = VillageScene(size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight))
            s.onNPCSelection = { selection in
                selectedNPC = selection
            }
            s.onLocalAssetAvailability = { available in
                localVillageAssetsAvailable = available
            }
            s.configure(engine: engine)
            scene = s
        }
    }

    private var activeShopAgentIDs: [String] {
        engine.activeSessionCounts
            .filter { $0.value > 0 && engine.agents[$0.key] != nil }
            .keys
            .sorted()
    }

    private var defaultShopAgentID: String? {
        if let selectedNPC { return selectedNPC.id }
        if activeShopAgentIDs.count == 1 { return activeShopAgentIDs[0] }
        return activeShopAgentIDs.first ?? engine.agents.keys.sorted().first
    }
}

private struct APIKeyPanel: View {
    @Binding var key: String
    let onSave: () -> Void
    let onClose: () -> Void
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OpenAI")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }

            SecureField("API key", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .padding(8)
                .background(.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Button {
                onSave()
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onClose() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saved ? "checkmark.circle.fill" : "checkmark.circle")
                    Text(saved ? "Saved!" : "Save")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)
            .foregroundStyle(.black)
            .background(saved ? Color(red: 0.38, green: 0.80, blue: 0.48) : Color(red: 0.52, green: 0.92, blue: 0.62))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saved)
            .animation(.easeOut(duration: 0.15), value: saved)
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 300)
        .background(.black.opacity(0.78))
        .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

private struct UpgradeShopPanel: View {
    let selectedAgentID: String?
    let activeAgentIDs: [String]
    let onSelectAgent: (String) -> Void
    let onPurchase: (String) -> Void
    let onPurchaseBondDividend: (String) -> Void
    let onPurchaseTrickle: (String) -> Void
    let availableBits: (String) -> Double
    let nextCost: (String) -> Double
    let nextBondDividendCost: (String) -> Double
    let nextTrickleCost: (String) -> Double
    let upgradeState: UpgradeState
    let agents: [String: AgentRecord]
    let onClose: () -> Void

    @State private var purchaseFlash: UpgradeKind? = nil

    private var allAgentIDs: [String] { agents.keys.sorted() }

    private var currentID: String? {
        if let id = selectedAgentID, agents[id] != nil { return id }
        return activeAgentIDs.first ?? allAgentIDs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shop")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
            }

            if allAgentIDs.count > 1 { npcSelector }

            if let id = currentID, let agent = agents[id] {
                let state = upgradeState.agents[id] ?? AgentUpgradeState()
                let balance = availableBits(id)
                let isActive = activeAgentIDs.contains(id)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        // NPC header
                        HStack(spacing: 6) {
                            Text(agent.name)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            if isActive { Circle().fill(Color.green).frame(width: 6, height: 6) }
                        }

                        // Balance block
                        VStack(alignment: .leading, spacing: 4) {
                            captionLabel("Available bits")
                            HStack {
                                PixelIcon(kind: .bit, size: 11)
                                Text(formatBits(balance))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                Spacer()
                            }
                        }
                        .padding(8)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        // ── Bit Multiplier ──
                        upgradeSection(
                            title: "Bit multiplier",
                            subtitle: nil,
                            currentValue: String(format: "%.2fx", state.bitMultiplier),
                            nextValue: String(format: "%.2fx", state.bitMultiplier + 0.25),
                            cost: nextCost(id),
                            balance: balance,
                            kind: .bitMultiplier,
                            buyLabel: "Buy +0.25×"
                        ) { onPurchase(id) }

                        // ── Bond Dividend ──
                        let bdCost = nextBondDividendCost(id)
                        let bdMult = UpgradeEconomy.bondDividendMultiplier(level: state.bondDividendLevel, bond: agent.bond)
                        let bdNextMult = UpgradeEconomy.bondDividendMultiplier(level: state.bondDividendLevel + 1, bond: agent.bond)
                        upgradeSection(
                            title: "Bond dividend",
                            subtitle: "Bond \(agent.bond) · scales with bond",
                            currentValue: state.bondDividendLevel == 0 ? "Locked" : formatMultiplier(bdMult),
                            nextValue: bdCost < .infinity ? formatMultiplier(bdNextMult) : nil,
                            cost: bdCost,
                            balance: balance,
                            kind: .bondDividend,
                            buyLabel: state.bondDividendLevel == 0 ? "Unlock" : "Upgrade"
                        ) { onPurchaseBondDividend(id) }

                        // ── Bit Trickle ──
                        let tCount = state.trickleLevel
                        let tCost = nextTrickleCost(id)
                        let tRate = UpgradeEconomy.trickleRate(count: tCount)
                        let tNextRate = UpgradeEconomy.trickleRate(count: tCount + 1)
                        upgradeSection(
                            title: "Bit trickle",
                            subtitle: tCount == 0 ? "×0 units" : "×\(tCount) unit\(tCount == 1 ? "" : "s") · \(formatTrickleRate(tRate))",
                            currentValue: tCount == 0 ? "Locked" : formatTrickleRate(tRate),
                            nextValue: formatTrickleRate(tNextRate),
                            cost: tCost,
                            balance: balance,
                            kind: .trickle,
                            buyLabel: "+1 trickle"
                        ) { onPurchaseTrickle(id) }
                    }
                }
                .frame(maxHeight: 420)
            } else {
                Text("No NPCs")
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 268)
        .background(.black.opacity(0.78))
        .overlay(Rectangle().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func upgradeSection(
        title: String,
        subtitle: String?,
        currentValue: String,
        nextValue: String?,
        cost: Double,
        balance: Double,
        kind: UpgradeKind,
        buyLabel: String,
        onBuy: @escaping () -> Void
    ) -> some View {
        let isMaxed = cost == .infinity
        let isFlashing = purchaseFlash == kind
        let canBuy = !isMaxed && balance >= cost && !isFlashing

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                captionLabel(title)
                Spacer()
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.30))
                }
            }

            HStack(spacing: 8) {
                Text(currentValue)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                if let nv = nextValue {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.40))
                    Text(nv)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(canBuy ? Color(red: 0.52, green: 0.92, blue: 0.62) : .white.opacity(0.30))
                }
                Spacer()
            }

            if isMaxed {
                Text("Max level")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Button {
                    onBuy()
                    purchaseFlash = kind
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if purchaseFlash == kind { purchaseFlash = nil }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isFlashing ? "checkmark.circle.fill" : "arrow.up.circle")
                        Text(isFlashing ? "Purchased!" : "\(buyLabel) — \(formatBits(cost)) Bits")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .foregroundStyle(canBuy ? .black : .white.opacity(0.35))
                .background(canBuy ? Color(red: 0.52, green: 0.92, blue: 0.62) : .white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .disabled(!canBuy)
                .animation(.easeOut(duration: 0.15), value: isFlashing)

                if balance < cost && !isFlashing {
                    Text("Need \(formatBits(cost - balance)) more bits")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.35).opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(8)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var npcSelector: some View {
        VStack(alignment: .leading, spacing: 4) {
            captionLabel("NPC")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allAgentIDs, id: \.self) { id in
                        let isSelected = id == currentID
                        let isActive = activeAgentIDs.contains(id)
                        Button { onSelectAgent(id) } label: {
                            HStack(spacing: 4) {
                                if isActive { Circle().fill(Color.green).frame(width: 5, height: 5) }
                                Text(agents[id]?.name ?? id)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color(red: 0.52, green: 0.92, blue: 0.62).opacity(0.25) : .white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                                isSelected ? Color(red: 0.52, green: 0.92, blue: 0.62).opacity(0.6) : Color.clear,
                                lineWidth: 1
                            ))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(isSelected ? Color(red: 0.52, green: 0.92, blue: 0.62) : .white)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    private func captionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.40))
    }

    private func formatBits(_ bits: Double) -> String {
        if bits >= 1_000_000 { return String(format: "%.1fM", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.1fk", bits / 1_000) }
        if bits >= 10 { return String(format: "%.0f", bits) }
        return String(format: "%.1f", bits)
    }

    private func formatRate(_ rate: Double) -> String {
        if rate == 0 { return "0 b/hr" }
        if rate >= 10 { return String(format: "%.0f b/hr", rate) }
        return String(format: "%.1f b/hr", rate)
    }

    private func formatMultiplier(_ value: Double) -> String {
        String(format: "%.2fx", value)
    }

    private func formatTrickleRate(_ rate: Double) -> String {
        if rate == rate.rounded(), rate >= 1 {
            return "\(Int(rate)) b/10s"
        }
        return String(format: "%.1f b/10s", rate)
    }
}
