import ARKit
import RealityKit
import SwiftUI

enum HammerType: String, CaseIterable {
    case step = "hammer_step"
    case wood = "hammer_wood"
    case iron = "hammer_iron"
}

/// A model type that holds app state and processes updates from ARKit.
@MainActor
class EntityModel: ObservableObject {
    let session = ARKitSession()
    var handTracking = HandTrackingProvider()
    var sceneReconstruction = SceneReconstructionProvider()
    var worldTracking = WorldTrackingProvider()
    @Published var contentEntity = Entity()
    @Published var meshEntities = [UUID: ModelEntity]()
    
    // Hand tracking states
    @Published var leftFistDetected = false
    @Published var rightFistDetected = false
    @Published var isPlaying = false
    
    // Hammer states
    @Published var selectedHammerType: HammerType = .step
    private var leftHammer: ModelEntity?
    private var rightHammer: ModelEntity?
    private var leftHandAnchor: HandAnchor?
    private var rightHandAnchor: HandAnchor?
    
    // Velocity tracking
    private struct VelocityFrame {
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let timestamp: TimeInterval
    }
    private var leftHandHistory: [VelocityFrame] = []
    private var rightHandHistory: [VelocityFrame] = []
    private let maxHistoryFrames = 20 // Increased for smoother velocity calculation
    private let maxLinearVelocity: Float = 15.0 // Realistic throwing speed in m/s
    private let maxAngularVelocity: Float = 3 * .pi // 1.5 rotations per second (in radians)
    
    func setupContentEntity() -> Entity {
        return contentEntity
    }
    
    func runARKitSession() async {
        do {
            try await session.run([handTracking, sceneReconstruction, worldTracking])
        } catch {
            print("Failed to start ARKit session: \(error)")
        }
    }
    
    private func checkForFist(handAnchor: HandAnchor, chirality: HandAnchor.Chirality) -> Bool {
        // Only process if this hand matches the requested chirality
        guard handAnchor.chirality == chirality,
              let skeleton = handAnchor.handSkeleton else {
            return false
        }
        
        // Get finger joints
        let middleTip = skeleton.joint(.middleFingerTip)
        let ringTip = skeleton.joint(.ringFingerTip)
        let littleTip = skeleton.joint(.littleFingerTip)
        let palmBase = skeleton.joint(.wrist)
        
        // Check if joints are tracked
        guard middleTip.isTracked &&
              ringTip.isTracked &&
              littleTip.isTracked &&
              palmBase.isTracked else {
            print("\(chirality) hand: Not all joints are tracked")
            return false
        }
        
        // Convert palm position to world space
        let worldPalmTransform = handAnchor.originFromAnchorTransform * palmBase.anchorFromJointTransform
        let palmPosition = SIMD3<Float>(worldPalmTransform.columns.3.x,
                                      worldPalmTransform.columns.3.y,
                                      worldPalmTransform.columns.3.z)
        
        let fingerTips = [middleTip, ringTip, littleTip]
        let maxDistance: Float = 0.10  // Reduced from 0.15 for tighter fist detection
        
        // Check if all finger tips are close to palm
        let isFist = fingerTips.allSatisfy { tip in
            let worldTipTransform = handAnchor.originFromAnchorTransform * tip.anchorFromJointTransform
            let tipPosition = SIMD3<Float>(worldTipTransform.columns.3.x,
                                         worldTipTransform.columns.3.y,
                                         worldTipTransform.columns.3.z)
            return simd_distance(tipPosition, palmPosition) < maxDistance
        }
        
        return isFist
    }
    
    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor
            
