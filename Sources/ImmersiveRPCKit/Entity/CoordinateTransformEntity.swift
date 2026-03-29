//
//  CoordinateTransformModel.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation
import MultipeerConnectivity
import simd

@available(visionOS 26.0, *)
@Observable
public class CoordinateTransforms {
    public struct CoordinateSession {
        /// 座標変換行列のリスト
        public var A: [simd_float4x4]
        /// 座標変換行列のリスト
        public var B: [simd_float4x4]
        /// 座標変換行列の状態
        public var state: PreparationState
        /// A側の座標変換行列からB側の座標変換行列へのアフィン行列
        public var affineMatrixAtoB: simd_float4x4
        /// B側の座標変換行列からA側の座標変換行列へのアフィン行列
        public var affineMatrixBtoA: simd_float4x4

        public enum PreparationState: Codable, Sendable {
            case initial
            case selecting
            case getTransformMatrixHost
            case getTransformMatrixClient
            case confirm
            case prepared
        }

        public init(state: PreparationState = .initial) {
            self.A = []
            self.B = []
            self.state = state
            self.affineMatrixAtoB = .init()
            self.affineMatrixBtoA = .init()
        }
    }

    public var session: CoordinateSession = .init()
    /// 座標の交換を管理するフラグ
    var requestedTransform: Bool = false
    ///  座標を交換する回数
    var matrixCount: Int = 0 {
        didSet {
            if matrixCount >= matrixCountLimit {
                session.state = .confirm
            }
        }
    }
    ///  座標を交換する回数の上限
    var matrixCountLimit: Int = 4

    /// 交換元の id
    public var myPeerId: Int = 0
    /// 交換先の id
    public var otherPeerId: Int = 0
    /// 計算が完了したアフィン行列
    public var affineMatrixs: [Int: simd_float4x4] = [:]

    public init() {}

    public struct InitMyPeerParam: Codable, Sendable {
        /// アクセス元の peerIdHash
        public let peerId: Int
        public init(peerId: Int) { self.peerId = peerId }
    }
    ///  初期化
    ///  座標交換の工程の1つ目
    /// - Parameter param: `InitPeerParam`
    /// - Returns: `RPCResult`
    func initMyPeer(param: InitMyPeerParam) -> RPCResult {
        // 新しく設定を始める CoordinateTransformEntity を定義
        session = CoordinateSession(state: .initial)
        myPeerId = param.peerId
        return .success(())
    }

    public struct InitOtherPeerParam: Codable, Sendable {
        /// アクセス先の peerIdHash
        public let peerId: Int
        public init(peerId: Int) { self.peerId = peerId }
    }

    /// 相手の PeerId を登録
    /// 座標交換の工程の2つ目
    /// - Parameter param: `InitOtherPeerParam`
    /// - Returns: `RPCResult`
    func initOtherPeer(param: InitOtherPeerParam) -> RPCResult {
        otherPeerId = param.peerId
        return .success(())
    }

    ///  初期化
    ///  - Parameter param: `ResetPeerParam`
    ///  - Returns: `RPCResult`
    func resetPeer() -> RPCResult {
        // 初期化
        session = CoordinateSession(state: .initial)
        otherPeerId = 0
        matrixCount = 0
        return .success(())
    }

    /// 座標変換行列の取得を要求
    /// - Parameter param: `RequestTransform`
    /// - Returns: `RPCResult`
    func requestTransform() -> RPCResult {
        guard session.state == .getTransformMatrixHost || session.state == .getTransformMatrixClient
        else {
            return .failure(RPCError("requestTransform: 不正な状態 \(session.state) で呼び出されました"))
        }
        requestedTransform = true
        return .success(())
    }

    public struct SetTransformParam: Codable, Sendable {
        /// リクエスト元の peerIdHash
        public let peerId: Int
        public let matrix: simd_float4x4
        public init(peerId: Int, matrix: simd_float4x4) {
            self.peerId = peerId
            self.matrix = matrix
        }
    }

