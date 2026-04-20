//
//  GetTransformMatrixClientView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import SwiftUI

struct GetTransformMatrixClientView: View {
    private var rpcModel: RPCModel
    private var coordinateTransforms: CoordinateTransforms
    @State private var errorMessage: String = ""

    init(rpcModel: RPCModel, coordinateTransforms: CoordinateTransforms) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
    }

    var body: some View {
        VStack {
            Text("3. 右手の人差し指の位置を確認 \(coordinateTransforms.session.matrixCount + 1) / \(coordinateTransforms.session.matrixCountLimit)").font(.title)
            Divider()

            Text("相手に合わせて、右手の人差し指を合わせてください")

            Divider()
            Spacer()

            Button(action: {
                returnToInitial()
            }) {
                Text("設定をやめる")
            }

            Spacer()
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

    GetTransformMatrixClientView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        ),
        coordinateTransforms: coordinateTransforms
    )
}
