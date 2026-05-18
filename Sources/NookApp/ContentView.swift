import SwiftUI
import SpriteKit

struct ContentView: View {
    @Environment(VillageEngine.self) private var engine
    @State private var scene: VillageScene?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let scene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // HUD overlay — SwiftUI is more reliable than SKCameraNode children on macOS
            Text("⬡ \(engine.totalBits, specifier: "%.1f") Bits")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .cornerRadius(4)
                .padding(16)
        }
        .onAppear {
            guard scene == nil else { return }
            engine.start()  // start before scene creation so totalBits is populated on first frame
            let s = VillageScene(size: CGSize(width: TileMap.mapWidth, height: TileMap.mapHeight))
            s.configure(engine: engine)
            scene = s
        }
    }
}
