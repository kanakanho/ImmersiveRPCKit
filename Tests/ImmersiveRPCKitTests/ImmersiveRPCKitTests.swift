//
//  ImmersiveRPCKitTests.swift
//  ImmersiveRPCKit
//
//  ユニットテスト + 結合テスト
//  MethodRegistry.shared はシングルトンなので .serialized で直列実行する
//

import Foundation
import MultipeerConnectivity
import Testing
import simd

@testable import ImmersiveRPCKit

/// 全テストを直列化するルートスイート
///
/// MethodRegistry.shared はプロセスグローバルなシングルトンなので、
/// 並列実行すると reset() が別スイートのテスト実行中に呼ばれて状態が壊れる。
/// .serialized を付けることで全テストを 1 件ずつ順番に実行する。
@Suite("ImmersiveRPCKit", .serialized)
struct ImmersiveRPCKitAllTests {

    // MARK: - RPCResult テスト

    @Suite struct RPCResultTests {

        @Test func successInit() {
            let r = RPCResult()
            #expect(r.success)
            #expect(r.errorMessage == "")
        }

        @Test func failureInit() {
            let r = RPCResult("something went wrong")
            #expect(!r.success)
            #expect(r.errorMessage == "something went wrong")
        }
    }

    // MARK: - DynamicCodingKey テスト

    @Suite struct DynamicCodingKeyTests {

        @Test func stringValueInit() {
            let key = DynamicCodingKey(stringValue: "entityKey")
            #expect(key != nil)
            #expect(key?.stringValue == "entityKey")
        }

        @Test func intValueIsAlwaysNil() {
            let key = DynamicCodingKey(stringValue: "x")
            #expect(key?.intValue == nil)
        }

        @Test func intValueInitReturnsNil() {
            let key = DynamicCodingKey(intValue: 0)
            #expect(key == nil)
        }
    }

    // MARK: - AnyRPCMethod テスト

    @Suite struct AnyRPCMethodTests {

