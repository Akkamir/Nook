import SwiftUI
import SpriteKit

struct ContentView: View {
    private let scene: SKScene = {
        let s = SKScene(size: CGSize(width: 1280, height: 800))
        s.backgroundColor = .init(red: 0.35, green: 0.56, blue: 0.24, alpha: 1) // green placeholder
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}
