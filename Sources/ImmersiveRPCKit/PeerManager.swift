//
//  PeerManager.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

@preconcurrency import MultipeerConnectivity

@available(visionOS 26.0, *)
@MainActor
public class PeerManager: NSObject {
    private var sendExchangeDataWrapper: ExchangeDataWrapper
    private var receiveExchangeDataWrapper: ExchangeDataWrapper
    private var mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper
    private var sendStreamTask: Task<Void, Never>?
    private let serviceType: String
    public nonisolated let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    public init(
        sendExchangeDataWrapper: ExchangeDataWrapper,
        receiveExchangeDataWrapper: ExchangeDataWrapper,
        mcPeerIDUUIDWrapper: MCPeerIDUUIDWrapper,
        serviceType: String = "ImmersiveRPCKit"
    ) {
        self.sendExchangeDataWrapper = sendExchangeDataWrapper
        self.receiveExchangeDataWrapper = receiveExchangeDataWrapper
        self.mcPeerIDUUIDWrapper = mcPeerIDUUIDWrapper
        self.serviceType = serviceType

        let peerID = mcPeerIDUUIDWrapper.mine
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self

        startSendStreamListener()
    }

    deinit {
        sendStreamTask?.cancel()
    }

    private func startSendStreamListener() {
        sendStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in self.sendExchangeDataWrapper.stream {
                if Task.isCancelled {
                    break
                }
                self.sendExchangeDataDidChange(value)
            }
        }
    }

    func sendExchangeDataDidChange(_ exchangeData: ExchangeData) {
        if exchangeData.mcPeerId != 0 {
            guard
                let peerID = mcPeerIDUUIDWrapper.standby.first(where: {
                    $0.hash == exchangeData.mcPeerId
                })
            else {
                print("Error: PeerID not found")
                return
            }
            sendRPC(exchangeData.data, to: peerID)
        } else {
            sendRPC(exchangeData.data)
        }
    }

    public func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    public func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
    }

    func firstSendMessage() {
        sendMessageForAll("Hello")
    }

    func sendMessageForAll(_ message: String) {
        guard !session.connectedPeers.isEmpty else {
            print("No connected peers")
            return
        }
        guard let messageData = message.data(using: .utf8) else { return }
        do {
            try session.send(messageData, toPeers: session.connectedPeers, with: .unreliable)
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    func sendRPC(_ data: Data) {
        do {
            try session.send(data, toPeers: mcPeerIDUUIDWrapper.standby, with: .unreliable)
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }

    func sendRPC(_ data: Data, to peerID: MCPeerID) {
        do {
            try session.send(data, toPeers: [peerID], with: .unreliable)
        } catch {
            print("Error sending message to \(peerID.displayName): \(error.localizedDescription)")
        }
    }

    func sendMessage(_ message: String) {
        guard let messageData = message.data(using: .utf8) else { return }
        do {
            try session.send(messageData, toPeers: mcPeerIDUUIDWrapper.standby, with: .unreliable)
            print("Send message: \(message)")
        } catch {
            print("Error sending message: \(error.localizedDescription)")
        }
    }
}

@available(visionOS 26.0, *)
extension PeerManager: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            print("Peer \(peerID.displayName) changed state to \(state)")
            if state == .connected {
                // 同じdisplayNameを持つMCPeerIDがいなかった場合、追加する
                if !mcPeerIDUUIDWrapper.standby.contains(where: { $0.displayName == peerID.displayName }) {
                    mcPeerIDUUIDWrapper.standby.append(peerID)
                }
                print("Peer \(peerID.displayName) reconnected/connected. Standby count: \(mcPeerIDUUIDWrapper.standby.count)")
            }
            if state == .notConnected {
                mcPeerIDUUIDWrapper.remove(mcPeerID: peerID)

                // アドバタイズ・ブラウジングを再起動して再接続を待ち受ける
                advertiser.stopAdvertisingPeer()
                browser.stopBrowsingForPeers()

                advertiser.delegate = self
                browser.delegate = self
                advertiser.startAdvertisingPeer()
                browser.startBrowsingForPeers()
            }
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            receiveExchangeDataWrapper.setData(data)
        }
    }

    // Unused delegate methods
    public nonisolated func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}
    public nonisolated func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}
    public nonisolated func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}

@available(visionOS 26.0, *)
extension PeerManager: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    public nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            print("Failed to start advertising: \(error.localizedDescription)")
        }
    }
}

@available(visionOS 26.0, *)
extension PeerManager: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            print("Found peer: \(peerID.displayName)")

            // すでに接続済みのピアは招待しない
            let alreadyConnected = session.connectedPeers.contains(where: {
                $0.displayName == peerID.displayName
            })
            guard !alreadyConnected else {
                print("Peer \(peerID.displayName) is already connected. Skipping invite.")
                return
            }

            // 相互招待を防ぐため、自分のUUIDが相手より辞書順で大きい場合のみ招待する
            // これにより、3台以上でもどちらか一方のみが招待を送る
            let myName = session.myPeerID.displayName
            guard myName > peerID.displayName else {
                print("Peer \(peerID.displayName) will invite us (their UUID is larger). Waiting.")
                return
            }

            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("Lost peer: \(peerID.displayName)")
        }
    }
}
