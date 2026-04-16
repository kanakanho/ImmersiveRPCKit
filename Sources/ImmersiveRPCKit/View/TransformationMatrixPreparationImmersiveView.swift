//
//  SwiftUIView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/27.
//

import ARKit
import RealityKit
import SwiftUI

struct TransformationMatrixPreparationImmersiveView: View {
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow: OpenWindowAction

    private var rpcModel: RPCModel
    private var coordinateTransforms: CoordinateTransforms

    @State private var rootEntity = Entity()
    @State private var indexFingerTipAnchor = AnchorEntity()
    @State private var rightFingerEntity: ModelEntity = .generateSphere(name: "R", color: SimpleMaterial.Color.white)
    @State private var indexFingerTipGuideBall: ModelEntity = .generateSphere(name: "indexFingerTipGuideBall", color: UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.4), radius: 0.02)

    init(rpcModel: RPCModel, coordinateTransforms: CoordinateTransforms) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
    }

    private var isActive: Bool {
        coordinateTransforms.session.state != .initial
    }

    var body: some View {
        RealityView { content in
            rootEntity.isEnabled = isActive

            let session = SpatialTrackingSession()
            let configuration = SpatialTrackingSession.Configuration(tracking: [.hand])
            let unapprovedCapabilities = await session.run(configuration)
            if let unapprovedCapabilities, unapprovedCapabilities.anchor.contains(.hand) {
                print("User has rejected hand data for your app.")
            } else {
                print("start tracking hand data.")
                indexFingerTipAnchor = AnchorEntity(.hand(AnchoringComponent.Target.Chirality.right, location: .indexFingerTip), trackingMode: .predicted)
                indexFingerTipAnchor.addChild(rightFingerEntity)
                rootEntity.addChild(indexFingerTipAnchor)
            }
            rootEntity.addChild(indexFingerTipGuideBall)
            content.add(rootEntity)
        }
        .onChange(of: coordinateTransforms.session.state) { _, newState in
            rootEntity.isEnabled = newState != .initial
        }
        .onChange(of: coordinateTransforms.requestedTransform) {
            if coordinateTransforms.requestedTransform {
                fingerSignal(flag: true)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    fingerSignal(flag: false)
                    let latestRightIndexFingerCoordinates: simd_float4x4 = .init(
                        pos: rightFingerEntity.position(relativeTo: nil))
                    let setTransformRPCResult = rpcModel.run(
                        sync: CoordinateTransformEntity.request(
                            .setTransform(
                                .init(
                                    peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash,
                                    matrix: latestRightIndexFingerCoordinates
                                )
                            ),
                            to: coordinateTransforms.otherPeerId
                        )
                    )
                    print("座標変換行列を送信: peerId=\(rpcModel.mcPeerIDUUIDWrapper.mine.hash), matrix=\(latestRightIndexFingerCoordinates)")
                    if case .failure(let e) = setTransformRPCResult {
                        print("Failed to set transform: \(e)")
                    }
                }
            }
        }
        .onChange(of: coordinateTransforms.matrixCount) {
            if coordinateTransforms.matrixCount == 0 {
                return
            }

            guard coordinateTransforms.session.state == .getTransformMatrixHost else {
                return
            }

            guard let nextPos: SIMD3<Float> = coordinateTransforms.getNextIndexFingerTipPosition()
            else {
                print("No next index finger tip position available.")
                return
            }
            enableIndexFingerTipGuideBall(position: nextPos)
        }
        .onChange(of: coordinateTransforms.affineMatrixs) { _, newMatrixs in
            disableIndexFingerTipGuideBall()
            rpcModel.affineMatrixProvider = { peerId in newMatrixs[peerId] }
        }
    }

    private func fingerSignal(flag: Bool) {
        if flag {
            let goldColor = UIColor(red: 255 / 255, green: 215 / 255, blue: 0 / 255, alpha: 1.0)
            let material = SimpleMaterial(color: goldColor, isMetallic: true)
            self.rightFingerEntity.model?.materials = [material]
        } else {
            let silverColor = UIColor(red: 220 / 255, green: 220 / 255, blue: 220 / 255, alpha: 1.0)
            let material = SimpleMaterial(color: silverColor, isMetallic: true)
            self.rightFingerEntity.model?.materials = [material]
        }
    }

    private func enableIndexFingerTipGuideBall(position: SIMD3<Float>) {
        indexFingerTipGuideBall.setPosition(position, relativeTo: nil)
        indexFingerTipGuideBall.isEnabled = true
    }

    private func disableIndexFingerTipGuideBall() {
        indexFingerTipGuideBall.isEnabled = false
    }
}

#Preview {
    let send = ExchangeDataWrapper()
    let receive = ExchangeDataWrapper()
    let peers = MCPeerIDUUIDWrapper()
    let coordinateTransforms = CoordinateTransforms()

    TransformationMatrixPreparationImmersiveView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [
                RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)
            ]
        ),
        coordinateTransforms: coordinateTransforms
    )
}
