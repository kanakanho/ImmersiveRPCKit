//
//  ErrorEntitiy.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation

// MARK: - Handler

/// RPC エラーを受信したときのコールバックを保持するハンドラ
struct ErrorHandler {
    /// エラーが届いたときに呼ばれるコールバック（引数: エラーメッセージ）
    var onError: (String) -> Void

    init(
        onError: @escaping (String) -> Void = { message in
            print("[ImmersiveRPCKit] RPCError received: \(message)")
        }
    ) {
        self.onError = onError
    }
}

// MARK: - Entity

struct ErrorEntitiy: RPCEntity {
    static let codingKey = "error"

    /// ブロードキャストなし（ユニキャスト専用 Entity）
    typealias BroadcastMethod = NoMethod<ErrorHandler>

    enum UnicastMethod: RPCUnicastMethod {
        typealias Handler = ErrorHandler

        case error(ErrorParam)

        struct ErrorParam: Codable {
            let errorMessage: String
        }

        // MARK: execute
        func execute(on handler: ErrorHandler) -> RPCResult {
            switch self {
            case .error(let param):
                handler.onError(param.errorMessage)
                return .failure(RPCError(param.errorMessage))
            }
        }

        // MARK: Codable
        enum CodingKeys: String, CodingKey {
            case error
        }
    }
}
