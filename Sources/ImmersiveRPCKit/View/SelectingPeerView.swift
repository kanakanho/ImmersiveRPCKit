//
//  SelectingPeerView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import SwiftUI

struct SelectingPeerView: View {
    private var rpcModel: RPCModel
    @State var peerIDHash: Int!
    @State private var errorMessage: String = ""

    init(rpcModel: RPCModel) {
        self.rpcModel = rpcModel
    }

    var body: some View {
        VStack {
            Text("2. 近くにいる人を選択").font(.title)
            Divider()
            Picker("", selection: $peerIDHash) {
                Text("選ぶ").tag(nil as Int?)
                ForEach(rpcModel.mcPeerIDUUIDWrapper.standby, id: \.hash) { peerId in
                    Text(String(peerId.displayName)).tag(peerId.hash)
                }
            }
            Spacer()
            Button(action: {
                confirmSelectClient()
            }) {
                Text("選択した相手を確定")
            }

            Spacer()

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }
            Button(action: {
                returnToInitial()
            }) {
                Text("設定をやめる")
            }
        }
    }

    private func confirmSelectClient() {
        if peerIDHash != nil {
            // 通信相手の peerId の登録
            let initPeerRPCResult = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.initOtherPeer(.init(peerId: peerIDHash))))
            if case .failure(let e) = initPeerRPCResult {
                errorMessage = e.message
                return
            }

            // hash値が大きい方をホストとする
            let nextState: CoordinateTransforms.CoordinateSession.PreparationState = rpcModel.mcPeerIDUUIDWrapper.mine.hash > peerIDHash ? .getTransformMatrixHost : .getTransformMatrixClient
            // 次の画面に遷移する
            let setStateRPCResult = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.setState(.init(state: nextState))))
            if case .failure(let e) = setStateRPCResult {
                errorMessage = e.message
            }
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

    SelectingPeerView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        )
    )
}
