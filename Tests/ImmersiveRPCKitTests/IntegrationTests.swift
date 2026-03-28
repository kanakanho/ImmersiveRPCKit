//
//  IntegrationTests.swift
//  ImmersiveRPCKit
//
//  結合テスト – RPCModel を介したリクエスト送受信フロー全体を検証する
//  各 RPCModel は per-instance MethodRegistry を持つため独立して実行できる
//

import Foundation
import MultipeerConnectivity
import Testing
import simd

@testable import ImmersiveRPCKit

// MARK: - receiveRequest 結合テスト

extension ImmersiveRPCKitAllTests {

    /// RPCModel.receiveRequest が正しく動作するかを検証するスイート。
    ///
    /// - 正常リクエスト: ハンドラ実行 → ACK をリモート Peer へ送信
    /// - 失敗リクエスト: Error をリモート Peer へ送信
    /// - 内部 Entity（ACK / Error）: ハンドラ実行のみ（ACK の再送なし）
    @Suite @MainActor struct RPCModelReceiveIntegrationTests {
        let sendWrapper: ExchangeDataWrapper
        let receiveWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel
        let remotePeer: MCPeerID

        init() {
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = MockHandler()
            let rp = MCPeerID(displayName: "remote")
            peers.standby = [rp]

            sendWrapper = send
            receiveWrapper = receive
            mockHandler = handler
            remotePeer = rp
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<MockEntity>(handler: handler)]
            )
        }

        // MARK: 正常フロー

        @Test func receiveNormalBroadcastRequest_executesHandlerAndSendsAck() async throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "from-remote"))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: method)

            let result = model.receiveRequest(schema)
            #expect(result.success)

            // ハンドラが呼ばれている
            #expect(mockHandler.broadcastMessages.contains("from-remote"))

            // ACK が sendWrapper に書き込まれている
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(!sent.data.isEmpty)
            // ACK は送信元 Peer ID へ unicast
            #expect(sent.mcPeerId == remotePeer.hash)

            // ACK の entityCodingKey が "ack" であることを確認
            let decoded = try decodeSentSchema(from: sent, using: model.methodRegistry)
            #expect(decoded.method.entityCodingKey == AcknowledgmentEntity.codingKey)
        }

        @Test func receiveNormalUnicastRequest_executesHandlerAndSendsAck() async throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 55))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: method)

            let result = model.receiveRequest(schema)
            #expect(result.success)
            #expect(mockHandler.unicastValues.contains(55))
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(sent.mcPeerId == remotePeer.hash)
        }

        @Test func ackRequestIdMatchesSchemaId() async throws {
            var ackedId: UUID? = nil
            // モデルの ACK ハンドラをテスト用に上書き
            model.methodRegistry.updateHandler(
                AcknowledgmentEntity.self,
                handler: AcknowledgmentHandler { id in ackedId = id }
            )

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "ack-id-test"))
            )
            let requestId = UUID()
            let schema = RequestSchema(id: requestId, peerId: remotePeer.hash, method: method)

            _ = model.receiveRequest(schema)

            // 送信された ACK のリクエストデータを再デコードして ACK ID を取り出す
            let sentAck = try #require(await nextValue(from: sendWrapper))
            let decodedAck = try decodeSentSchema(from: sentAck, using: model.methodRegistry)
            _ = model.methodRegistry.execute(decodedAck.method)
            #expect(ackedId == requestId)
        }

        // MARK: 失敗フロー

        @Test func receiveFailingRequest_sendsErrorNotAck() async throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.alwaysFail(
                    .init(reason: "intentional failure"))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: method)

            let result = model.receiveRequest(schema)
            #expect(!result.success)

            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(!sent.data.isEmpty)
            #expect(sent.mcPeerId == remotePeer.hash)

            // Error entity が送信されている
            let decoded = try decodeSentSchema(from: sent, using: model.methodRegistry)
            #expect(decoded.method.entityCodingKey == ErrorEntitiy.codingKey)
        }

        @Test func receiveFailingRequest_errorMessagePropagates() async throws {
            var receivedErrorMsg: String? = nil
            // モデルの Error ハンドラをテスト用に上書き
            model.methodRegistry.updateHandler(
                ErrorEntitiy.self,
                handler: ErrorHandler { msg in receivedErrorMsg = msg }
            )

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.alwaysFail(
                    .init(reason: "propagated-error"))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: method)
            _ = model.receiveRequest(schema)

            // 送信された Error を自分が受信した想定でデコード・実行
            let sentErr = try #require(await nextValue(from: sendWrapper))
            let decoded = try decodeSentSchema(from: sentErr, using: model.methodRegistry)
            _ = model.methodRegistry.execute(decoded.method)
            #expect(receivedErrorMsg == "propagated-error")
        }

        // MARK: 内部 Entity（ACK / Error）は再 ACK しない

        @Test func receiveAckEntity_doesNotSendAckBack() async throws {
            let ackMethod = AnyRPCMethod(
                entityKey: AcknowledgmentEntity.codingKey,
                unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: UUID()))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: ackMethod)

            let result = model.receiveRequest(schema)
            #expect(result.success)
            // ACK を受け取っても sendWrapper にデータが書き込まれない（再 ACK 不要）
            let sent = await nextValue(from: sendWrapper)
            #expect(sent == nil)
        }

        @Test func receiveErrorEntity_doesNotSendAckBack() async throws {
            let errorMethod = AnyRPCMethod(
                entityKey: ErrorEntitiy.codingKey,
                unicastMethod: ErrorEntitiy.UnicastMethod.error(
                    .init(errorMessage: "internal error"))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: errorMethod)

            let result = model.receiveRequest(schema)
            #expect(!result.success)
            // Error を受け取っても sendWrapper にデータが書き込まれない
            let sent = await nextValue(from: sendWrapper)
            #expect(sent == nil)
        }

        // MARK: SpatialEntity を含む変換送受信フロー

        @Test func sendAndReceiveSpatialEntity_matrixPreserved() async throws {
            let localSpatialHandler = SpatialHandler()
            model.methodRegistry.register(SpatialEntity.self, handler: localSpatialHandler)

            let matrix = simd_float4x4(pos: .init(1, 2, 3))

            // ①送信側: remoteOnly で SpatialEntity を送信
            let req = SpatialEntity.request(.move(.init(matrix: matrix)), to: remotePeer.hash)
            model.send(req)

            // ②受信側: 送信されたデータを RequestSchema にデコードして受信処理
            let sentData = try #require(await nextValue(from: sendWrapper))
            let decoded = try decodeSentSchema(from: sentData, using: model.methodRegistry)

            let receiveResult = model.receiveRequest(decoded)
            #expect(receiveResult.success)
            #expect(!localSpatialHandler.executedMatrices.isEmpty)
            #expect(localSpatialHandler.executedMatrices[0] == matrix)
        }

        // MARK: 複数スタンバイ Peer への syncAll フロー

        @Test func syncAllToMultiplePeers_allReceiveAndExecute() throws {
            let peer2 = MCPeerID(displayName: "peer-2")
            model.mcPeerIDUUIDWrapper.standby.append(peer2)

            let req = MockEntity.request(.ping(.init(message: "sync-multi")))
            let result = model.run(syncAll: req)  // RPCBroadcastRequest → RPCResult

            // ローカル実行成功後に broadcast 送信
            #expect(result.success)
            #expect(mockHandler.broadcastMessages.contains("sync-multi"))
        }

        // MARK: transforming 全フロー結合テスト

        @Test func transformingAutoFullFlow_localAndRemoteExecution() async throws {
            let spatialHandler = SpatialHandler()
            model.methodRegistry.register(SpatialEntity.self, handler: spatialHandler)

            let localMatrix = simd_float4x4.identity
            let affine = simd_float4x4(pos: .init(10, 0, 0))

            // ① ローカル実行 + remotePeer への変換済み unicast 送信
            let results = model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: localMatrix))
            ) { _ in affine }

            #expect(results.allSatisfy { $0.success })

            // ② ローカルには identity 行列で実行される
            #expect(spatialHandler.executedMatrices[0] == localMatrix)

            // ③ 送信データをデコードして "受信側" で実行
            let sentData = try #require(await nextValue(from: sendWrapper))
            let decoded = try decodeSentSchema(from: sentData, using: model.methodRegistry)
            let receiveResult = model.receiveRequest(decoded)
            #expect(receiveResult.success)

            // ④ 受信側で適用された行列は affine * identity
            let expected = affine * localMatrix
            #expect(spatialHandler.executedMatrices[1] == expected)
        }
    }

}  // end extension ImmersiveRPCKitAllTests
