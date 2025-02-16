//
//  AutoMultipeer.swift
//  AutoMultipeer
//
//  Created by John Haney on 4/30/24.
//

import MultipeerConnectivity

public protocol MultipeerMessagable: Hashable, Codable, Sendable {}

public class MultipeerManager {
    public init(serviceName: String, client: Bool = true, server: Bool = true) {
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceName)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceName)
        session = MCSession(peer: myPeerID)
        delegate.manager = self
        delegate.session = session
        session.delegate = delegate
        if server {
            startAdvertising()
        }
        if client {
            startBrowsing()
        }
    }
    
    private let myPeerID = MCPeerID(displayName: UUID().uuidString)
    private let delegate = Delegate()
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let session: MCSession
    fileprivate var continuations: [(any MultipeerMessagable.Type, @Sendable (any MultipeerMessagable) async -> Void)] = []
    fileprivate var dataContinuations: [AsyncStream<Data>.Continuation] = []
    
    deinit {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        advertiser.delegate = nil
        browser.delegate = nil
    }

    fileprivate class Delegate: NSObject {
        var peerState: [MCPeerID: MCSessionState] = [:]
        var manager: MultipeerManager!
        var session: MCSession!
        func handle(_ data: Data, from: MCPeerID) {
            for (type, handler) in manager.continuations {
                Task {
                    let message = try JSONDecoder().decode(type, from: data)
                    await handler(message)
                }
            }
            for handler in manager.dataContinuations {
                Task {
                    _ = handler.yield(data)
                }
            }
        }
    }
    
    private func startBrowsing() {
        browser.delegate = delegate
        browser.startBrowsingForPeers()
    }

    private func startAdvertising() {
        advertiser.delegate = delegate
        advertiser.startAdvertisingPeer()
    }
    
    private func stop() {
        browser.stopBrowsingForPeers()
        browser.delegate = nil

        advertiser.stopAdvertisingPeer()
        advertiser.delegate = nil
    }
    
    public func messages<Message: MultipeerMessagable>() -> AsyncStream<Message> {
        AsyncStream(bufferingPolicy: .bufferingNewest(6)) { continuation in
            self.build(continuation)
        }
    }
    
    public func data() -> AsyncStream<Data> {
        AsyncStream(bufferingPolicy: .bufferingNewest(6)) { continuation in
            self.build(continuation)
        }
    }
    
    public func send<Message: MultipeerMessagable>(_ message: Message, mode: MCSessionSendDataMode) throws {
        guard !delegate.peerState.isEmpty else { return }
        let data = try JSONEncoder().encode(message)
        try session.send(data, toPeers: Array(Set(delegate.peerState.keys).subtracting([myPeerID])), with: mode)
    }
    
    public func send(_ data: Data, mode: MCSessionSendDataMode) throws {
        guard !delegate.peerState.isEmpty else { return }
        try session.send(data, toPeers: Array(Set(delegate.peerState.keys).subtracting([myPeerID])), with: mode)
    }
    
    func build<Message: MultipeerMessagable>(_ continuation: AsyncStream<Message>.Continuation) {
        continuations.append((Message.self, { message in
            if let message = message as? Message {
                Task {
                    _ = continuation.yield(message)
                }
            }
        }))
    }
    
    func build(_ continuation: AsyncStream<Data>.Continuation) {
        dataContinuations.append(continuation)
    }
}

extension MultipeerManager.Delegate: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard peerState[peerID] != .connected else { return }
        peerState[peerID] = .notConnected
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10.0)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    }
}

extension MultipeerManager.Delegate: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension MultipeerManager.Delegate: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        peerState[peerID] = state
        switch state {
        case .notConnected:
            peerState.removeValue(forKey: peerID)
        case .connecting:
            break
        case .connected:
            break
        @unknown default:
            break
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handle(data, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}
