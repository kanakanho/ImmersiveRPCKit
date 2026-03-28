//
//  AcknowledgmentEntity.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation

// MARK: - Handler

/// Acknowledgment を受信したときのコールバックを保持するハンドラ
struct AcknowledgmentHandler {
    /// ACK が届いたときに呼ばれるコールバック（引数: 確認済みリクエストの UUID）
    var onAck: (UUID) -> Void

    init(onAck: @escaping (UUID) -> Void = { _ in }) {
        self.onAck = onAck
    }
}

// MARK: - Entity

/// RPC acknowledgment entity for tracking successful request completion
struct AcknowledgmentEntity: RPCEntity {
    static let codingKey = "ack"

    /// ブロードキャストなし（ユニキャスト専用 Entity）
    typealias BroadcastMethod = NoMethod<AcknowledgmentHandler>

    enum UnicastMethod: RPCUnicastMethod {
        typealias Handler = AcknowledgmentHandler

        case ack(AckParam)

        /// Acknowledgment parameter containing the original request ID
        struct AckParam: Codable {
            /// The ID of the request being acknowledged
            let requestId: UUID
        }

        // MARK: execute
        func execute(on handler: AcknowledgmentHandler) -> RPCResult {
            switch self {
            case .ack(let param):
                handler.onAck(param.requestId)
                return .success(())
            }
        }

        // MARK: Codable
        enum CodingKeys: String, CodingKey {
            case ack
        }
    }
}
