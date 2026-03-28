//
//  MCPeerIDUUIDWrapper.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import MultipeerConnectivity

/// 各端末の接続状況を管理するラッパー
@available(visionOS 26.0, *)
@Observable
class MCPeerIDUUIDWrapper {
    /// 自身の id
    let myId: UUID
    /// 自身の MCPeerID
    var mine: MCPeerID
    /// 通信可能な id
    var standby: [MCPeerID] = []
    
    init() {
        self.myId = UUID()
        self.mine = MCPeerID(displayName: myId.uuidString)
    }
    
    func remove(mcPeerID: MCPeerID) {
        standby.removeAll { $0 == mcPeerID }
    }
}
