//
//  RPCModel.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation
import MultipeerConnectivity
import Observation
import simd

// MARK: - RequestSchema

/// 内部ワイヤーフォーマット
///
/// ユーザーは `RPCRequest` を介して `RPCModel.send(_:)` を使います。
/// `RequestSchema` は `RPCModel` と `RequestQueue` 内部でのみ使用されます。
struct RequestSchema: Encodable {
    /// 通信の一意な ID
    let id: UUID
    /// 通信元の Peer の一意な ID
    let peerId: Int
    /// RPC のメソッド（型消去済み）
    let method: AnyRPCMethod

    init(id: UUID = UUID(), peerId: Int, method: AnyRPCMethod) {
        self.id = id
        self.peerId = peerId
        self.method = method
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(peerId, forKey: .peerId)
        var methodContainer = container.nestedContainer(
            keyedBy: DynamicCodingKey.self,
            forKey: .method
        )
        let entityKey = DynamicCodingKey(stringValue: method.entityCodingKey)!
        let methodEncoder = methodContainer.superEncoder(forKey: entityKey)
        try method.encode(to: methodEncoder)
    }

    private enum CodingKeys: String, CodingKey {
        case id, peerId, method
    }
}

extension RequestSchema: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.peerId = try container.decode(Int.self, forKey: .peerId)
        let methodContainer = try container.nestedContainer(
            keyedBy: DynamicCodingKey.self, forKey: .method)
        guard let entityKey = methodContainer.allKeys.first else {
            throw DecodingError.dataCorruptedError(
                forKey: CodingKeys.method, in: container,
                debugDescription: "method field is empty"
            )
        }
        let methodDecoder = try methodContainer.superDecoder(forKey: entityKey)
        self.method = try MethodRegistry.shared.decode(
            entityKey: entityKey.stringValue,
            from: methodDecoder
        )
    }
}

// MARK: - RPCModel

/// RPC を管理するクラス
///
/// ## 新しい Entity を追加するには
/// 1. `RPCEntity` に準拠した struct と `BroadcastMethod` / `UnicastMethod` を実装する
/// 2. ハンドラオブジェクトを生成し、`RPCEntityRegistration<E>(handler:)` でエントリを作る
/// 3. `RPCModel.init(entities:)` の `entities` 引数に渡す
///
/// `RPCModel` 自体は一切変更不要です。
///
/// ```swift
/// let coordinateTransforms = CoordinateTransforms()
///
/// let rpcModel = RPCModel(
///     sendExchangeDataWrapper: send,
///     receiveExchangeDataWrapper: receive,
///     mcPeerIDUUIDWrapper: peerWrapper,
///     entities: [
///         RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)
///     ]
/// )
/// ```
@available(visionOS 26.0, *)
@MainActor
@Observable
public class RPCModel {
    /// 送信するデータ
    private var sendExchangeDataWrapper = ExchangeDataWrapper()
    /// 受信したデータ
    private var receiveExchangeDataWrapper = ExchangeDataWrapper()
    /// 変更検知
    private var receiveChanges: Observations<ExchangeData, Never>
    /// リクエストキュー（再送管理用）
    private let requestQueue: RequestQueue

    var mcPeerIDUUIDWrapper = MCPeerIDUUIDWrapper()

    /// `run(transforming:_:)` で使用するアフィン行列のプロバイダ
    ///
    /// Peer ID を受け取り対応するアフィン行列を返します。
    /// `nil` を返した Peer はスキップされます。
    /// ```swift
    /// rpcModel.affineMatrixProvider = { peerId in
    ///     coordinateTransforms.affineMatrixs[peerId]
    /// }
    /// ```
    var affineMatrixProvider: ((Int) -> simd_float4x4?)?

    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    /// - Parameters:
    ///   - sendExchangeDataWrapper: 送信用ラッパー
    ///   - receiveExchangeDataWrapper: 受信用ラッパー
    ///   - mcPeerIDUUIDWrapper: Peer ID 管理ラッパー
    ///   - entities: 利用する Entity の登録エントリ（`RPCEntityRegistration<E>(handler:)` で生成）
    init(
        sendExchangeDataWrapper: ExchangeDataWrapper,
        receiveExchangeDataWrapper: ExchangeDataWrapper,
        mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper,
        entities: [any RPCEntityRegistrable] = [],
        retriesTimeout: TimeInterval = 1.0,
        maxRetries: Int = 3
    ) {
        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        self.requestQueue = RequestQueue(timeout: retriesTimeout, maxRetries: maxRetries)
        self.receiveChanges = Observations {
            receiveExchangeDataWrapper.exchangeData
        }

        // リクエストキューの再送コールバックを設定
        requestQueue.onRetry = { [weak self] request in
            self?.resendRequest(request)
        }

        // ユーザー定義 Entity を登録
        for entry in entities {
            entry._register(MethodRegistry.shared)
        }

        // フレームワーク内部用 Entity（変更不要）
        // ACK: 受信時にリクエストキューから削除する
        let queue = requestQueue
        MethodRegistry.shared.register(
            AcknowledgmentEntity.self,
            handler: AcknowledgmentHandler { requestId in
                Task { @MainActor in queue.dequeue(requestId) }
            }
        )

        // Error: 受信時にログ出力する（デフォルト動作）
        MethodRegistry.shared.register(
            ErrorEntitiy.self,
            handler: ErrorHandler { message in
                print("[ImmersiveRPCKit] Remote error: \(message)")
            }
        )

        Task { @MainActor in
            for await value in receiveChanges {
                receiveExchangeDataDidChange(value)
            }
        }
    }

