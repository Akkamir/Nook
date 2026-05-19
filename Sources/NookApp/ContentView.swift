import SwiftUI
import SpriteKit

struct ContentView: View {
    @Environment(VillageEngine.self) private var engine
    @State private var scene: VillageScene?
    @State private var selectedNPC: NPCSelection?

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
            Text("⬡ \(engine.totalBits, specifier: "%.1f") Bits")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .cornerRadius(4)
                .padding(16)
                .allowsHitTesting(false)

            if let selectedNPC {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedNPC.name)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    Text("Bond \(selectedNPC.bond)")
                    Text("\(selectedNPC.totalTokens) tokens")
                    Text("\(selectedNPC.totalBits, specifier: "%.1f") Bits")
                    Text(selectedNPC.activeSessionCount > 0 ? "\(selectedNPC.activeSessionCount) active session(s)" : "Idle")
                    Text(selectedNPC.trait.rawValue)
                }
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.72))
                .cornerRadius(4)
                .padding(.top, 56)
                .padding(.leading, 16)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard scene == nil else { return }
            engine.start()  // start before scene creation so totalBits is populated on first frame
            let s = VillageScene(size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight))
            s.configure(engine: engine)
            s.onNPCSelection = { selection in
                selectedNPC = selection
            }
            scene = s
        }
    }
}
