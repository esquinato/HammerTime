import ARKit
import SwiftUI
import RealityKit

struct GameInteraction: View {
    @EnvironmentObject var model: EntityModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        RealityView { content, attachments in
            // Setup the AR content
            content.add(model.setupContentEntity())
            
            // Add a simple debug text attachment
            if let debugAttachment = attachments.entity(for: "debug") {
                debugAttachment.position = [0, 1.5, -1]
                content.add(debugAttachment)
            }
        } update: { content, attachments in
            // Update logic if needed
        } attachments: {
            Attachment(id: "debug") {
                VStack(spacing: 20) {
                    Text("Hammer: \(model.selectedHammerType.rawValue)")
                        .font(.headline)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    
                    HStack(spacing: 30) {
                        VStack {
                            Text("Left Hand")
                                .font(.headline)
                            Circle()
                                .fill(model.leftFistDetected ? Color.green : Color.red)
                                .frame(width: 50, height: 50)
                        }
                        
                        VStack {
                            Text("Right Hand")
                                .font(.headline)
                            Circle()
                                .fill(model.rightFistDetected ? Color.green : Color.red)
                                .frame(width: 50, height: 50)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    
                    // Exit button
                    Button(action: {
                        Task {
                            await dismissImmersiveSpace()
                            openWindow(id: "content")
                        }
                    }) {
                        Text("EXIT")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
            }
        }
        .task {
            // Start AR session
            await model.runARKitSession()
        }
        .task {
            // Start hand tracking updates continuously
            await model.processHandUpdates()
        }
        .task {
            // Start scene reconstruction
            await model.processSceneReconstruction()
        }
        
    }
}

#Preview {
    GameInteraction()
        .environmentObject(EntityModel())
}
