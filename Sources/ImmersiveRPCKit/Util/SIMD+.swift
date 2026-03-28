//
//  SIMD+.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation
import RealityKit

extension SIMD3 {
    // Initialize Float4 with SIMD3<Float> inputs.
    init(_ float4: SIMD4<Scalar>) {
        self.init()

        x = float4.x
        y = float4.y
        z = float4.z
    }
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        self[SIMD3(0, 1, 2)]
    }
}

extension simd_float4x4: @retroactive Decodable {}
extension simd_float4x4: @retroactive Encodable {}
extension simd_float4x4 {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var matrix: [SIMD4<Float>] = []
        for _ in 0..<4 {
            let row = try container.decode(SIMD4<Float>.self)
            matrix.append(row)
        }
        self = simd_float4x4([
            SIMD4<Float>(matrix[0][0], matrix[0][1], matrix[0][2], matrix[0][3]),
            SIMD4<Float>(matrix[1][0], matrix[1][1], matrix[1][2], matrix[1][3]),
            SIMD4<Float>(matrix[2][0], matrix[2][1], matrix[2][2], matrix[2][3]),
            SIMD4<Float>(matrix[3][0], matrix[3][1], matrix[3][2], matrix[3][3]),
        ])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for row in 0..<4 {
            try container.encode([self[row, 0], self[row, 1], self[row, 2], self[row, 3]])
        }
    }

    static var identity: simd_float4x4 {
        matrix_identity_float4x4
    }

    var position: SIMD3<Float> {
        self.columns.3.xyz
    }

    init(pos: SIMD3<Float>) {
        self.init([
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(pos.x, pos.y, pos.z, 1),
        ])
    }
}

extension simd_float4x4 {
    var floatList: [[Float]] {
        return [
            [self.columns.0.x, self.columns.0.y, self.columns.0.z, self.columns.0.w],
            [self.columns.1.x, self.columns.1.y, self.columns.1.z, self.columns.1.w],
            [self.columns.2.x, self.columns.2.y, self.columns.2.z, self.columns.2.w],
            [self.columns.3.x, self.columns.3.y, self.columns.3.z, self.columns.3.w],
        ]
    }

    var doubleList: [[Double]] {
        return [
            [Double(self.columns.0.x), Double(self.columns.0.y), Double(self.columns.0.z), Double(self.columns.0.w)],
            [Double(self.columns.1.x), Double(self.columns.1.y), Double(self.columns.1.z), Double(self.columns.1.w)],
            [Double(self.columns.2.x), Double(self.columns.2.y), Double(self.columns.2.z), Double(self.columns.2.w)],
            [Double(self.columns.3.x), Double(self.columns.3.y), Double(self.columns.3.z), Double(self.columns.3.w)],
        ]
    }
}

extension Float {
    func toDouble() -> Double {
        Double(self)
    }
}

extension Double {
    func toFloat() -> Float {
        Float(self)
    }
}

extension [[Float]] {
    func toDoubleList() -> [[Double]] {
        return self.map { $0.map { Double($0) } }
    }
}

extension [[Double]] {
    var transpose4x4: [[Double]] {
        var result = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                result[i][j] = self[j][i]
            }
        }
        return result
    }

    func tosimd_float4x4() -> simd_float4x4 {
        return simd_float4x4([
            SIMD4<Float>(self[0][0].toFloat(), self[0][1].toFloat(), self[0][2].toFloat(), self[0][3].toFloat()),
            SIMD4<Float>(self[1][0].toFloat(), self[1][1].toFloat(), self[1][2].toFloat(), self[1][3].toFloat()),
            SIMD4<Float>(self[2][0].toFloat(), self[2][1].toFloat(), self[2][2].toFloat(), self[2][3].toFloat()),
            SIMD4<Float>(self[3][0].toFloat(), self[3][1].toFloat(), self[3][2].toFloat(), self[3][3].toFloat()),
        ])
    }

    var isIncludeNaN: Bool {
        for row in self {
            for value in row {
                if value.isNaN {
                    return true
                }
            }
        }
        return false
    }
}
