/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Helper functions for converting between ARKit and RealityKit types.
*/

import ARKit
import RealityKit
import SwiftUI


func randomColor() -> UIColor {
    // Generate random values for RGB
    let red = CGFloat.random(in: 0...1)
    let green = CGFloat.random(in: 0...1)
    let blue = CGFloat.random(in: 0...1)
    
    // Return the UIColor
    return UIColor(red: red, green: green, blue: blue, alpha: 1) // alpha set to 1.0 for fully opaque
}

//
//extension ModelEntity {
//    /// Creates an invisible sphere that can interact with dropped cubes in the scene.
//    class func createFingertip() -> ModelEntity {
//        let entity = ModelEntity(
//            mesh: .generateSphere(radius: 0.005),
//            materials: [UnlitMaterial(color: .cyan)],
//            collisionShape: .generateSphere(radius: 0.005),
//            mass: 0.0)
//
//        entity.components.set(PhysicsBodyComponent(mode: .kinematic))
//        entity.components.set(OpacityComponent(opacity: 1.0))
//
//        return entity
//    }
//}



extension EntityModel {
    /// Periodically checks and removes entities whose Z axis is below -1.
    func removeEntitiesBelowYAxis() {
        for entity in contentEntity.children {
            if entity.position.y < -1 {
                contentEntity.removeChild(entity)
            }
        }
    }
}


// Add this extension outside of the EntityModel class
extension GeometrySource {
    @MainActor func asArray<T>(ofType: T.Type) -> [T] {
        assert(MemoryLayout<T>.stride == stride, "Invalid stride \(MemoryLayout<T>.stride); expected \(stride)")
        return (0..<self.count).map {
            buffer.contents().advanced(by: offset + stride * Int($0)).assumingMemoryBound(to: T.self).pointee
        }
    }

    @MainActor func asSIMD3<T>(ofType: T.Type) -> [SIMD3<T>] {
        return asArray(ofType: (T, T, T).self).map { .init($0.0, $0.1, $0.2) }
    }
}



// Add this extension to Entity to provide the forward direction
extension Entity {
    var forward: SIMD3<Float> {
        SIMD3<Float>(transform.matrix.columns.2.x,
                     transform.matrix.columns.2.y,
                     transform.matrix.columns.2.z)
    }
}

// Add these color definitions
extension UIColor {
    static let blue = UIColor.blue
    static let cyan = UIColor.cyan
    static let white = UIColor.white
    static let green = UIColor.green
}

// Add this extension to help with entity finding
extension Entity {
    func findEntity(named name: String) -> Entity? {
        if self.name == name {
            return self
        }
        
        for child in children {
            if let found = child.findEntity(named: name) {
                return found
            }
        }
        
        return nil
    }
}

