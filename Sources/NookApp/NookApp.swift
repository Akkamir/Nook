import SwiftUI
import SpriteKit

@main
struct NookApp: App {
    @State private var engine = VillageEngine()

    var body: some Scene {
        WindowGroup("Nook") {
            ContentView()
                .environment(engine)
                .frame(minWidth: 1024, minHeight: 768)
                .onAppear { engine.start() }
                .onDisappear { engine.stop() }
        }
    }
}
