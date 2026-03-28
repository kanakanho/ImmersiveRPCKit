//
//  IntegrationTests.swift
//  ImmersiveRPCKit
//
//  結合テスト – RPCModel を介したリクエスト送受信フロー全体を検証する
//  ImmersiveRPCKitAllTests (.serialized) の拡張として定義し直列実行を保証する
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
            MethodRegistry.shared.reset()
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

        @Test func receiveNormalBroadcastRequest_executesHandlerAndSendsAck() throws {
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
            #expect(!sendWrapper.exchangeData.data.isEmpty)
            // ACK は送信元 Peer ID へ unicast
            #expect(sendWrapper.exchangeData.mcPeerId == remotePeer.hash)

            // ACK の entityCodingKey が "ack" であることを確認
            MethodRegistry.shared.register(
                AcknowledgmentEntity.self,
                handler: AcknowledgmentHandler { _ in }
            )
            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            #expect(decoded.method.entityCodingKey == AcknowledgmentEntity.codingKey)
        }

        @Test func receiveNormalUnicastRequest_executesHandlerAndSendsAck() throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 55))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: method)

            let result = model.receiveRequest(schema)
            #expect(result.success)
            #expect(mockHandler.unicastValues.contains(55))
            #expect(sendWrapper.exchangeData.mcPeerId == remotePeer.hash)
        }

        @Test func ackRequestIdMatchesSchemaId() throws {
            var ackedId: UUID? = nil
            MethodRegistry.shared.register(
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
            let decodedAck = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            _ = MethodRegistry.shared.execute(decodedAck.method)
            #expect(ackedId == requestId)
        }

        // MARK: 失敗フロー

        @Test func receiveFailingRequest_sendsErrorNotAck() throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.alwaysFail(
                    .init(reason: "intentional failure"))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: method)

            let result = model.receiveRequest(schema)
            #expect(!result.success)

            #expect(!sendWrapper.exchangeData.data.isEmpty)
            #expect(sendWrapper.exchangeData.mcPeerId == remotePeer.hash)

            // Error entity が送信されている
            MethodRegistry.shared.register(
                ErrorEntitiy.self,
                handler: ErrorHandler { _ in }
            )
            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            #expect(decoded.method.entityCodingKey == ErrorEntitiy.codingKey)
        }

        @Test func receiveFailingRequest_errorMessagePropagates() throws {
            var receivedErrorMsg: String? = nil
            MethodRegistry.shared.register(
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
            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            _ = MethodRegistry.shared.execute(decoded.method)
            #expect(receivedErrorMsg == "propagated-error")
        }

        // MARK: 内部 Entity（ACK / Error）は再 ACK しない

        @Test func receiveAckEntity_doesNotSendAckBack() throws {
            MethodRegistry.shared.register(
                AcknowledgmentEntity.self,
                handler: AcknowledgmentHandler { _ in }
            )

            let ackMethod = AnyRPCMethod(
                entityKey: AcknowledgmentEntity.codingKey,
                unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: UUID()))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: ackMethod)

            let result = model.receiveRequest(schema)
            #expect(result.success)
            // ACK を受け取っても sendWrapper にデータが書き込まれない（再 ACK 不要）
            #expect(sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func receiveErrorEntity_doesNotSendAckBack() throws {
            MethodRegistry.shared.register(
                ErrorEntitiy.self,
                handler: ErrorHandler { _ in }
            )

            let errorMethod = AnyRPCMethod(
                entityKey: ErrorEntitiy.codingKey,
                unicastMethod: ErrorEntitiy.UnicastMethod.error(
                    .init(errorMessage: "internal error"))
            )
            let schema = RequestSchema(peerId: remotePeer.hash, method: errorMethod)

            let result = model.receiveRequest(schema)
            #expect(!result.success)
            // Error を受け取っても sendWrapper にデータが書き込まれない
            #expect(sendWrapper.exchangeData.data.isEmpty)
        }

        // MARK: SpatialEntity を含む変換送受信フロー

        @Test func sendAndReceiveSpatialEntity_matrixPreserved() throws {
            let localSpatialHandler = SpatialHandler()
            MethodRegistry.shared.register(SpatialEntity.self, handler: localSpatialHandler)
            MethodRegistry.shared.register(
                AcknowledgmentEntity.self,
                handler: AcknowledgmentHandler { _ in }
            )

            let matrix = simd_float4x4(pos: .init(1, 2, 3))

            // ①送信側: remoteOnly で SpatialEntity を送信
            let req = SpatialEntity.request(.move(.init(matrix: matrix)), to: remotePeer.hash)
            model.send(req)

            // ②受信側: 送信されたデータを RequestSchema にデコードして受信処理
            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)

            let receiveResult = model.receiveRequest(decoded)
            #expect(receiveResult.success)
            #expect(!localSpatialHandler.executedMatrices.isEmpty)
            #expect(localSpatialHandler.executedMatrices[0].floatList == matrix.floatList)
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

        @Test func transformingAutoFullFlow_localAndRemoteExecution() throws {
            let spatialHandler = SpatialHandler()
            MethodRegistry.shared.register(SpatialEntity.self, handler: spatialHandler)
            MethodRegistry.shared.register(
                AcknowledgmentEntity.self,
                handler: AcknowledgmentHandler { _ in }
            )

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
            #expect(spatialHandler.executedMatrices[0].floatList == localMatrix.floatList)

            // ③ 送信データをデコードして "受信側" で実行
            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            let receiveResult = model.receiveRequest(decoded)
            #expect(receiveResult.success)

            // ④ 受信側で適用された行列は affine * identity
            let expected = affine * localMatrix
            #expect(spatialHandler.executedMatrices[1].floatList == expected.floatList)
        }
    }

}  // end extension ImmersiveRPCKitAllTests
