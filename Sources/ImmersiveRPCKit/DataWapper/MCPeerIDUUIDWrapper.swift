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
public class MCPeerIDUUIDWrapper {
    /// 自身の id
    public let myId: UUID
    /// 自身の MCPeerID
    public var mine: MCPeerID
    /// 通信可能な id
    public var standby: [MCPeerID] = []

    public init() {
        self.myId = UUID()
        self.mine = MCPeerID(displayName: myId.uuidString)
    }

    public func remove(mcPeerID: MCPeerID) {
        standby.removeAll { $0 == mcPeerID }
    }
}
