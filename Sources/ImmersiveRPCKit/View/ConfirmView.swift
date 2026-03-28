//
//  ConfirmView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import SwiftUI

struct ConfirmView: View {
    private var rpcModel: RPCModel
    private var coordinateTransforms: CoordinateTransforms
    @State private var errorMessage = ""

    init(rpcModel: RPCModel, coordinateTransforms: CoordinateTransforms) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
    }

    var body: some View {
        VStack {
            Text("A").font(.title)
            Text(coordinateTransforms.session.A.description)

            Text("B").font(.title)
            Text(coordinateTransforms.session.B.description)

            Button(action: {
                prepared()
            }) {
                Text("設定を完了する")
            }

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
                Button(action: {
                    returnToInitial()
                }) {
                    Text("設定をやめる")
                }
            }
        }
    }

    private func prepared() {
        let clacAffineMatrixAtoBRPCResult = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.clacAffineMatrix))
        if case .failure(let e) = clacAffineMatrixAtoBRPCResult {
            errorMessage = e.message
            return
        }

        _ = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.setAffineMatrix))

        let setStateRPCResult = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.setState(.init(state: .prepared))))
        if case .failure(let e) = setStateRPCResult {
            errorMessage = e.message
        }
    }

    private func returnToInitial() {
        _ = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.resetPeer))
    }
}

#Preview {
    let send = ExchangeDataWrapper()
    let receive = ExchangeDataWrapper()
    let peers = MCPeerIDUUIDWrapper()
    let coordinateTransforms = CoordinateTransforms()

    ConfirmView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        ),
        coordinateTransforms: coordinateTransforms
    )
}
