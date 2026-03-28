//
//  InitialView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import SwiftUI

struct InitialView: View {
    private var rpcModel: RPCModel
    @State private var errorMessage = ""

    init(rpcModel: RPCModel) {
        self.rpcModel = rpcModel
    }

    var body: some View {
        VStack {
            Button(action: {
                initPeer()
            }) {
                Text("初期設定を開始します")
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }
        }
    }

    private func initPeer() {
        // 次の画面に遷移
        let setStateRPCResult = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.setState(.init(state: .selecting))))
        if case .failure(let e) = setStateRPCResult {
            errorMessage = e.message
            return
        }
    }
}

#Preview {
    let send = ExchangeDataWrapper()
    let receive = ExchangeDataWrapper()
    let peers = MCPeerIDUUIDWrapper()
    let coordinateTransforms = CoordinateTransforms()

    InitialView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        )
    )
}
