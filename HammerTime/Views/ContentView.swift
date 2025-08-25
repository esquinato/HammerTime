import SwiftUI
import RealityKit

struct ContentView: View {
    @State private var immersiveSpaceIsShown = false
    
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.dismissWindow) var dismissWindow
    @EnvironmentObject var model: EntityModel
    
    func startGame() async {
        do {
            try await openImmersiveSpace(id: "GameInteraction")
            immersiveSpaceIsShown = true
            model.isPlaying = true
            dismissWindow(id: "content")
        } catch {
            print("Error opening immersive space: \(error)")
        }
    }
    
    func stopGame() async {
        await dismissImmersiveSpace()
        immersiveSpaceIsShown = false
        model.isPlaying = false
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Hammer Time")
                .font(.largeTitle)
                .padding(.bottom, 20)
            
            // Hammer selection buttons
            VStack(spacing: 15) {
                Text("Select Hammer Type")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    ForEach(HammerType.allCases, id: \.self) { hammerType in
                        Button(action: {
                            model.selectedHammerType = hammerType
                        }) {
                            VStack {
                                Text(hammerIcon(for: hammerType))
                                    .font(.system(size: 40))
                                Text(hammerName(for: hammerType))
                                    .font(.caption)
                            }
                            .frame(width: 80, height: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(model.selectedHammerType == hammerType ? Color.blue.opacity(0.3) : Color.gray.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(model.selectedHammerType == hammerType ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(15)
            
            Button(action: {
                Task {
                    if immersiveSpaceIsShown {
                        await stopGame()
                    } else {
                        await startGame()
                    }
                }
            }) {
                Text(immersiveSpaceIsShown ? "STOP" : "START")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
                    .background(immersiveSpaceIsShown ? Color.red : Color.blue)
                    .cornerRadius(15)
            }
            .buttonStyle(.plain)
            .hoverEffect()
        }
        .frame(minWidth: 500, minHeight: 400)
        .padding()
    }
    
    private func hammerIcon(for type: HammerType) -> String {
        switch type {
        case .step: return "🔨"
        case .wood: return "🪵"
        case .iron: return "⚒️"
        }
    }
    
    private func hammerName(for type: HammerType) -> String {
        switch type {
        case .step: return "Step"
        case .wood: return "Wood"
        case .iron: return "Iron"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(EntityModel())
}
