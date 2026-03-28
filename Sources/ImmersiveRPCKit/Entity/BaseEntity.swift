//
//  BaseEntity.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation
import simd

// MARK: - RPCBroadcastMethod

/// ブロードキャスト（全 Peer 送信）用 RPC メソッドプロトコル
///
/// `RPCRequest(_:)` に渡すと送信先指定なしで全 Peer へ送られます。
/// 片方のスコープのみ持つ Entity では `typealias BroadcastMethod = Never` とします。
/// `Sendable` は `AnyRPCMethod` の `@Sendable` クロージャキャプチャのために必要です。
protocol RPCBroadcastMethod: Codable, Sendable {
    /// このメソッドを実行するハンドラの型
    associatedtype Handler
    /// ハンドラでメソッドを実行し、結果を返す
    func execute(on handler: Handler) -> RPCResult
    /// 失敗時に再送するかどうか（デフォルト: true）
    var allowRetry: Bool { get }
}

extension RPCBroadcastMethod {
    var allowRetry: Bool { true }
}

// MARK: - RPCUnicastMethod

/// ユニキャスト（特定 Peer 送信）用 RPC メソッドプロトコル
///
/// `RPCRequest(_:to:)` に渡すと指定した Peer ID へのみ送られます。
/// 片方のスコープのみ持つ Entity では `typealias UnicastMethod = Never` とします。
/// `Sendable` は `AnyRPCMethod` の `@Sendable` クロージャキャプチャのために必要です。
protocol RPCUnicastMethod: Codable, Sendable {
    /// このメソッドを実行するハンドラの型
    associatedtype Handler
    /// ハンドラでメソッドを実行し、結果を返す
    func execute(on handler: Handler) -> RPCResult
    /// 失敗時に再送するかどうか（デフォルト: true）
    var allowRetry: Bool { get }
}

extension RPCUnicastMethod {
    var allowRetry: Bool { true }
}

// MARK: - NoMethod placeholder

/// ブロードキャストまたはユニキャストが不要な Entity で使うプレースホルダ型
///
/// ケースなしの uninhabited enum なので、インスタンスを生成できません。
/// `typealias BroadcastMethod = NoMethod<MyHandler>` のようにして使います。
/// `@unchecked Sendable`: ケースがなくインスタンス不存在のため送信されることはなく安全。
enum NoMethod<H>: RPCBroadcastMethod, RPCUnicastMethod {
    typealias Handler = H

    init(from decoder: Decoder) throws {
        throw DecodingError.dataCorrupted(
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "NoMethod cannot be instantiated"
            )
        )
    }

    func encode(to encoder: Encoder) throws { /* uninhabited */  }

    func execute(on handler: H) -> RPCResult {
        // 到達不能コード: NoMethod はインスタンス化できないため呼ばれることはない
        .failure(RPCError("NoMethod should never be executed."))
    }

    /// 明示的に宣言して 2 つのプロトコルの拡張間の曖昧さを回避
    var allowRetry: Bool { true }
}

// NoMethod はケースなし（uninhabited）のため @unchecked Sendable は安全
extension NoMethod: @unchecked Sendable {}

// MARK: - RPCEntity

/// RPC で利用する Entity の基底プロトコル
///
/// 新しい Entity を追加する手順:
/// 1. `RPCEntity` に準拠した struct を定義し、`static var codingKey` を設定する
/// 2. `BroadcastMethod` / `UnicastMethod` の enum を実装する
///    （片方のみなら `typealias BroadcastMethod = Never` などとする）
/// 3. `RPCEntityRegistration<E>(handler:)` で登録エントリを作り `RPCModel.init(entities:)` に渡す
protocol RPCEntity {
    /// 全 Peer へブロードキャストするメソッド群（不要なら `NoMethod<HandlerType>`）
    associatedtype BroadcastMethod: RPCBroadcastMethod
    /// 特定 Peer へユニキャストするメソッド群（不要なら `NoMethod<HandlerType>`）
    associatedtype UnicastMethod: RPCUnicastMethod
    /// JSON での識別キー（全 Entity で一意にする）
    static var codingKey: String { get }
}

// MARK: - RPCEntityRegistrable

/// 型パラメータを消去した登録エントリの基本プロトコル
protocol RPCEntityRegistrable {
    var _register: (MethodRegistry) -> Void { get }
}

// MARK: - RPCEntityRegistration

/// Entity 用の登録エントリ
///
/// BroadcastMethod と UnicastMethod で同一ハンドラを共有する Entity に使います。
/// どちらかが不要な場合は `typealias BroadcastMethod = NoMethod<MyHandler>` のように
/// `NoMethod<H>` を使うと、ハンドラ型を揃えつつインスタンス生成を禁止できます。
///
/// ```swift
/// let coordinateTransforms = CoordinateTransforms()
/// let entry = RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)
/// ```
struct RPCEntityRegistration<E: RPCEntity>: RPCEntityRegistrable
where E.BroadcastMethod.Handler == E.UnicastMethod.Handler {
    let _register: (MethodRegistry) -> Void

    init(_ entityType: E.Type = E.self, handler: E.BroadcastMethod.Handler) {
        _register = { registry in
            registry.register(E.self, handler: handler)
        }
    }
}

// MARK: - RPCBroadcastRequest

