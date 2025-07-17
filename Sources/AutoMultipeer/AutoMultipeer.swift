//
//  AutoMultipeer.swift
//  AutoMultipeer
//
//  Created by John Haney on 4/30/24.
//

import MultipeerConnectivity

public protocol MultipeerMessagable: Hashable, Codable, Sendable {
    static var typeIdentifier: UInt8 { get }
}

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
    let encoder = JSONEncoder()
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
        let decoder = JSONDecoder()
        func handle(_ data: Data, from: MCPeerID) {
            guard let (count, consumed) = try? Int.unpack(data: data)
            else {
                print("error unpacking count")
                return
            }
            var offset = consumed
            let typeIdentifier = data[offset]
            offset += 1
            guard data.count == offset + count
            else {
                print("data mismatch: \(data.count) vs \(offset + count)")
                return
            }
            
            guard let manager = manager else { return }
            if typeIdentifier == 0 {
                for handler in manager.dataContinuations {
                    _ = handler.yield(data)
                }
            } else {
                for (type, handler) in manager.continuations {
                    if type.typeIdentifier == typeIdentifier {
                        var messageData = data
                        messageData.removeFirst(offset)
                        do {
                            let message = try decoder.decode(type, from: messageData)
                            Task {
                                await handler(message)
                            }
                        } catch {
                            print("error decoding \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
    
    public func startBrowsing() {
        delegate.manager = self
        browser.delegate = delegate
        browser.startBrowsingForPeers()
        print("browser starting…")
    }

    public func startAdvertising() {
        delegate.manager = self
        advertiser.delegate = delegate
        advertiser.startAdvertisingPeer()
        print("advertiser starting…")
    }
    
    public func stop() {
        delegate.manager = nil
        browser.stopBrowsingForPeers()
        print("browser STOPPED")
        browser.delegate = nil

        advertiser.stopAdvertisingPeer()
        print("advertiser STOPPED")
        advertiser.delegate = nil
    }
    
    public func messages<M: MultipeerMessagable>() -> AsyncStream<M> {
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
        let remotePeers = Array(delegate.peerState.filter { $0 != myPeerID && $1 == .connected }.keys)
        guard !remotePeers.isEmpty else { return }
        let data = try encoder.encode(message)
        let length = try data.count.pack()
        var messageData = length
        messageData.append(contentsOf: [Message.typeIdentifier])
        messageData.append(data)
        try session.send(messageData, toPeers: remotePeers, with: mode)
    }
    
    public func send(_ data: Data, typeIdentifier: UInt8 = 0, mode: MCSessionSendDataMode) throws {
        let remotePeers = Array(delegate.peerState.filter { $0 != myPeerID && $1 == .connected }.keys)
        guard !remotePeers.isEmpty else { return }
        let length = try data.count.pack()
        var messageData = length
        messageData.append(contentsOf: [typeIdentifier])
        messageData.append(data)
        try session.send(messageData, toPeers: remotePeers, with: mode)
    }
    
    func build<M: MultipeerMessagable>(_ continuation: AsyncStream<M>.Continuation) {
        continuations.append((M.self, { message in
            if let message = message as? M {
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
        print("browser lost peer \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        print("browser did not start: \(error.localizedDescription)")
    }
}

extension MultipeerManager.Delegate: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("advertiser invite from peer \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        print("advertiser did not start: \(error.localizedDescription)")
    }
}

extension MultipeerManager.Delegate: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        peerState[peerID] = state
        print("peerState didChange -> \(state.rawValue)")
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
        print("received stream named \(streamName)")
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}
}

extension Int {
    public func pack() throws -> Data {
        .init(underlying: UInt64(bitPattern: Int64(self)).bigEndian)
    }
    
    public static func unpack(data: Data) throws -> (Int, Int) {
        let bytes = MemoryLayout<UInt64>.size
        guard data.count >= bytes else { return (0, bytes) }
        let value = UInt64(bigEndian: data.interpreted())
        let number = Int(Int64(bitPattern: value))
        return (number, bytes)
    }
}

extension Data {
    init<T>(underlying value: T) {
        var target = value
        self = Swift.withUnsafeBytes(of: &target) {
            Data($0)
        }
    }
    
    func interpreted<T>(as type: T.Type = T.self) -> T {
        Data(self).withUnsafeBytes {
            $0.baseAddress!.load(as: T.self)
        }
    }
}