    func receiveExchangeDataDidChange(_ exchangeData: ExchangeData) {
        guard let request = try? jsonDecoder.decode(RequestSchema.self, from: exchangeData.data)
        else {
            print("[ImmersiveRPCKit] Failed to decode request")
            return
        }
        _ = receiveRequest(request)
    }

    // MARK: - run

    // - BroadcastRequest（全員へ broadcast）
    //   - run(syncAll:)       — ローカル実行 + broadcast 送信
    // - UnicastRequest（特定 Peer へ unicast）
    //   - run(localOnly:)     — ローカルのみ実行、送信なし
    //   - run(remoteOnly:)    — request.targetPeerId へ unicast 送信のみ
    //   - run(remoteOnly:toEach:) — 複数 Peer へそれぞれ unicast 送信
    //   - run(syncAll:)       — ローカル実行 + request.targetPeerId へ unicast 送信
    //   - run(syncAll:toEach:)— ローカル実行 + 複数 Peer へ unicast 送信
    //   - run(transforming:)  — ローカル実行 + Peer ごとに変換して unicast 送信

    // MARK: BroadcastRequest

    /// BroadcastMethod をローカルで実行し、成功したら全 Peer へ送信する
    ///
    /// ローカル実行が失敗した場合はネットワーク送信をスキップします。
    ///
    /// ```swift
    /// rpcModel.run(syncAll: ChatEntity.request(.sendMessage(.init(text: "hello"))))
    /// ```
    @discardableResult
    func run(syncAll request: RPCBroadcastRequest) -> RPCResult {
        let localResult = MethodRegistry.shared.execute(request.method)
        if case .failure = localResult { return localResult }
        return send(request)
    }

    // MARK: UnicastRequest

    /// UnicastMethod をローカルのハンドラだけ実行する（ネットワーク送信なし）
    ///
    /// `to:` は不要です。`Entity.localRequest(_:)` でリクエストを生成してください。
    ///
    /// ```swift
    /// rpcModel.run(localOnly: ChatEntity.localRequest(.directMessage(.init(text: "hi", fromPeerId: myId))))
    /// ```
    @discardableResult
    func run(localOnly request: RPCLocalRequest) -> RPCResult {
        MethodRegistry.shared.execute(request.method)
    }

    /// UnicastMethod を自端末では実行せず、`request.targetPeerId` へのみ送信する
    ///
    /// ```swift
    /// rpcModel.run(remoteOnly: ChatEntity.request(.directMessage(.init(text: "hi")), to: peerId))
    /// ```
    @discardableResult
    func run(remoteOnly request: RPCUnicastRequest) -> RPCResult {
        send(request)
    }

    /// UnicastMethod を自端末では実行せず、複数 Peer へそれぞれ送信する
    ///
    /// ```swift
    /// rpcModel.run(
    ///     remoteOnly: ChatEntity.request(.directMessage(.init(text: "hi")), to: 0),
    ///     toEach: .peers([peer1, peer2])
    /// )
    /// ```
    @discardableResult
    func run(remoteOnly request: RPCUnicastRequest, toEach target: RPCUnicastMultiTarget)
        -> [RPCResult]
    {
        resolvedPeerIds(for: target).map { peerId in
            send(
                RPCUnicastRequest(
                    entityCodingKey: request.entityCodingKey,
                    method: request.method,
                    targetPeerId: peerId,
                    allowRetry: request.allowRetry
                ))
        }
    }

    /// UnicastMethod を自端末でも実行し、成功したら `request.targetPeerId` へ送信する
    ///
    /// ローカル実行が失敗した場合はネットワーク送信をスキップします。
    ///
    /// ```swift
    /// rpcModel.run(syncAll: ChatEntity.request(.directMessage(.init(text: "hi")), to: peerId))
    /// ```
    @discardableResult
    func run(syncAll request: RPCUnicastRequest) -> RPCResult {
        let localResult = MethodRegistry.shared.execute(request.method)
        if case .failure = localResult { return localResult }
        return send(request)
    }

