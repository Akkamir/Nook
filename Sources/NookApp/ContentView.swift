import SwiftUI
import SpriteKit

struct ContentView: View {
    @Environment(VillageEngine.self) private var engine

    private let scene: SKScene = {
        let s = SKScene(size: CGSize(width: 1280, height: 800))
        s.backgroundColor = .init(red: 0.35, green: 0.56, blue: 0.24, alpha: 1) // green placeholder
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
            Text("⬡ \(engine.totalBits, specifier: "%.1f") Bits")
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
                .padding()
        }
    }
}
