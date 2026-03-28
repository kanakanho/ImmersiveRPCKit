//
//  GetTransformMatrixHostView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import SwiftUI

struct GetTransformMatrixHostView: View {
    private var rpcModel: RPCModel
    var coordinateTransforms: CoordinateTransforms
    @State private var errorMessage: String = ""

    init(rpcModel: RPCModel, coordinateTransforms: CoordinateTransforms) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
    }
    
    var body: some View {
        VStack {
            Text("3. 右手の人差し指の位置を確認 \(coordinateTransforms.matrixCount + 1) / \(coordinateTransforms.matrixCountLimit)").font(.title)
            Divider()
            
            Text("開始ボタンを押した後に、右手の人差し指で相手の右手の人差し指に触れてください")
            Text("約3秒後の位置を取得します")
            
            Button(action: {
                start()
            }){
                Text("\(coordinateTransforms.matrixCount + 1)回目 開始")
            }
            .disabled(coordinateTransforms.requestedTransform)
            
            Divider()
            Spacer()
            
            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red)
            }
            
            Button(action: {
                returnToInitial()
            }){
                Text("設定をやめる")
            }
            
            Spacer()
        }
    }
    
    private func start() {
        let requestTransformRPCResult = rpcModel.run(remoteOnly:  CoordinateTransformEntity.request(.requestTransform, to: coordinateTransforms.otherPeerId))

        if case .failure(let e) = requestTransformRPCResult {
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
    
    GetTransformMatrixHostView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        ),
        coordinateTransforms: coordinateTransforms
    )
}