    /// UnicastMethod を自端末でも実行し、成功したら複数 Peer へそれぞれ送信する
    ///
    /// ローカル実行が失敗した場合はネットワーク送信をスキップします。
    ///
    /// ```swift
    /// rpcModel.run(
    ///     syncAll: ChatEntity.request(.directMessage(.init(text: "hi")), to: 0),
    ///     toEach: .all
    /// )
    /// ```
    @discardableResult
    func run(syncAll request: RPCUnicastRequest, toEach target: RPCUnicastMultiTarget)
        -> [RPCResult]
    {
        let localResult = MethodRegistry.shared.execute(request.method)
        if case .failure = localResult { return [localResult] }
        return resolvedPeerIds(for: target).map { peerId in
            send(
                RPCUnicastRequest(
                    entityCodingKey: request.entityCodingKey,
                    method: request.method,
                    targetPeerId: peerId,
                    allowRetry: request.allowRetry
                ))
        }
    }

    // MARK: transforming

    /// 各 Peer に合わせて手動で変換した UnicastRequest を送信する（クロージャ版）
    ///
    /// 自端末（`mine.hash`）はローカル実行のみ行われ、送信はされません。
    /// `nil` を返した Peer はスキップされます。
    ///
    /// ```swift
    /// rpcModel.run(transforming: .all) { peerId in
    ///     guard let affine = coordinateTransforms.affineMatrix(for: peerId) else { return nil }
    ///     return CoordinateTransformEntity.request(
    ///         .setTransform(.init(peerId: myPeerId, matrix: affine * localMatrix)),
    ///         to: peerId
    ///     )
    /// }
    /// ```
    @discardableResult
    func run(
        transforming target: RPCUnicastMultiTarget = .all,
        requestFor: (Int) -> RPCUnicastRequest?
    ) -> [RPCResult] {
        let myHash = mcPeerIDUUIDWrapper.mine.hash
        if let localRequest = requestFor(myHash) {
            let localResult = MethodRegistry.shared.execute(localRequest.method)
            if case .failure = localResult { return [localResult] }
        }
        return resolvedPeerIds(for: target).compactMap { peerId -> RPCResult? in
            guard let request = requestFor(peerId) else { return nil }
            return send(request)
        }
    }

    /// アフィン行列を自動適用して各 Peer に unicast 送信する（プロバイダ指定版）
    ///
    /// `E.UnicastMethod` が `RPCTransformableUnicastMethod` に準拠している必要があります。
    /// 自端末は変換なしでローカル実行のみ。`affineMatrixFor` が `nil` を返した Peer はスキップされます。
    ///
    /// ```swift
    /// rpcModel.run(transforming: .all, ObjectEntity.self, .move(.init(matrix: m))) { peerId in
    ///     coordinateTransforms.affineMatrix(for: peerId)
    /// }
    /// ```
    @discardableResult
    func run<E: RPCEntity>(
        transforming target: RPCUnicastMultiTarget = .all,
        _ entityType: E.Type,
        _ method: E.UnicastMethod,
        affineMatrixFor: (Int) -> simd_float4x4?
    ) -> [RPCResult] where E.UnicastMethod: RPCTransformableUnicastMethod {
        let localResult = MethodRegistry.shared.execute(
            AnyRPCMethod(entityKey: E.codingKey, unicastMethod: method)
        )
        if case .failure = localResult { return [localResult] }
        return resolvedPeerIds(for: target).compactMap { peerId -> RPCResult? in
            guard let affine = affineMatrixFor(peerId) else { return nil }
            return send(E.request(method.applying(affineMatrix: affine), to: peerId))
        }
    }

    /// アフィン行列を自動適用して各 Peer に unicast 送信する（`affineMatrixProvider` 使用版）
    ///
    /// 事前に `rpcModel.affineMatrixProvider` をセットしておく必要があります。
    /// 未設定の場合はエラーの `RPCResult` を返します。
    ///
    /// ```swift
    /// rpcModel.affineMatrixProvider = { peerId in coordinateTransforms.affineMatrix(for: peerId) }
    /// rpcModel.run(transforming: .all, ObjectEntity.self, .move(.init(matrix: m)))
    /// ```
    @discardableResult
    func run<E: RPCEntity>(
        transforming target: RPCUnicastMultiTarget = .all,
        _ entityType: E.Type,
        _ method: E.UnicastMethod
    ) -> [RPCResult] where E.UnicastMethod: RPCTransformableUnicastMethod {
        guard let provider = affineMatrixProvider else {
            return [
                .failure(
                    RPCError(
                        "affineMatrixProvider が未設定です。rpcModel.affineMatrixProvider を先にセットしてください。"))
            ]
        }
        return run(transforming: target, entityType, method, affineMatrixFor: provider)
    }

