//
//  TestFixtures.swift
//  ImmersiveRPCKit
//
//  テスト全体で共有するフィクスチャ定義
//

import Foundation
import MultipeerConnectivity
import simd

@testable import ImmersiveRPCKit

// MARK: - MockHandler

/// broadcast / unicast の呼び出しを記録するテスト用ハンドラ
final class MockHandler {
    var broadcastMessages: [String] = []
    var unicastValues: [Int] = []
    var failureCallCount: Int = 0

    func handleBroadcast(message: String) -> RPCResult {
        broadcastMessages.append(message)
        return RPCResult()
    }

    func handleUnicast(value: Int) -> RPCResult {
        unicastValues.append(value)
        return RPCResult()
    }
}

// MARK: - MockEntity
//
// BroadcastMethod と UnicastMethod の両方を持つシンプルな Entity。
// `.ping`: 成功 + allowRetry = true
// `.alwaysFail`: 失敗 + allowRetry = false

struct MockEntity: RPCEntity {
    static let codingKey = "testMock"

    // MARK: BroadcastMethod
    enum BroadcastMethod: RPCBroadcastMethod {
        typealias Handler = MockHandler

        case ping(PingParam)
        case alwaysFail(FailParam)

        struct PingParam: Codable { let message: String }
        struct FailParam: Codable { let reason: String }

        func execute(on handler: MockHandler) -> RPCResult {
            switch self {
            case .ping(let p): return handler.handleBroadcast(message: p.message)
            case .alwaysFail(let p): return RPCResult(p.reason)
            }
        }

        var allowRetry: Bool {
            switch self {
            case .ping: return true
            case .alwaysFail: return false
            }
        }

        enum CodingKeys: CodingKey { case ping, alwaysFail }
    }

    // MARK: UnicastMethod
    enum UnicastMethod: RPCUnicastMethod {
        typealias Handler = MockHandler

        case setValue(SetValueParam)
        case alwaysFail(FailParam)

        struct SetValueParam: Codable { let value: Int }
        struct FailParam: Codable { let reason: String }

        func execute(on handler: MockHandler) -> RPCResult {
            switch self {
            case .setValue(let p): return handler.handleUnicast(value: p.value)
            case .alwaysFail(let p): return RPCResult(p.reason)
            }
        }

        var allowRetry: Bool {
            switch self {
            case .setValue: return true
            case .alwaysFail: return false
            }
        }

        enum CodingKeys: CodingKey { case setValue, alwaysFail }
    }
}

// MARK: - SpatialHandler

/// simd_float4x4 を記録するテスト用ハンドラ
final class SpatialHandler {
    var executedMatrices: [simd_float4x4] = []

    func move(matrix: simd_float4x4) -> RPCResult {
        executedMatrices.append(matrix)
        return RPCResult()
    }
}

// MARK: - SpatialEntity
//
// RPCTransformableUnicastMethod に準拠したテスト用 Entity。
// BroadcastMethod なし（NoMethod<SpatialHandler>）。
// UnicastMethod.move の matrix フィールドにアフィン行列を適用する。

struct SpatialEntity: RPCEntity {
    static let codingKey = "testSpatial"

    typealias BroadcastMethod = NoMethod<SpatialHandler>

    enum UnicastMethod: RPCTransformableUnicastMethod {
        typealias Handler = SpatialHandler

        case move(MoveParam)

        struct MoveParam: Codable { let matrix: simd_float4x4 }

        func execute(on handler: SpatialHandler) -> RPCResult {
            switch self {
            case .move(let p): return handler.move(matrix: p.matrix)
            }
        }

        func applying(affineMatrix: simd_float4x4) -> Self {
            switch self {
            case .move(let p):
                return .move(.init(matrix: affineMatrix * p.matrix))
            }
        }

        enum CodingKeys: CodingKey { case move }
    }
}

// MARK: - MethodRegistry + RPCModel ヘルパー

extension MethodRegistry {
    /// テスト向けに MockEntity と SpatialEntity を共通登録するユーティリティ
    func registerTestEntities(mockHandler: MockHandler, spatialHandler: SpatialHandler) {
        register(MockEntity.self, handler: mockHandler)
        register(SpatialEntity.self, handler: spatialHandler)
    }
}

// MARK: - RequestSchema デコード確認ヘルパー

/// 送信された ExchangeDataWrapper のデータを RequestSchema にデコードして返す
@available(visionOS 26.0, *)
func decodeSentSchema(from wrapper: ExchangeDataWrapper) throws -> RequestSchema {
    try JSONDecoder().decode(RequestSchema.self, from: wrapper.exchangeData.data)
}
