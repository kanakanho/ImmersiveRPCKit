//
//  File.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/27.
//

import Foundation
import RealityKit
import SwiftUI

// added by nagao 2025/3/22
extension ModelEntity {
    class func generateSphere(name: String, color: UIColor, radius: Float = 0.01) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: false)],
            collisionShape: .generateSphere(radius: 0.01),
            mass: 0.0
        )
        
        entity.name = name
        entity.components.set(PhysicsBodyComponent(mode: .kinematic))
        entity.components.set(OpacityComponent(opacity: 1.0))
        
        return entity
    }
}