        @Test func broadcastEntityCodingKey() {
            let method = AnyRPCMethod(
                entityKey: "testKey",
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "hi"))
            )
            #expect(method.entityCodingKey == "testKey")
        }

        @Test func unicastEntityCodingKey() {
            let method = AnyRPCMethod(
                entityKey: "myKey",
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 1))
            )
            #expect(method.entityCodingKey == "myKey")
        }

        @Test func broadcastExecuteCallsHandler() {
            let handler = MockHandler()
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "hello"))
            )
            let result = method.execute(on: handler)
            #expect(result.success)
            #expect(handler.broadcastMessages == ["hello"])
        }

        @Test func unicastExecuteCallsHandler() {
            let handler = MockHandler()
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 42))
            )
            let result = method.execute(on: handler)
            #expect(result.success)
            #expect(handler.unicastValues == [42])
        }

        @Test func handlerTypeMismatchReturnsFailure() {
            let wrongHandler: String = "not a MockHandler"
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "x"))
            )
            let result = method.execute(on: wrongHandler)
            #expect(!result.success)
        }

        @Test func broadcastEncodesWithBScopeKey() throws {
            let method = AnyRPCMethod(
                entityKey: "mock",
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "enc"))
            )
            let data = try JSONEncoder().encode(method)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            #expect(json["b"] != nil)
            #expect(json["u"] == nil)
        }

        @Test func unicastEncodesWithUScopeKey() throws {
            let method = AnyRPCMethod(
                entityKey: "mock",
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 7))
            )
            let data = try JSONEncoder().encode(method)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            #expect(json["u"] != nil)
            #expect(json["b"] == nil)
        }

        @Test func alwaysFailBroadcastReturnsFailure() {
            let handler = MockHandler()
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.alwaysFail(.init(reason: "test fail"))
            )
            let result = method.execute(on: handler)
            #expect(!result.success)
            #expect(result.errorMessage == "test fail")
        }
    }

    // MARK: - MethodRegistry テスト

    @Suite struct MethodRegistryTests {
        init() { MethodRegistry.shared.reset() }

        @Test func registerAndExecuteBroadcast() {
            let handler = MockHandler()
            MethodRegistry.shared.register(MockEntity.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "reg-broadcast"))
            )
            let result = MethodRegistry.shared.execute(method)
            #expect(result.success)
            #expect(handler.broadcastMessages.contains("reg-broadcast"))
        }

        @Test func registerAndExecuteUnicast() {
            let handler = MockHandler()
            MethodRegistry.shared.register(MockEntity.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 99))
            )
            let result = MethodRegistry.shared.execute(method)
            #expect(result.success)
            #expect(handler.unicastValues.contains(99))
        }

        @Test func unknownEntityKeyReturnsFailure() {
            let method = AnyRPCMethod(
                entityKey: "unknown_entity_xyz",
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "x"))
            )
            let result = MethodRegistry.shared.execute(method)
            #expect(!result.success)
            #expect(result.errorMessage.contains("unknown_entity_xyz"))
        }

        @Test func updateHandlerReplacesHandler() {
            let h1 = MockHandler()
            let h2 = MockHandler()
            MethodRegistry.shared.register(MockEntity.self, handler: h1)
            MethodRegistry.shared.updateHandler(MockEntity.self, handler: h2)

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 10))
            )
            _ = MethodRegistry.shared.execute(method)
            #expect(h1.unicastValues.isEmpty)
            #expect(h2.unicastValues == [10])
        }

        @Test func resetClearsAllRegistrations() {
            let handler = MockHandler()
            MethodRegistry.shared.register(MockEntity.self, handler: handler)
            MethodRegistry.shared.reset()

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 1))
            )
            let result = MethodRegistry.shared.execute(method)
            #expect(!result.success)
        }

        @Test func decodeRegisteredBroadcastEntity() throws {
            let handler = MockHandler()
            MethodRegistry.shared.register(MockEntity.self, handler: handler)

            let original = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "round-trip"))
            )
            let schema = RequestSchema(peerId: 0, method: original)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)
            let result = MethodRegistry.shared.execute(decoded.method)
            #expect(result.success)
            #expect(handler.broadcastMessages.contains("round-trip"))
        }

        @Test func decodeUnknownEntityKeyThrows() throws {
            let original = AnyRPCMethod(
                entityKey: "neverRegistered",
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "x"))
            )
            let schema = RequestSchema(peerId: 0, method: original)
            let data = try JSONEncoder().encode(schema)
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(RequestSchema.self, from: data)
            }
        }
    }

    // MARK: - RPCRequest ファクトリテスト

    @Suite struct RPCRequestFactoryTests {

        @Test func broadcastRequestHasNilTargetPeerId() {
            let req = MockEntity.request(.ping(.init(message: "bcast")))
            // RPCBroadcastRequest には targetPeerId フィールドがない（コンパイル時に保証）
            #expect(req.entityCodingKey == MockEntity.codingKey)
            #expect(req.allowRetry == true)
        }

        @Test func unicastRequestHasTargetPeerId() {
            let req = MockEntity.request(.setValue(.init(value: 5)), to: 42)
            #expect(req.entityCodingKey == MockEntity.codingKey)
            #expect(req.targetPeerId == 42)
        }

        @Test func alwaysFailBroadcastAllowRetryIsFalse() {
            let req = MockEntity.request(.alwaysFail(.init(reason: "test")))
            #expect(req.allowRetry == false)
        }
    }

    // MARK: - AcknowledgmentEntity テスト

    @Suite struct AcknowledgmentEntityTests {
        init() { MethodRegistry.shared.reset() }

        @Test func encodingDecodingRoundTrip() throws {
            var receivedId: UUID? = nil
            let handler = AcknowledgmentHandler { id in receivedId = id }
            MethodRegistry.shared.register(AcknowledgmentEntity.self, handler: handler)

            let targetId = UUID()
            let method = AnyRPCMethod(
                entityKey: AcknowledgmentEntity.codingKey,
                unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: targetId))
            )
            let schema = RequestSchema(peerId: 0, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)

            let result = MethodRegistry.shared.execute(decoded.method)
            #expect(result.success)
            #expect(receivedId == targetId)
        }

        @Test func executeCallsOnAck() {
            let expectedId = UUID()
            var calledId: UUID? = nil
            let handler = AcknowledgmentHandler { id in calledId = id }
            MethodRegistry.shared.register(AcknowledgmentEntity.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: AcknowledgmentEntity.codingKey,
                unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: expectedId))
            )
            _ = MethodRegistry.shared.execute(method)
            #expect(calledId == expectedId)
        }
    }

    // MARK: - ErrorEntitiy テスト

    @Suite struct ErrorEntitiyTests {
        init() { MethodRegistry.shared.reset() }

        @Test func executeCallsOnError() {
            var receivedMessage: String? = nil
            let handler = ErrorHandler { msg in receivedMessage = msg }
            MethodRegistry.shared.register(ErrorEntitiy.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: ErrorEntitiy.codingKey,
                unicastMethod: ErrorEntitiy.UnicastMethod.error(.init(errorMessage: "oops"))
            )
            let result = MethodRegistry.shared.execute(method)
            #expect(!result.success)
            #expect(result.errorMessage == "oops")
            #expect(receivedMessage == "oops")
        }

        @Test func roundTripEncodeDecode() throws {
            var receivedMessage: String? = nil
            let handler = ErrorHandler { msg in receivedMessage = msg }
            MethodRegistry.shared.register(ErrorEntitiy.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: ErrorEntitiy.codingKey,
                unicastMethod: ErrorEntitiy.UnicastMethod.error(
                    .init(errorMessage: "round-trip error"))
            )
            let schema = RequestSchema(peerId: 99, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)
            _ = MethodRegistry.shared.execute(decoded.method)
            #expect(receivedMessage == "round-trip error")
        }
    }

    // MARK: - RequestSchema ラウンドトリップテスト

    @Suite struct RequestSchemaRoundTripTests {
        init() {
            MethodRegistry.shared.reset()
            MethodRegistry.shared.register(MockEntity.self, handler: MockHandler())
            MethodRegistry.shared.register(SpatialEntity.self, handler: SpatialHandler())
        }

        @Test func broadcastRoundTrip() throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "bcast-rt"))
            )
            let schema = RequestSchema(id: UUID(), peerId: 1, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)

            #expect(decoded.peerId == 1)
            #expect(decoded.method.entityCodingKey == MockEntity.codingKey)
        }

        @Test func unicastRoundTrip() throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 77))
            )
            let schema = RequestSchema(id: UUID(), peerId: 2, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)

            #expect(decoded.peerId == 2)
            #expect(decoded.method.entityCodingKey == MockEntity.codingKey)
        }

        @Test func idPreservedInRoundTrip() throws {
            let id = UUID()
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "id-test"))
            )
            let schema = RequestSchema(id: id, peerId: 0, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)
            #expect(decoded.id == id)
        }

        @Test func spatialEntityRoundTrip() throws {
            let matrix = simd_float4x4(pos: .init(1, 2, 3))
            let method = AnyRPCMethod(
                entityKey: SpatialEntity.codingKey,
                unicastMethod: SpatialEntity.UnicastMethod.move(.init(matrix: matrix))
            )
            let schema = RequestSchema(id: UUID(), peerId: 5, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try JSONDecoder().decode(RequestSchema.self, from: data)
            #expect(decoded.peerId == 5)
            #expect(decoded.method.entityCodingKey == SpatialEntity.codingKey)
        }

        @Test func unknownEntityKeyThrowsOnDecode() throws {
            let method = AnyRPCMethod(
                entityKey: "ghost_entity",
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "x"))
            )
            let schema = RequestSchema(id: UUID(), peerId: 0, method: method)
            let data = try JSONEncoder().encode(schema)
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(RequestSchema.self, from: data)
            }
        }
    }

    // MARK: - RPCTransformableUnicastMethod テスト

    @Suite struct RPCTransformableUnicastMethodTests {

        @Test func applyingCombinesMatrices() {
            let base = simd_float4x4(pos: .init(1, 0, 0))
            let affine = simd_float4x4(pos: .init(0, 2, 0))
            let method = SpatialEntity.UnicastMethod.move(.init(matrix: base))
            let transformed = method.applying(affineMatrix: affine)

            guard case .move(let p) = transformed else {
                Issue.record("expected .move case")
                return
            }
            let expected = affine * base
            #expect(p.matrix.floatList == expected.floatList)
        }
    }

    // MARK: - RPCModel send テスト

    @Suite @MainActor struct RPCModelSendTests {
        let sendWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel

        init() {
            MethodRegistry.shared.reset()
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = MockHandler()
            sendWrapper = send
            mockHandler = handler
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<MockEntity>(handler: handler)]
            )
        }

        @Test func broadcastSendSetsMcPeerIdToZero() throws {
            let req = MockEntity.request(.ping(.init(message: "bcast")))
            model.send(req)
            #expect(sendWrapper.exchangeData.mcPeerId == 0)
            #expect(!sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func unicastSendSetsMcPeerIdToTarget() throws {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: 777)
            model.send(req)
            #expect(sendWrapper.exchangeData.mcPeerId == 777)
            #expect(!sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func sentDataDecodesBackToOriginalEntity() throws {
            let req = MockEntity.request(.ping(.init(message: "decode-back")))
            model.send(req)

            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            #expect(decoded.method.entityCodingKey == MockEntity.codingKey)
        }

        @Test func sendDoesNotExecuteLocalHandler() {
            let req = MockEntity.request(.ping(.init(message: "no-local")))
            model.send(req)
            #expect(mockHandler.broadcastMessages.isEmpty)
        }
    }

    // MARK: - RPCModel run(localOnly:) テスト

    @Suite @MainActor struct RPCModelRunLocalOnlyTests {
        let sendWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel

        init() {
            MethodRegistry.shared.reset()
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = MockHandler()
            sendWrapper = send
            mockHandler = handler
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<MockEntity>(handler: handler)]
            )
        }

        @Test func localOnlyExecutesHandler() {
            let req = MockEntity.localRequest(.setValue(.init(value: 1)))
            let result = model.run(localOnly: req)
            #expect(result.success)
            #expect(mockHandler.unicastValues == [1])
        }

        @Test func localOnlyDoesNotSendData() {
            let req = MockEntity.localRequest(.setValue(.init(value: 2)))
            model.run(localOnly: req)
            #expect(sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func localOnlyUnicastExecutesHandler() {
            let req = MockEntity.localRequest(.setValue(.init(value: 88)))
            let result = model.run(localOnly: req)
            #expect(result.success)
            #expect(mockHandler.unicastValues == [88])
        }

        @Test func localOnlyAlwaysFailReturnsFailure() {
            let req = MockEntity.localRequest(.alwaysFail(.init(reason: "local-fail")))
            let result = model.run(localOnly: req)
            #expect(!result.success)
            #expect(result.errorMessage == "local-fail")
        }
    }

    // MARK: - RPCModel run(remoteOnly:to:) テスト

    @Suite @MainActor struct RPCModelRunRemoteOnlyTests {
        let sendWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel
        let peer1: MCPeerID
        let peer2: MCPeerID

        init() {
            MethodRegistry.shared.reset()
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = MockHandler()
            let p1 = MCPeerID(displayName: "peer-A")
            let p2 = MCPeerID(displayName: "peer-B")
            peers.standby = [p1, p2]
            sendWrapper = send
            mockHandler = handler
            peer1 = p1
            peer2 = p2
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<MockEntity>(handler: handler)]
            )
        }

        @Test func remoteOnlyDoesNotExecuteLocalHandler() {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            model.run(remoteOnly: req)
            #expect(mockHandler.unicastValues.isEmpty)
        }

        @Test func remoteOnlyInheritedUsesRequestTargetPeerId() {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            model.run(remoteOnly: req)  // .inherited
            #expect(sendWrapper.exchangeData.mcPeerId == peer1.hash)
            #expect(!sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func remoteOnlyPeerSendsToSpecificPeer() {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            let result = model.run(remoteOnly: req)
            #expect(result.success)
            #expect(sendWrapper.exchangeData.mcPeerId == peer1.hash)
        }

        @Test func remoteOnlyPeersSendsToEachPeer() {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: 0)
            let results = model.run(remoteOnly: req, toEach: .peers([peer1.hash, peer2.hash]))
            #expect(results.count == 2)
            #expect(results.allSatisfy { $0.success })
        }
    }

    // MARK: - RPCModel run(syncAll:to:) テスト

    @Suite @MainActor struct RPCModelRunSyncAllTests {
        let sendWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel
        let peer1: MCPeerID

        init() {
            MethodRegistry.shared.reset()
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = MockHandler()
            let p1 = MCPeerID(displayName: "sync-peer")
            peers.standby = [p1]
            sendWrapper = send
            mockHandler = handler
            peer1 = p1
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<MockEntity>(handler: handler)]
            )
        }

        @Test func syncAllExecutesLocalAndSendsRemote() {
            let req = MockEntity.request(.ping(.init(message: "sync")))
            let result = model.run(syncAll: req)  // RPCBroadcastRequest → RPCResult
            #expect(mockHandler.broadcastMessages == ["sync"])
            #expect(result.success)
            #expect(!sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func syncAllLocalFailureSkipsRemote() {
            let req = MockEntity.request(.alwaysFail(.init(reason: "sync-fail")))
            let result = model.run(syncAll: req)  // RPCBroadcastRequest → RPCResult
            #expect(!result.success)
            #expect(sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func syncAllToPeer() {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            let result = model.run(syncAll: req)
            #expect(mockHandler.unicastValues == [1])
            #expect(result.success)
            #expect(sendWrapper.exchangeData.mcPeerId == peer1.hash)
        }
    }

    // MARK: - RPCModel run(transforming:requestFor:) テスト

    @Suite @MainActor struct RPCModelRunTransformingClosureTests {
        let sendWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel
        let peer1: MCPeerID

        init() {
            MethodRegistry.shared.reset()
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = MockHandler()
            let p1 = MCPeerID(displayName: "trans-peer")
            peers.standby = [p1]
            sendWrapper = send
            mockHandler = handler
            peer1 = p1
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<MockEntity>(handler: handler)]
            )
        }

        @Test func transformingClosureExecutesLocalForMine() {
            let myHash = model.mcPeerIDUUIDWrapper.mine.hash
            model.run(transforming: .all) { peerId in
                MockEntity.request(.setValue(.init(value: peerId)), to: peerId)
            }
            #expect(mockHandler.unicastValues.contains(myHash))
        }

        @Test func transformingClosureSendsToStandbyPeer() {
            model.run(transforming: .all) { (peerId: Int) -> RPCUnicastRequest? in
                MockEntity.request(.setValue(.init(value: peerId)), to: peerId)
            }
            #expect(!sendWrapper.exchangeData.data.isEmpty)
            #expect(sendWrapper.exchangeData.mcPeerId == peer1.hash)
        }

        @Test func transformingClosureNilSkipsPeer() {
            let results = model.run(transforming: .peer(peer1.hash)) { _ in nil }
            #expect(results.isEmpty)
            #expect(sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func transformingClosureLocalFailureStopsEarly() {
            let myHash = model.mcPeerIDUUIDWrapper.mine.hash
            let results = model.run(transforming: .all) { peerId in
                if peerId == myHash {
                    return MockEntity.request(.alwaysFail(.init(reason: "stop")), to: peerId)
                }
                return MockEntity.request(.setValue(.init(value: peerId)), to: peerId)
            }
            // ローカル失敗 -> peers への送信もスキップ
            #expect(results.count == 1)
            #expect(!results[0].success)
        }
    }

    // MARK: - RPCModel run(transforming:_:_:affineMatrixFor:) テスト

    @Suite @MainActor struct RPCModelRunTransformingAutoTests {
        let sendWrapper: ExchangeDataWrapper
        let spatialHandler: SpatialHandler
        let model: RPCModel
        let peer1: MCPeerID

        init() {
            MethodRegistry.shared.reset()
            let send = ExchangeDataWrapper()
            let receive = ExchangeDataWrapper()
            let peers = MCPeerIDUUIDWrapper()
            let handler = SpatialHandler()
            let p1 = MCPeerID(displayName: "spatial-peer")
            peers.standby = [p1]
            sendWrapper = send
            spatialHandler = handler
            peer1 = p1
            model = RPCModel(
                sendExchangeDataWrapper: send,
                receiveExchangeDataWrapper: receive,
                mcPeerIDUUIDWrapper: peers,
                entities: [RPCEntityRegistration<SpatialEntity>(handler: handler)]
            )
        }

        @Test func transformingAutoExecutesLocalWithOriginalMatrix() {
            let localMatrix = simd_float4x4(pos: .init(1, 0, 0))

            model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: localMatrix))
            ) { _ in
                simd_float4x4(pos: .init(0, 5, 0))
            }

            #expect(!spatialHandler.executedMatrices.isEmpty)
            #expect(spatialHandler.executedMatrices[0].floatList == localMatrix.floatList)
        }

        @Test func transformingAutoSendsAffineAppliedMatrixToPeer() throws {
            let localMatrix = simd_float4x4.identity
            let affine = simd_float4x4(pos: .init(3, 0, 0))

            model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: localMatrix))
            ) { _ in affine }

            let decoded = try JSONDecoder().decode(
                RequestSchema.self, from: sendWrapper.exchangeData.data)
            #expect(decoded.method.entityCodingKey == SpatialEntity.codingKey)
            _ = MethodRegistry.shared.execute(decoded.method)
            let expected = affine * localMatrix
            // spatialHandler.executedMatrices[0] = local, [1] = decoded peer
            #expect(spatialHandler.executedMatrices.count == 2)
            #expect(spatialHandler.executedMatrices[1].floatList == expected.floatList)
        }

        @Test func transformingAutoNilSkipsPeer() {
            let results = model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: .identity))
            ) { _ in nil }
            // peer スキップ -> 送信なし
            #expect(sendWrapper.exchangeData.data.isEmpty)
            // ローカルは実行される
            #expect(!spatialHandler.executedMatrices.isEmpty)
            _ = results
        }

        @Test func transformingAutoWithProviderProperty() {
            let affine = simd_float4x4(pos: .init(0, 1, 0))
            model.affineMatrixProvider = { _ in affine }

            let results = model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: .identity))
            )
            #expect(results.allSatisfy { $0.success })
            #expect(!sendWrapper.exchangeData.data.isEmpty)
        }

        @Test func transformingAutoMissingProviderReturnsError() {
            model.affineMatrixProvider = nil
            let results = model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: .identity))
            )
            #expect(results.count == 1)
            #expect(!results[0].success)
        }
    }

}  // end ImmersiveRPCKitAllTests
