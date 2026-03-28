//
//  TransformationMatrixPreparationView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation
import SwiftUI

enum SharedCoordinateState {
    case prepare
    case sharing
    case shared
}

public struct TransformationMatrixPreparationView: View {
    var rpcModel: RPCModel
    var coordinateTransforms: CoordinateTransforms
    
    init(
        rpcModel: RPCModel,
        coordinateTransforms: CoordinateTransforms
    ) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
    }
    
    public var body: some View {
        VStack {
            NavigationStack {
                switch coordinateTransforms.session.state {
                case .initial:
                    InitialView(rpcModel: rpcModel)
                case .selecting:
                    SelectingPeerView(rpcModel: rpcModel)
                case .getTransformMatrixHost:
                    GetTransformMatrixHostView(rpcModel: rpcModel, coordinateTransforms: coordinateTransforms)
                case .getTransformMatrixClient:
                    GetTransformMatrixClientView(rpcModel: rpcModel, coordinateTransforms: coordinateTransforms)
                case .confirm:
                    ConfirmView(rpcModel: rpcModel, coordinateTransforms: coordinateTransforms)
                case .prepared:
                    PreparedView(rpcModel: rpcModel, coordinateTransforms: coordinateTransforms)
                }
            }
            Spacer()
        }
        .onAppear {
            _ = rpcModel.run(localOnly: CoordinateTransformEntity.localRequest(.initMyPeer(.init(peerId: rpcModel.mcPeerIDUUIDWrapper.mine.hash))))
        }
    }
}

#Preview {
    let send = ExchangeDataWrapper()
    let receive = ExchangeDataWrapper()
    let peers = MCPeerIDUUIDWrapper()
    let coordinateTransforms = CoordinateTransforms()
    
    TransformationMatrixPreparationView(
        rpcModel: RPCModel(
            sendExchangeDataWrapper: send,
            receiveExchangeDataWrapper: receive,
            mcPeerIDUUIDWrapper: peers,
            entities: [RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)]
        ),
        coordinateTransforms: coordinateTransforms
    )
}