    func setTransform(param: SetTransformParam) -> RPCResult {
        guard session.state == .getTransformMatrixHost || session.state == .getTransformMatrixClient
        else {
            return .failure(RPCError("setTransform: 不正な状態 \(session.state) で呼び出されました"))
        }
        if myPeerId == param.peerId {
            if myPeerId > otherPeerId {
                session.A.append(param.matrix)
                matrixCount = session.A.count
            } else {
                session.B.append(param.matrix)
                matrixCount = session.B.count
            }
        } else {
            if myPeerId > otherPeerId {
                session.B.append(param.matrix)
                matrixCount = session.B.count
            } else {
                session.A.append(param.matrix)
                matrixCount = session.A.count
            }
        }
        requestedTransform = false

        return .success(())
    }

    public struct SetATransformParam: Codable, Sendable {
        public let A: simd_float4x4
        public init(A: simd_float4x4) { self.A = A }
    }

    ///  A側の Peer に座標変換行列を追加
    ///  - Parameter param: `SetATransformParam`
    ///  - Returns: `RPCResult`
    func setATransform(param: SetATransformParam) -> RPCResult {
        guard session.state == .getTransformMatrixHost || session.state == .getTransformMatrixClient
        else {
            return .failure(RPCError("setATransform: 不正な状態 \(session.state) で呼び出されました"))
        }
        session.A.append(param.A)
        return .success(())
    }

    public struct SetBTransformParam: Codable, Sendable {
        public let B: simd_float4x4
        public init(B: simd_float4x4) { self.B = B }
    }

    ///  B側の Peer に座標変換行列を追加
    ///  - Parameter param: `SetBTransformParam`
    ///  - Returns: `RPCResult`
    func setBTransform(param: SetBTransformParam) -> RPCResult {
        guard session.state == .getTransformMatrixHost || session.state == .getTransformMatrixClient
        else {
            return .failure(RPCError("setBTransform: 不正な状態 \(session.state) で呼び出されました"))
        }
        session.B.append(param.B)
        return .success(())
    }

    public struct SetStateParam: Codable, Sendable {
        public let state: CoordinateSession.PreparationState
        public init(state: CoordinateSession.PreparationState) { self.state = state }
    }

    ///  座標変換行列の状態を変更
    ///  - Parameter param: `SetStateParam`
    ///  - Returns: `RPCResult`
    func setState(param: SetStateParam) -> RPCResult {
        session.state = param.state
        return .success(())
    }

    ///  アフィン行列を計算
    ///  - Parameters:
    ///     - A: A側の座標変換行列のリスト
    ///     - B: B側の座標変換行列のリスト
    ///  - Returns: アフィン行列 `simd_float4x4`
    func calculateTransformationMatrix(A: [[[Float]]], B: [[[Float]]]) -> [[Double]] {
        let AMatrix: [[[Double]]] = A.map {
            $0.toDoubleList().transpose4x4
        }
        let BMatrix: [[[Double]]] = B.map {
            $0.toDoubleList().transpose4x4
        }
        return calcAffineMatrix(AMatrix, BMatrix)
    }

    ///  アフィン行列を計算
    ///  - Parameter param: `ClacAffineMatrixParam`
    ///  - Returns: `RPCResult`
    func clacAffineMatrix() -> RPCResult {
        guard session.state == .confirm else {
            return .failure(
                RPCError("clacAffineMatrix: confirm 状態でないため計算できません (current: \(session.state))"))
        }
        let A = session.A
        let B = session.B

        // それぞれの要紤0が4つ存在しなければエラーを返す
        if A.count != 4 || B.count != 4 {
            return .failure(RPCError("座標変換行列は4つ必要です"))
        }

        // ここで座標変換行列を計算する処理を追加
        let affineMatrix = calculateTransformationMatrix(
            A: A.map { $0.floatList },
            B: B.map { $0.floatList }
        )
        session.affineMatrixAtoB = affineMatrix.tosimd_float4x4()
        session.affineMatrixBtoA = affineMatrix.tosimd_float4x4().inverse
        return .success(())
    }

    func getAffineMatrixAtoB(peerId: Int) -> (simd_float4x4, Bool) {
        if session.affineMatrixAtoB == .init() {
            return (.init(), false)
        }
        return (session.affineMatrixAtoB, true)
    }

    func setAffineMatrix() -> RPCResult {
        if myPeerId > otherPeerId {
            affineMatrixs[otherPeerId] = session.affineMatrixAtoB
        } else {
            affineMatrixs[otherPeerId] = session.affineMatrixBtoA
        }
        return .success(())
    }

