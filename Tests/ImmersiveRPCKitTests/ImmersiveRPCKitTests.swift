//
//  ImmersiveRPCKitTests.swift
//  ImmersiveRPCKit
//
//  ユニットテスト + 結合テスト
//  RPCModel は per-instance MethodRegistry を持つため、どのテストも独立して安全に並列実行できる。
//

import Foundation
import MultipeerConnectivity
import Testing
import simd

@testable import ImmersiveRPCKit

/// ルートスイート
///
/// RPCModel は per-instance MethodRegistry を持つため、それぞれのテストスイートは完全に独立している。
/// グローバル状態を共有しないため並列実行が安全。
@Suite("ImmersiveRPCKit")
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

    @Suite @MainActor struct AnyRPCMethodTests {

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

    @Suite @MainActor struct MethodRegistryTests {
        // Swift Testing の value-type semantics により各テストで register がクリーンなインスタンスを得る
        let registry = MethodRegistry()

        @Test func registerAndExecuteBroadcast() {
            let handler = MockHandler()
            registry.register(MockEntity.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "reg-broadcast"))
            )
            let result = registry.execute(method)
            #expect(result.success)
            #expect(handler.broadcastMessages.contains("reg-broadcast"))
        }

        @Test func registerAndExecuteUnicast() {
            let handler = MockHandler()
            registry.register(MockEntity.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 99))
            )
            let result = registry.execute(method)
            #expect(result.success)
            #expect(handler.unicastValues.contains(99))
        }

        @Test func unknownEntityKeyReturnsFailure() {
            let method = AnyRPCMethod(
                entityKey: "unknown_entity_xyz",
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "x"))
            )
            let result = registry.execute(method)
            #expect(!result.success)
            #expect(result.errorMessage.contains("unknown_entity_xyz"))
        }

        @Test func updateHandlerReplacesHandler() {
            let h1 = MockHandler()
            let h2 = MockHandler()
            registry.register(MockEntity.self, handler: h1)
            registry.updateHandler(MockEntity.self, handler: h2)

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 10))
            )
            _ = registry.execute(method)
            #expect(h1.unicastValues.isEmpty)
            #expect(h2.unicastValues == [10])
        }

        @Test func resetClearsAllRegistrations() {
            let handler = MockHandler()
            registry.register(MockEntity.self, handler: handler)
            registry.reset()

            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                unicastMethod: MockEntity.UnicastMethod.setValue(.init(value: 1))
            )
            let result = registry.execute(method)
            #expect(!result.success)
        }

        @Test func decodeRegisteredBroadcastEntity() throws {
            let handler = MockHandler()
            let registry = MethodRegistry()
            registry.register(MockEntity.self, handler: handler)

            let original = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "round-trip"))
            )
            let schema = RequestSchema(peerId: 0, method: original)
            let data = try JSONEncoder().encode(schema)
            let decoder = JSONDecoder()
            decoder.userInfo[.methodRegistry] = registry
            let decoded = try decoder.decode(RequestSchema.self, from: data)
            let result = registry.execute(decoded.method)
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
            let decoder = JSONDecoder()
            decoder.userInfo[.methodRegistry] = MethodRegistry()  // 空のレジストリ
            #expect(throws: (any Error).self) {
                _ = try decoder.decode(RequestSchema.self, from: data)
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

    @Suite @MainActor struct AcknowledgmentEntityTests {

        @Test func encodingDecodingRoundTrip() throws {
            var receivedId: UUID? = nil
            let handler = AcknowledgmentHandler { id in receivedId = id }
            let registry = MethodRegistry()
            registry.register(AcknowledgmentEntity.self, handler: handler)

            let targetId = UUID()
            let method = AnyRPCMethod(
                entityKey: AcknowledgmentEntity.codingKey,
                unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: targetId))
            )
            let schema = RequestSchema(peerId: 0, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoder = JSONDecoder()
            decoder.userInfo[.methodRegistry] = registry
            let decoded = try decoder.decode(RequestSchema.self, from: data)

            let result = registry.execute(decoded.method)
            #expect(result.success)
            #expect(receivedId == targetId)
        }

        @Test func executeCallsOnAck() {
            let expectedId = UUID()
            var calledId: UUID? = nil
            let handler = AcknowledgmentHandler { id in calledId = id }
            let registry = MethodRegistry()
            registry.register(AcknowledgmentEntity.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: AcknowledgmentEntity.codingKey,
                unicastMethod: AcknowledgmentEntity.UnicastMethod.ack(.init(requestId: expectedId))
            )
            _ = registry.execute(method)
            #expect(calledId == expectedId)
        }
    }

    // MARK: - ErrorEntitiy テスト

    @Suite @MainActor struct ErrorEntitiyTests {

        @Test func executeCallsOnError() {
            var receivedMessage: String? = nil
            let handler = ErrorHandler { msg in receivedMessage = msg }
            let registry = MethodRegistry()
            registry.register(ErrorEntitiy.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: ErrorEntitiy.codingKey,
                unicastMethod: ErrorEntitiy.UnicastMethod.error(.init(errorMessage: "oops"))
            )
            let result = registry.execute(method)
            #expect(!result.success)
            #expect(result.errorMessage == "oops")
            #expect(receivedMessage == "oops")
        }

        @Test func roundTripEncodeDecode() throws {
            var receivedMessage: String? = nil
            let handler = ErrorHandler { msg in receivedMessage = msg }
            let registry = MethodRegistry()
            registry.register(ErrorEntitiy.self, handler: handler)

            let method = AnyRPCMethod(
                entityKey: ErrorEntitiy.codingKey,
                unicastMethod: ErrorEntitiy.UnicastMethod.error(
                    .init(errorMessage: "round-trip error"))
            )
            let schema = RequestSchema(peerId: 99, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoder = JSONDecoder()
            decoder.userInfo[.methodRegistry] = registry
            let decoded = try decoder.decode(RequestSchema.self, from: data)
            _ = registry.execute(decoded.method)
            #expect(receivedMessage == "round-trip error")
        }
    }

    // MARK: - RequestSchema ラウンドトリップテスト

    @Suite @MainActor struct RequestSchemaRoundTripTests {
        let registry: MethodRegistry
        let decoder: JSONDecoder

        init() {
            let r = MethodRegistry()
            r.register(MockEntity.self, handler: MockHandler())
            r.register(SpatialEntity.self, handler: SpatialHandler())
            let d = JSONDecoder()
            d.userInfo[.methodRegistry] = r
            registry = r
            decoder = d
        }

        @Test func broadcastRoundTrip() throws {
            let method = AnyRPCMethod(
                entityKey: MockEntity.codingKey,
                broadcastMethod: MockEntity.BroadcastMethod.ping(.init(message: "bcast-rt"))
            )
            let schema = RequestSchema(id: UUID(), peerId: 1, method: method)
            let data = try JSONEncoder().encode(schema)
            let decoded = try decoder.decode(RequestSchema.self, from: data)

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
            let decoded = try decoder.decode(RequestSchema.self, from: data)

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
            let decoded = try decoder.decode(RequestSchema.self, from: data)
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
            let decoded = try decoder.decode(RequestSchema.self, from: data)
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
                _ = try decoder.decode(RequestSchema.self, from: data)
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

        @Test func broadcastSendSetsMcPeerIdToZero() async throws {
            let req = MockEntity.request(.ping(.init(message: "bcast")))
            model.send(req)
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(sent.mcPeerId == 0)
            #expect(!sent.data.isEmpty)
        }

        @Test func unicastSendSetsMcPeerIdToTarget() async throws {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: 777)
            model.send(req)
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(sent.mcPeerId == 777)
            #expect(!sent.data.isEmpty)
        }

        @Test func sentDataDecodesBackToOriginalEntity() async throws {
            let req = MockEntity.request(.ping(.init(message: "decode-back")))
            model.send(req)
            let sent = try #require(await nextValue(from: sendWrapper))
            let decoded = try decodeSentSchema(from: sent, using: model.methodRegistry)
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

        @Test func localOnlyDoesNotSendData() async {
            let req = MockEntity.localRequest(.setValue(.init(value: 2)))
            model.run(localOnly: req)
            let sent = await nextValue(from: sendWrapper)
            #expect(sent == nil)
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

        @Test func remoteOnlyInheritedUsesRequestTargetPeerId() async throws {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            model.run(remoteOnly: req)  // .inherited
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(sent.mcPeerId == peer1.hash)
            #expect(!sent.data.isEmpty)
        }

        @Test func remoteOnlyPeerSendsToSpecificPeer() async throws {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            let result = model.run(remoteOnly: req)
            #expect(result.success)
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(sent.mcPeerId == peer1.hash)
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

        @Test func syncAllExecutesLocalAndSendsRemote() async throws {
            let req = MockEntity.request(.ping(.init(message: "sync")))
            let result = model.run(syncAll: req)  // RPCBroadcastRequest → RPCResult
            #expect(mockHandler.broadcastMessages == ["sync"])
            #expect(result.success)
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(!sent.data.isEmpty)
        }

        @Test func syncAllLocalFailureSkipsRemote() async {
            let req = MockEntity.request(.alwaysFail(.init(reason: "sync-fail")))
            let result = model.run(syncAll: req)  // RPCBroadcastRequest → RPCResult
            #expect(!result.success)
            let sent = await nextValue(from: sendWrapper)
            #expect(sent == nil)
        }

        @Test func syncToPeer() async throws {
            let req = MockEntity.request(.setValue(.init(value: 1)), to: peer1.hash)
            let result = model.run(sync: req)
            #expect(mockHandler.unicastValues == [1])
            #expect(result.success)
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(sent.mcPeerId == peer1.hash)
        }
    }

    // MARK: - RPCModel run(transforming:requestFor:) テスト

    @Suite @MainActor struct RPCModelRunTransformingClosureTests {
        let sendWrapper: ExchangeDataWrapper
        let mockHandler: MockHandler
        let model: RPCModel
        let peer1: MCPeerID

        init() {
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

        @Test func transformingClosureSendsToStandbyPeer() async throws {
            model.run(transforming: .all) { (peerId: Int) -> RPCUnicastRequest? in
                MockEntity.request(.setValue(.init(value: peerId)), to: peerId)
            }
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(!sent.data.isEmpty)
            #expect(sent.mcPeerId == peer1.hash)
        }

        @Test func transformingClosureNilSkipsPeer() async {
            let results = model.run(transforming: .peer(peer1.hash)) { _ in nil }
            #expect(results.isEmpty)
            let sent = await nextValue(from: sendWrapper)
            #expect(sent == nil)
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

        @Test func transformingAutoSendsAffineAppliedMatrixToPeer() async throws {
            let localMatrix = simd_float4x4.identity
            let affine = simd_float4x4(pos: .init(3, 0, 0))

            model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: localMatrix))
            ) { _ in affine }

            let sent = try #require(await nextValue(from: sendWrapper))
            let decoded = try decodeSentSchema(from: sent, using: model.methodRegistry)
            #expect(decoded.method.entityCodingKey == SpatialEntity.codingKey)
            _ = model.methodRegistry.execute(decoded.method)
            let expected = affine * localMatrix
            // spatialHandler.executedMatrices[0] = local, [1] = decoded peer
            #expect(spatialHandler.executedMatrices.count == 2)
            #expect(spatialHandler.executedMatrices[1].floatList == expected.floatList)
        }

        @Test func transformingAutoNilSkipsPeer() async {
            let results = model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: .identity))
            ) { _ in nil }
            // peer スキップ -> 送信なし
            let sent = await nextValue(from: sendWrapper)
            #expect(sent == nil)
            // ローカルは実行される
            #expect(!spatialHandler.executedMatrices.isEmpty)
            _ = results
        }

        @Test func transformingAutoWithProviderProperty() async throws {
            let affine = simd_float4x4(pos: .init(0, 1, 0))
            model.affineMatrixProvider = { _ in affine }

            let results = model.run(
                transforming: .all,
                SpatialEntity.self,
                .move(.init(matrix: .identity))
            )
            #expect(results.allSatisfy { $0.success })
            let sent = try #require(await nextValue(from: sendWrapper))
            #expect(!sent.data.isEmpty)
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

    // MARK: - CoordinateTransforms テスト

    @Suite struct CoordinateTransformsTests {

        @Test func setTransformFailsWhenPeersAreNotInitialized() {
            let transforms = CoordinateTransforms()

            let result = transforms.setTransform(
                param: .init(peerId: 1, matrix: .identity)
            )

            #expect(!result.success)
            #expect(result.errorMessage.contains("peerId が未初期化"))
        }

        @Test func initPeerStateIsStoredInSession() {
            let transforms = CoordinateTransforms()

            let initMine = transforms.initMyPeer(param: .init(peerId: 100))
            let initOther = transforms.initOtherPeer(param: .init(peerId: 200))

            #expect(initMine.success)
            #expect(initOther.success)
            #expect(transforms.session.myPeerId == 100)
            #expect(transforms.session.otherPeerId == 200)
            #expect(transforms.session.isMyPeerInitialized)
            #expect(transforms.session.isOtherPeerInitialized)
        }

        @Test func requestTransformRequiresValidState() {
            let transforms = CoordinateTransforms()

            let failed = transforms.requestTransform()
            #expect(!failed.success)

            _ = transforms.setState(param: .init(state: .getTransformMatrixHost))
            let success = transforms.requestTransform()
            #expect(success.success)
            #expect(transforms.session.requestedTransform)
        }

        @Test func setTransformAppendsToABasedOnHostAndClientPeer() {
            let transforms = CoordinateTransforms()
            _ = transforms.initMyPeer(param: .init(peerId: 100))
            _ = transforms.initOtherPeer(param: .init(peerId: 200))

            let hostMatrix = simd_float4x4(pos: .init(1, 0, 0))
            let clientMatrix = simd_float4x4(pos: .init(0, 1, 0))

            let hostResult = transforms.setTransform(param: .init(peerId: 200, matrix: hostMatrix))
            let clientResult = transforms.setTransform(param: .init(peerId: 100, matrix: clientMatrix))

            #expect(hostResult.success)
            #expect(clientResult.success)
            #expect(transforms.session.A.count == 1)
            #expect(transforms.session.B.count == 1)
            #expect(transforms.session.A[0].floatList == hostMatrix.floatList)
            #expect(transforms.session.B[0].floatList == clientMatrix.floatList)
        }

        @Test func matrixCountReachesLimitThenStateBecomesConfirm() {
            let transforms = CoordinateTransforms()
            _ = transforms.initMyPeer(param: .init(peerId: 100))
            _ = transforms.initOtherPeer(param: .init(peerId: 200))

            for i in 0..<4 {
                let matrix = simd_float4x4(pos: .init(Float(i), 0, 0))
                let result = transforms.setTransform(param: .init(peerId: 200, matrix: matrix))
                #expect(result.success)
            }

            #expect(transforms.session.matrixCount == 4)
            #expect(transforms.session.state == .confirm)
        }

        @Test func resetPeerClearsSessionButKeepsPersistentAffineMaps() {
            let transforms = CoordinateTransforms()
            transforms.affineMatrixs[99] = .identity

            _ = transforms.initMyPeer(param: .init(peerId: 100))
            _ = transforms.initOtherPeer(param: .init(peerId: 200))
            _ = transforms.setState(param: .init(state: .prepared))
            let resetResult = transforms.resetPeer()

            #expect(resetResult.success)
            #expect(transforms.session.state == .initial)
            #expect(!transforms.session.isMyPeerInitialized)
            #expect(!transforms.session.isOtherPeerInitialized)
            #expect(transforms.affineMatrixs[99] != nil)
        }

        @Test func setAffineMatrixUsesHostDirection() {
            let transforms = CoordinateTransforms()
            transforms.session.myPeerId = 300
            transforms.session.otherPeerId = 200
            transforms.session.isMyPeerInitialized = true
            transforms.session.isOtherPeerInitialized = true
            transforms.session.affineMatrixAtoB = simd_float4x4(pos: .init(1, 2, 3))

            let result = transforms.setAffineMatrix()

            #expect(result.success)
            #expect(transforms.affineMatrixs[200]?.floatList == transforms.session.affineMatrixAtoB.floatList)
        }

        @Test func setAffineMatrixUsesClientDirection() {
            let transforms = CoordinateTransforms()
            transforms.session.myPeerId = 100
            transforms.session.otherPeerId = 200
            transforms.session.isMyPeerInitialized = true
            transforms.session.isOtherPeerInitialized = true
            transforms.session.affineMatrixBtoA = simd_float4x4(pos: .init(4, 5, 6))

            let result = transforms.setAffineMatrix()

            #expect(result.success)
            #expect(transforms.affineMatrixs[200]?.floatList == transforms.session.affineMatrixBtoA.floatList)
        }
    }

}  // end ImmersiveRPCKitAllTests