            switch handAnchor.chirality {
            case .left:
                leftHandAnchor = handAnchor
                let wasFistDetected = leftFistDetected
                leftFistDetected = checkForFist(handAnchor: handAnchor, chirality: .left)
                
                // Handle hammer spawning/despawning for left hand
                if leftFistDetected && !wasFistDetected {
                    // Fist just made - spawn hammer
                    await spawnHammer(for: .left, handAnchor: handAnchor)
                } else if !leftFistDetected && wasFistDetected {
                    // Fist just released - drop hammer
                    dropHammer(for: .left)
                } else if leftFistDetected && leftHammer != nil {
                    // Update hammer position while fist is maintained
                    updateHammerPosition(for: .left, handAnchor: handAnchor)
                }
                
            case .right:
                rightHandAnchor = handAnchor
                let wasFistDetected = rightFistDetected
                rightFistDetected = checkForFist(handAnchor: handAnchor, chirality: .right)
                
                // Handle hammer spawning/despawning for right hand
                if rightFistDetected && !wasFistDetected {
                    // Fist just made - spawn hammer
                    await spawnHammer(for: .right, handAnchor: handAnchor)
                } else if !rightFistDetected && wasFistDetected {
                    // Fist just released - drop hammer
                    dropHammer(for: .right)
                } else if rightFistDetected && rightHammer != nil {
                    // Update hammer position while fist is maintained
                    updateHammerPosition(for: .right, handAnchor: handAnchor)
                }
            }
        }
    }
    
    func processSceneReconstruction() async {
        for await update in sceneReconstruction.anchorUpdates {
            switch update.event {
            case .added:
                let meshAnchor = update.anchor
                
                // Create mesh from the anchor
                guard let meshResource = try? await MeshResource(from: meshAnchor) else { continue }
                
                // Create a semi-transparent material
                var material = SimpleMaterial()
                material.color = .init(tint: .gray.withAlphaComponent(0.3))
                material.roughness = 0.5
                material.metallic = 0.1
                
                let meshEntity = ModelEntity(mesh: meshResource, materials: [material])
                meshEntity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                meshEntity.name = "SceneMesh"
                
                // Generate collision shape with error handling
                if let collisionShape = try? await ShapeResource.generateConvex(from: meshResource) {
                    meshEntity.components.set(CollisionComponent(shapes: [collisionShape], isStatic: true))
                    meshEntity.components.set(PhysicsBodyComponent(mode: .static))
                }
                
                meshEntities[meshAnchor.id] = meshEntity
                contentEntity.addChild(meshEntity)
                
            case .updated:
                guard let meshEntity = meshEntities[update.anchor.id] else { continue }
                meshEntity.transform = Transform(matrix: update.anchor.originFromAnchorTransform)
                
            case .removed:
                guard let meshEntity = meshEntities[update.anchor.id] else { continue }
                meshEntity.removeFromParent()
                meshEntities.removeValue(forKey: update.anchor.id)
            }
        }
    }
    
    // MARK: - Hammer Management
    
    private func spawnHammer(for chirality: HandAnchor.Chirality, handAnchor: HandAnchor) async {
        // Load the hammer model
        guard let hammerModel = try? await ModelEntity(named: selectedHammerType.rawValue) else {
            print("Failed to load hammer model: \(selectedHammerType.rawValue)")
            return
        }
        
        // Configure hammer
        hammerModel.name = "Hammer_\(chirality)"
        
        // Debug: Print the actual scale
        print("Hammer spawned with scale: \(hammerModel.scale)")
        
        // Add to scene
        contentEntity.addChild(hammerModel)
        
        // Store reference
        switch chirality {
        case .left:
            leftHammer = hammerModel
        case .right:
            rightHammer = hammerModel
        }
    }
    
    private func updateHammerPosition(for chirality: HandAnchor.Chirality, handAnchor: HandAnchor) {
        let hammer: ModelEntity?
        switch chirality {
        case .left:
            hammer = leftHammer
        case .right:
            hammer = rightHammer
        }
        
        guard let hammer = hammer else { return }
        
        // Update hammer position to follow hand while maintaining scale
        guard let skeleton = handAnchor.handSkeleton else { return }
        
        // Get key joints for grip positioning
        let indexKnuckle = skeleton.joint(.indexFingerMetacarpal)
        let middleKnuckle = skeleton.joint(.middleFingerMetacarpal)
        let palmBase = skeleton.joint(.middleFingerKnuckle)
        
        // Ensure joints are tracked
        guard indexKnuckle.isTracked &&
              middleKnuckle.isTracked &&
              palmBase.isTracked else { return }
        
        // Calculate grip center - average between palm and knuckles
        let indexTransform = handAnchor.originFromAnchorTransform * indexKnuckle.anchorFromJointTransform
        let middleTransform = handAnchor.originFromAnchorTransform * middleKnuckle.anchorFromJointTransform
        let palmTransform = handAnchor.originFromAnchorTransform * palmBase.anchorFromJointTransform
        
        // Get positions
        let indexPos = SIMD3<Float>(indexTransform.columns.3.x, indexTransform.columns.3.y, indexTransform.columns.3.z)
        let middlePos = SIMD3<Float>(middleTransform.columns.3.x, middleTransform.columns.3.y, middleTransform.columns.3.z)
        let palmPos = SIMD3<Float>(palmTransform.columns.3.x, palmTransform.columns.3.y, palmTransform.columns.3.z)
        
        // Calculate grip center point
        let gripCenter = (indexPos + middlePos + palmPos) / 3.0
        
        // Create a parent entity to act as the pivot point
        if hammer.parent == nil || hammer.parent?.name != "HammerPivot_\(chirality)" {
            // Create pivot entity at grip position
            let pivotEntity = Entity()
            pivotEntity.name = "HammerPivot_\(chirality)"
            pivotEntity.position = gripCenter
            
            // Remove hammer from content and add to pivot
            hammer.removeFromParent()
            pivotEntity.addChild(hammer)
            contentEntity.addChild(pivotEntity)
            
            // Offset hammer so handle is at pivot point (adjust this value based on your model)
            // Negative Y moves the hammer up so the handle is at the grip point
            hammer.position = SIMD3<Float>(0, 0.15, 0) // Adjust this to match where the handle is on your model
            hammer.scale = SIMD3<Float>(repeating: 0.009)
        }
        
        // Update pivot position and rotation
        if let pivotEntity = hammer.parent {
            pivotEntity.position = gripCenter
            
            // Use hand orientation from the palm for rotation
            let handRotation = simd_quatf(palmTransform)
            pivotEntity.orientation = handRotation
            
            // Track velocity history
            let currentTime = CACurrentMediaTime()
            let frame = VelocityFrame(
                position: gripCenter,
                rotation: handRotation,
                timestamp: currentTime
            )
            
            switch chirality {
            case .left:
                leftHandHistory.append(frame)
                if leftHandHistory.count > maxHistoryFrames {
                    leftHandHistory.removeFirst()
                }
            case .right:
                rightHandHistory.append(frame)
                if rightHandHistory.count > maxHistoryFrames {
                    rightHandHistory.removeFirst()
                }
            }
        }
    }
    
    private func dropHammer(for chirality: HandAnchor.Chirality) {
        let hammer: ModelEntity?
        switch chirality {
        case .left:
            hammer = leftHammer
            leftHammer = nil
        case .right:
            hammer = rightHammer
            rightHammer = nil
        }
        
        guard let hammer = hammer, let pivotEntity = hammer.parent else { return }
        
        // Calculate final velocity before detaching
        let history = chirality == .left ? leftHandHistory : rightHandHistory
        var linearVelocity = SIMD3<Float>.zero
        var angularVelocity = SIMD3<Float>.zero
        
        if history.count >= 2 {
            // At 90 FPS, we need to sample over more frames to get accurate velocity
            // Using frames that are further apart to avoid noise from tiny movements
            let sampleSpacing = 3 // Sample every 3rd frame (~33ms apart at 90fps)
            var totalVelocity = SIMD3<Float>.zero
            var velocitySamples = 0
            
            // Calculate velocity using spaced samples
            let samplesToUse = min(3, (history.count - 1) / sampleSpacing)
            for i in 0..<samplesToUse {
                let olderIndex = history.count - (i + 1) * sampleSpacing - 1
                let newerIndex = history.count - i * sampleSpacing - 1
                
                if olderIndex >= 0 && newerIndex < history.count {
                    let older = history[olderIndex]
                    let newer = history[newerIndex]
                    let dt = Float(newer.timestamp - older.timestamp)
                    
                    if dt > 0.02 { // ~2 frames at 90fps minimum
                        let velocity = (newer.position - older.position) / dt
                        totalVelocity += velocity
                        velocitySamples += 1
                    }
                }
            }
            
            if velocitySamples > 0 {
                linearVelocity = totalVelocity / Float(velocitySamples)
                
                // Don't scale up - the velocity should already be accurate
                // linearVelocity *= 2.0 // REMOVED - was making things too fast
                
                // Clamp velocity to maximum
                let speed = length(linearVelocity)
                if speed > maxLinearVelocity {
                    linearVelocity = normalize(linearVelocity) * maxLinearVelocity
                }
                
                print("Throwing with velocity: \(linearVelocity), speed: \(speed) m/s")
            }
            
            // Calculate angular velocity with proper frame spacing
            if history.count >= 6 { // Need more frames for angular velocity
                let olderIndex = max(0, history.count - 6)
                let newerIndex = history.count - 1
                let older = history[olderIndex]
                let newer = history[newerIndex]
                let dt = Float(newer.timestamp - older.timestamp)
                
                if dt > 0.05 { // ~5 frames at 90fps minimum
                    // Calculate rotation difference
                    let rotDiff = newer.rotation * older.rotation.inverse
                    let angle = 2.0 * acos(min(1.0, abs(rotDiff.real)))
                    
                    if angle > 0.05 { // Only apply if there's meaningful rotation
                        let axis = length_squared(rotDiff.imag) > 0.0001 ? normalize(rotDiff.imag) : SIMD3<Float>(0, 1, 0)
                        angularVelocity = axis * (angle / dt) // Don't scale down anymore
                        
                        // Clamp angular velocity
                        let angSpeed = length(angularVelocity)
                        if angSpeed > maxAngularVelocity {
                            angularVelocity = normalize(angularVelocity) * maxAngularVelocity
                        }
                        
                        print("Angular velocity: \(angularVelocity), speed: \(angSpeed) rad/s")
                    }
                }
            }
        }
        
        // Move hammer to world space preserving its exact world position
        let worldPosition = pivotEntity.position(relativeTo: contentEntity)
        let worldOrientation = pivotEntity.orientation(relativeTo: contentEntity)
        
        // Remove from pivot and add to world
        hammer.removeFromParent()
        contentEntity.addChild(hammer)
        
        // Apply the world transform
        hammer.position = worldPosition
        hammer.orientation = worldOrientation
        
        // Remove the pivot entity
        pivotEntity.removeFromParent()
        
        // Create physics components
        Task { @MainActor in
            // Generate collision shape first
            if let mesh = hammer.model?.mesh,
               let shape = try? await ShapeResource.generateConvex(from: mesh) {
                
                // Add collision component
                hammer.components.set(CollisionComponent(shapes: [shape]))
                
                // Add physics body with proper mass
                let physicsBody = PhysicsBodyComponent(
                    massProperties: .init(mass: 0.5), // Lighter hammer for better throwing
                    material: .generate(friction: 0.6, restitution: 0.3),
                    mode: .dynamic
                )
                hammer.components.set(physicsBody)
                
                // Apply velocities after physics is set up
                if length(linearVelocity) > 0.1 {
                    // Apply impulse (impulse = mass * velocity)
                    let impulse = linearVelocity * 0.5 // mass
                    hammer.applyLinearImpulse(impulse, relativeTo: nil)
                }
                
                if length(angularVelocity) > 0.1 {
                    // Apply angular impulse
                    let angularImpulse = angularVelocity * 0.05 // Scaled for inertia
                    hammer.applyAngularImpulse(angularImpulse, relativeTo: nil)
                }
            } else {
                print("Failed to create collision shape for hammer")
            }
        }
        
        // Clear history for this hand
        switch chirality {
        case .left:
            leftHandHistory.removeAll()
        case .right:
            rightHandHistory.removeAll()
        }
    }
}
