//
//  SwiftUIView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/28.
//

import SwiftUI

struct PreparedView: View {
    private var rpcModel: RPCModel
    var coordinateTransforms: CoordinateTransforms
    
    init(rpcModel: RPCModel, coordinateTransforms: CoordinateTransforms) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
    }
    
    var body: some View {
        Text(coordinateTransforms.session.affineMatrixAtoB.debugDescription)
        Button(action: {
            _ = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.resetPeer))
        }) {
            Text("設定を完了しました")
        }
    }
}

#Preview {
    let send = ExchangeDataWrapper()
    let receive = ExchangeDataWrapper()
    let peers = MCPeerIDUUIDWrapper()
    let coordinateTransforms = CoordinateTransforms()
    
    PreparedView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        ),
        coordinateTransforms: coordinateTransforms
    )
}
