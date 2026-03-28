//
//  MethodRegistry.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation

// MARK: - CodingUserInfoKey

/// `JSONDecoder.userInfo` に `MethodRegistry` インスタンスを渡すためのキー。
/// `RPCModel` は `jsonDecoder.userInfo[.methodRegistry] = methodRegistry` を設定することで
/// シングルトンに依存せず自身のレジストリを使ってデコードする。
extension CodingUserInfoKey {
    static let methodRegistry = CodingUserInfoKey(
        rawValue: "ImmersiveRPCKit.methodRegistry"
    )!
}

// MARK: - DynamicCodingKey

/// 動的な文字列で CodingKey を生成するヘルパー
struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - ScopeCodingKey

/// broadcast / unicast のスコープを JSON 上で区別するキー
private enum ScopeCodingKey: String, CodingKey {
    case broadcast = "b"
    case unicast = "u"
}

// MARK: - AnyRPCMethod

/// 型消去された RPC メソッドコンテナ
///
/// JSON 上では `{ "b": { ...payload... } }` または `{ "u": { ...payload... } }` の形式で
/// スコープを区別してエンコードされます。
struct AnyRPCMethod: Sendable {
    /// この Method が属する Entity の codingKey
    let entityCodingKey: String
    private let _encode: @Sendable (Encoder) throws -> Void
    private let _execute: @MainActor @Sendable (Any) -> RPCResult

    /// BroadcastMethod コンテナを生成する
    init<M: RPCBroadcastMethod>(entityKey: String, broadcastMethod: M) {
        self.entityCodingKey = entityKey
        self._encode = { encoder in
            var container = encoder.container(keyedBy: ScopeCodingKey.self)
            try container.encode(broadcastMethod, forKey: .broadcast)
        }
        self._execute = { @MainActor handler in
            guard let typedHandler = handler as? M.Handler else {
                return RPCResult("Handler type mismatch for entity '\(entityKey)'. Expected \(M.Handler.self).")
            }
            return broadcastMethod.execute(on: typedHandler)
        }
    }

    /// UnicastMethod コンテナを生成する
    init<M: RPCUnicastMethod>(entityKey: String, unicastMethod: M) {
        self.entityCodingKey = entityKey
        self._encode = { encoder in
            var container = encoder.container(keyedBy: ScopeCodingKey.self)
            try container.encode(unicastMethod, forKey: .unicast)
        }
        self._execute = { @MainActor handler in
            guard let typedHandler = handler as? M.Handler else {
                return RPCResult("Handler type mismatch for entity '\(entityKey)'. Expected \(M.Handler.self).")
            }
            return unicastMethod.execute(on: typedHandler)
        }
    }

    /// 型消去されたハンドラでメソッドを実行する
    @MainActor func execute(on handler: Any) -> RPCResult {
        _execute(handler)
    }
}

extension AnyRPCMethod: Encodable {
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - MethodRegistry

/// Entity とハンドラの登録・管理を行うレジストリ
///
/// 各 `RPCModel` は専有の `MethodRegistry` インスタンスを保持します（per-instance 設計）。
/// 複数の `RPCModel` を同一プロセスで共存させても互いに干渉しません。
///
/// - Note: 登録・実行操作はすべて `@MainActor` 上で行います。
///         `decode(entityKey:from:)` は登録完了後に読み取り専用で使うため `nonisolated` です。
final class MethodRegistry: @unchecked Sendable {
    /// codingKey → デコーダ関数
    private var decoders: [String: (Decoder) throws -> AnyRPCMethod] = [:]
    /// codingKey → ハンドラ
    private var handlers: [String: Any] = [:]

    init() {}

    // MARK: Registration

    /// BroadcastMethod と UnicastMethod が同じハンドラ型を持つ Entity を登録する
    func register<E: RPCEntity>(_ entityType: E.Type, handler: E.BroadcastMethod.Handler)
    where E.BroadcastMethod.Handler == E.UnicastMethod.Handler {
        let key = E.codingKey
        decoders[key] = { decoder in
            let container = try decoder.container(keyedBy: ScopeCodingKey.self)
            if container.contains(.broadcast) {
                let method = try container.decode(E.BroadcastMethod.self, forKey: .broadcast)
                return AnyRPCMethod(entityKey: key, broadcastMethod: method)
            } else {
                let method = try container.decode(E.UnicastMethod.self, forKey: .unicast)
                return AnyRPCMethod(entityKey: key, unicastMethod: method)
            }
        }
        handlers[key] = handler
    }

    /// 登録済み Entity のハンドラのみを更新する
    func updateHandler<E: RPCEntity>(_ entityType: E.Type, handler: E.BroadcastMethod.Handler)
    where E.BroadcastMethod.Handler == E.UnicastMethod.Handler {
        handlers[E.codingKey] = handler
    }

    // MARK: Decode

    /// entityKey と Decoder を使って `AnyRPCMethod` をデコードする
    ///
    /// `RequestSchema.init(from:)` の内部から呼ばれます。
    /// `decoders` は登録完了後は読み取り専用のため安全です。
    func decode(entityKey: String, from decoder: Decoder) throws -> AnyRPCMethod {
        guard let decode = decoders[entityKey] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown entity key '\(entityKey)'. Call MethodRegistry.register(_:handler:) first."
                )
            )
        }
        return try decode(decoder)
    }

    // MARK: Execute

    /// 登録されたハンドラでメソッドを実行する
    @MainActor func execute(_ method: AnyRPCMethod) -> RPCResult {
        guard let handler = handlers[method.entityCodingKey] else {
            return RPCResult("No handler registered for entity '\(method.entityCodingKey)'.")
        }
        return method.execute(on: handler)
    }

    // MARK: Reset

    /// 登録済みのデコーダとハンドラをすべてクリアする
    func reset() {
        decoders = [:]
        handlers = [:]
    }
}
