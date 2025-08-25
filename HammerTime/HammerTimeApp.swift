import SwiftUI

@main
struct AegisCoreApp: App {
    @StateObject private var model = EntityModel()
    
    var body: some Scene {
        WindowGroup(id: "content") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .defaultSize(CGSize(width: 600, height: 400))
        
        ImmersiveSpace(id: "GameInteraction") {
            GameInteraction()
                .environmentObject(model)
        }
    }
}