    // MARK: - run private helpers

    private func resolvedPeerIds(for target: RPCUnicastMultiTarget) -> [Int] {
        switch target {
        case .all:
            return mcPeerIDUUIDWrapper.standby.map(\.hash)
        case .peer(let id):
            return [id]
        case .peers(let ids):
            return ids
        }
    }

    // MARK: - send

    /// BroadcastMethod リクエストを全 Peer へブロードキャスト送信する（ローカル実行なし）
    @discardableResult
    func send(_ request: RPCBroadcastRequest) -> RPCResult {
        let schema = RequestSchema(
            peerId: mcPeerIDUUIDWrapper.mine.hash,
            method: request.method
        )
        guard let requestData = try? jsonEncoder.encode(schema) else {
            return .failure(RPCError("Failed to encode request"))
        }
        if request.allowRetry {
            requestQueue.enqueue(schema)
        }
        sendExchangeDataWrapper.setData(requestData)
        return .success(())
    }

    /// UnicastMethod リクエストを指定 Peer へ送信する（ローカル実行なし）
    @discardableResult
    func send(_ request: RPCUnicastRequest) -> RPCResult {
        let schema = RequestSchema(
            peerId: mcPeerIDUUIDWrapper.mine.hash,
            method: request.method
        )
        guard let requestData = try? jsonEncoder.encode(schema) else {
            return .failure(RPCError("Failed to encode request"))
        }
        if request.allowRetry {
            requestQueue.enqueue(schema)
        }
        sendExchangeDataWrapper.setData(requestData, to: request.targetPeerId)
        return .success(())
    }

    // MARK: - receiveRequest

    /// 受信した RPC の実行
    /// - Parameters: request: `RequestSchema`
    /// - Returns: `RPCResult`
    func receiveRequest(_ request: RequestSchema) -> RPCResult {
        let entityKey = request.method.entityCodingKey
        let isInternal =
            entityKey == AcknowledgmentEntity.codingKey
            || entityKey == ErrorEntitiy.codingKey

        let rpcResult = MethodRegistry.shared.execute(request.method)

        // 内部 Entity（ACK・Error）はここで終了（ACK 返送不要）
        if isInternal { return rpcResult }

        if case .failure(let e) = rpcResult {
            return error(message: e.message, to: request.peerId)
        }

        sendAcknowledgment(requestId: request.id, to: request.peerId)
        return rpcResult
    }

    // MARK: - Helpers

    /// エラーを特定 Peer へ送信（内部ヘルパー）
    @discardableResult
    func error(message: String, to peerId: Int) -> RPCResult {
        let method = AnyRPCMethod(
            entityKey: ErrorEntitiy.codingKey,
            unicastMethod: ErrorEntitiy.UnicastMethod.error(.init(errorMessage: message))
        )
        let schema = RequestSchema(peerId: mcPeerIDUUIDWrapper.mine.hash, method: method)
        guard let requestData = try? jsonEncoder.encode(schema) else {
            return .failure(RPCError("\"\(message)\" の送信エンコードに失敗しました"))
        }
        sendExchangeDataWrapper.setData(requestData, to: peerId)
        return .failure(RPCError(message))
    }

    /// Acknowledgment を特定 Peer へ送信（内部ヘルパー）
    private func sendAcknowledgment(requestId: UUID, to peerId: Int) {
        let method = AnyRPCMethod(
            entityKey: AcknowledgmentEntity.codingKey,
            unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: requestId))
        )
        let schema = RequestSchema(peerId: mcPeerIDUUIDWrapper.mine.hash, method: method)
        guard let requestData = try? jsonEncoder.encode(schema) else {
            print("[ImmersiveRPCKit] Failed to encode acknowledgment")
            return
        }
        sendExchangeDataWrapper.setData(requestData, to: peerId)
    }

    /// リクエストを再送信
    private func resendRequest(_ request: RequestSchema) {
        guard let requestData = try? jsonEncoder.encode(request) else {
            print("[ImmersiveRPCKit] Failed to encode request for resend")
            return
        }
        if let peerID = mcPeerIDUUIDWrapper.standby.first(where: { $0.hash == request.peerId }) {
            sendExchangeDataWrapper.setData(requestData, to: peerID.hash)
        } else {
            sendExchangeDataWrapper.setData(requestData)
        }
    }
}