    func getNextIndexFingerTipPosition() -> SIMD3<Float>? {
        var firstRightFingerMatrix: SIMD3<Float> = .init()
        if myPeerId < otherPeerId {
            firstRightFingerMatrix = session.B[0].position
        } else {
            print("is not a host")
            return nil
        }

        if matrixCount == 1 {
            firstRightFingerMatrix = firstRightFingerMatrix + SIMD3<Float>(0, 0.3, 0)
        } else if matrixCount == 2 {
            firstRightFingerMatrix = firstRightFingerMatrix + SIMD3<Float>(0.3, 0, 0)
        } else if matrixCount == 3 {
            firstRightFingerMatrix = firstRightFingerMatrix + SIMD3<Float>(0, 0, 0.3)
        }

        print("firstRightFingerMatrix: \(firstRightFingerMatrix)")

        return firstRightFingerMatrix
    }

    /// 初期化地点のボールを描画するための座標を取得する関数
    /// - Returns:
    ///     - 失敗した場合に理由を与える
    ///     - 座標
    ///     - A側かどうか
    func initBallTransform() -> (RPCResult, simd_float4x4) {
        if affineMatrixs.isEmpty {
            return (.failure(RPCError("計算し終わったアフィン行列が空です")), .init())
        }
        if myPeerId == 0 || otherPeerId == 0 {
            return (.failure(RPCError("座標を取得するPeerが取得できません")), .init())
        }
        if session.A.isEmpty || session.B.isEmpty {
            return (.failure(RPCError("座標変換行列が取得できません")), .init())
        }

        guard let affineMatrix = affineMatrixs[otherPeerId] else {
            return (.failure(RPCError("座標変換行列が取得できません")), .init())
        }

        var fristRightFingerPos: SIMD3<Float> = .init()
        if myPeerId > otherPeerId {
            fristRightFingerPos = session.A[0].position
        } else {
            fristRightFingerPos = session.B[0].position
        }

        let fristRightFingerMatrix = simd_float4x4(pos: fristRightFingerPos)

        return (
            .success(()),
            affineMatrix.inverse * fristRightFingerMatrix
        )
    }
}

///  座標変換処理を行う構造体
@available(visionOS 26.0, *)
public struct CoordinateTransformEntity: RPCEntity {
    /// JSON での識別キー
    public static let codingKey = "coordinateTransformEntity"

    // MARK: - BroadcastMethod（全 Peer へ送信）

    public typealias BroadcastMethod = NoMethod<CoordinateTransforms>

    // MARK: - UnicastMethod（特定 Peer へ送信）

    public enum UnicastMethod: RPCUnicastMethod {
        public typealias Handler = CoordinateTransforms

        case initMyPeer(CoordinateTransforms.InitMyPeerParam)
        case initOtherPeer(CoordinateTransforms.InitOtherPeerParam)
        case setTransform(CoordinateTransforms.SetTransformParam)
        case setATransform(CoordinateTransforms.SetATransformParam)
        case setBTransform(CoordinateTransforms.SetBTransformParam)
        case requestTransform
        case clacAffineMatrix
        case setState(CoordinateTransforms.SetStateParam)
        case setAffineMatrix
        case resetPeer

        // MARK: execute
        public func execute(on handler: Handler) -> RPCResult {
            switch self {
            case .initMyPeer(let p):
                return handler.initMyPeer(param: p)
            case .initOtherPeer(let p):
                return handler.initOtherPeer(param: p)
            case .setTransform(let p):
                return handler.setTransform(param: p)
            case .setATransform(let p):
                return handler.setATransform(param: p)
            case .setBTransform(let p):
                return handler.setBTransform(param: p)
            case .requestTransform:
                return handler.requestTransform()
            case .clacAffineMatrix:
                return handler.clacAffineMatrix()
            case .setState(let p):
                return handler.setState(param: p)
            case .setAffineMatrix:
                return handler.setAffineMatrix()
            case .resetPeer:
                return handler.resetPeer()
            }
        }

        // MARK: Codable
        public enum CodingKeys: CodingKey {
            case initMyPeer
            case initOtherPeer
            case setTransform
            case setATransform
            case setBTransform
            case requestTransform
            case clacAffineMatrix
            case setState
            case setAffineMatrix
            case resetPeer
        }
    }
}