/// BroadcastMethod リクエスト（送信先なし・常にブロードキャスト）
///
/// 直接生成せず、`RPCEntity.request(_:)` を使ってください。
/// このリクエストは `run(remoteOnly:)` / `run(syncAll:)` にのみ渡せます。
/// `run(localOnly:)` や特定 Peer への送信には使用できません。
struct RPCBroadcastRequest {
    /// この Method が属する Entity の codingKey
    let entityCodingKey: String
    /// 型消去済みメソッド（エンコード・実行用）
    let method: AnyRPCMethod
    /// 失敗時に再送するかどうか
    let allowRetry: Bool
}

// MARK: - RPCLocalRequest

/// ローカル実行専用リクエスト（送信先 Peer ID 不要）
///
/// 直接生成せず、`RPCEntity.localRequest(_:)` を使ってください。
/// このリクエストは `run(localOnly:)` にのみ渡せます。
/// ネットワーク送信には使用できません。
struct RPCLocalRequest {
    /// この Method が属する Entity の codingKey
    let entityCodingKey: String
    /// 型消去済みメソッド（実行用）
    let method: AnyRPCMethod
    /// 失敗時に再送するかどうか
    let allowRetry: Bool
}

// MARK: - RPCUnicastRequest

/// UnicastMethod リクエスト（送信先 Peer ID 必須）
///
/// 直接生成せず、`RPCEntity.request(_:to:)` を使ってください。
/// このリクエストは `run(remoteOnly:to:)` / `run(syncAll:to:)` に渡せます。
struct RPCUnicastRequest {
    /// この Method が属する Entity の codingKey
    let entityCodingKey: String
    /// 型消去済みメソッド（エンコード・実行用）
    let method: AnyRPCMethod
    /// 送信先 Peer ID
    let targetPeerId: Int
    /// 失敗時に再送するかどうか
    let allowRetry: Bool
}

// MARK: - RPCEntity factory helpers

extension RPCEntity {
    /// ブロードキャスト用リクエストを生成する
    ///
    /// 生成されるリクエストは `run(remoteOnly:)` / `run(syncAll:)` にのみ渡せます。
    /// 特定 Peer への送信や `run(localOnly:)` には使用できません。
    ///
    /// ```swift
    /// rpcModel.run(syncAll: ChatEntity.request(.sendMessage(.init(text: "hello"))))
    /// ```
    static func request(_ method: BroadcastMethod) -> RPCBroadcastRequest {
        RPCBroadcastRequest(
            entityCodingKey: codingKey,
            method: AnyRPCMethod(entityKey: codingKey, broadcastMethod: method),
            allowRetry: method.allowRetry
        )
    }

    /// ローカル実行専用リクエストを生成する（送信先 Peer ID 不要）
    ///
    /// 生成されるリクエストは `run(localOnly:)` にのみ渡せます。
    /// ネットワーク送信には使用できません。
    ///
    /// ```swift
    /// rpcModel.run(localOnly: ChatEntity.localRequest(.directMessage(.init(text: "hi", fromPeerId: myId))))
    /// ```
    static func localRequest(_ method: UnicastMethod) -> RPCLocalRequest {
        RPCLocalRequest(
            entityCodingKey: codingKey,
            method: AnyRPCMethod(entityKey: codingKey, unicastMethod: method),
            allowRetry: method.allowRetry
        )
    }

    /// ユニキャスト用リクエストを生成する（送信先 Peer ID 必須）
    ///
    /// 生成されるリクエストは `run(remoteOnly:to:)` / `run(syncAll:to:)` に渡せます。
    ///
    /// ```swift
    /// rpcModel.run(remoteOnly: ChatEntity.request(.directMessage(.init(text: "hi")), to: peerId))
    /// ```
    static func request(_ method: UnicastMethod, to targetPeerId: Int) -> RPCUnicastRequest {
        RPCUnicastRequest(
            entityCodingKey: codingKey,
            method: AnyRPCMethod(entityKey: codingKey, unicastMethod: method),
            targetPeerId: targetPeerId,
            allowRetry: method.allowRetry
        )
    }
}

// MARK: - RPCUnicastMultiTarget

/// `run(remoteOnly:toEach:)` / `run(syncAll:toEach:)` / `run(transforming:...)` の
/// 複数 Peer 送信先を指定するための型
///
/// 1 Peer への送信は `run(remoteOnly:)` / `run(remoteOnly:to:)` を使ってください。
enum RPCUnicastMultiTarget: Sendable {
    /// `mcPeerIDUUIDWrapper.standby` の全 Peer へそれぞれ unicast
    case all
    /// 特定の 1 Peer へ unicast（`transforming` での絞り込み等に使用）
    case peer(Int)
    /// 複数の Peer それぞれへ unicast
    case peers([Int])
}

// MARK: - RPCTransformableUnicastMethod

/// 座標変換に対応した UnicastMethod であることを示すプロトコル
///
/// `run(transforming:_:)` で自動変換させるには、
/// `UnicastMethod` をこのプロトコルに準拠させて `applying(affineMatrix:)` を実装します。
/// 座標フィールドを持たない case は `return self` で対応します。
///
/// ```swift
/// enum UnicastMethod: RPCTransformableUnicastMethod {
///     case moveObject(MoveObjectParam)
///     case ping                          // 座標なし
///
///     func applying(affineMatrix: simd_float4x4) -> Self {
///         switch self {
///         case .moveObject(let p):
///             return .moveObject(.init(matrix: affineMatrix * p.matrix))
///         case .ping:
///             return self
///         }
///     }
/// }
/// ```
protocol RPCTransformableUnicastMethod: RPCUnicastMethod {
    /// アフィン行列を適用した変換済みメソッドを返す（pure function）
    func applying(affineMatrix: simd_float4x4) -> Self
}
