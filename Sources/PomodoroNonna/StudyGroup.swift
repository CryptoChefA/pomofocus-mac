import Foundation
@preconcurrency import MultipeerConnectivity

/// Studying together with friends in the same room. One Mac hosts a group; friends nearby
/// join it, and their timers follow the host's: the same block, breaks at the same moment.
///
/// It uses Apple's Multipeer Connectivity, which finds Macs nearby over Bluetooth and
/// peer-to-peer Wi-Fi, the way AirDrop does, so it needs no internet, account or server and
/// works on library Wi-Fi that keeps devices apart. The connection is encrypted. Only the
/// timer is shared (see `GroupTimer`), with a first name if you give one; tasks, notes and
/// history never leave this Mac.
@MainActor
@Observable
final class StudyGroup: NSObject {
    static let shared = StudyGroup()

    enum Role: Equatable {
        case none
        case hosting
        case joining(String)
        case following(host: String)
    }

    struct NearbyGroup: Identifiable, Equatable {
        let peer: MCPeerID
        let hostName: String
        var id: MCPeerID { peer }
    }

    private(set) var role: Role = .none
    /// Groups found nearby while looking.
    private(set) var nearby: [NearbyGroup] = []
    /// First names of everyone in the group, host first.
    private(set) var members: [String] = []
    private(set) var lastProblem: String?

    var isInGroup: Bool { role != .none }
    var isFollowing: Bool { if case .following = role { return true } else { return false } }

    /// Up to eight Macs can share a session; Multipeer Connectivity's own limit.
    static let maximumMembers = 8
    private static let serviceType = "pomofocus-grp"

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var me: MCPeerID?
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var heartbeat: Timer?
    @ObservationIgnored private var hostPeer: MCPeerID?
    /// The host block this Mac is following.
    @ObservationIgnored private var followingBlock: String?
    @ObservationIgnored private var names: [MCPeerID: String] = [:]
    @ObservationIgnored private var lastSent: GroupTimer?

    /// The name shown to others: your first name from Settings, or "A friend".
    private var myName: String {
        let name = (UserDefaults.standard.string(forKey: "displayName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "A friend" : String(name.prefix(30))
    }

    private func makeSession() -> MCSession {
        let peer = MCPeerID(displayName: myName)
        me = peer
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        return session
    }

    // MARK: Hosting

    func startHosting() {
        leave()
        let session = makeSession()
        let advertiser = MCNearbyServiceAdvertiser(peer: session.myPeerID, discoveryInfo: ["host": myName],
                                                   serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        role = .hosting
        members = [myName]
        lastProblem = nil
        // A heartbeat keeps everyone in step even if a message goes missing.
        let beat = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.broadcast(force: true) }
        }
        RunLoop.main.add(beat, forMode: .common)
        heartbeat = beat
    }

    /// Tells the group straight away when the host's timer changes, rather than at the next beat.
    func hostTimerChanged() {
        guard role == .hosting else { return }
        broadcast(force: false)
    }

    private func broadcast(force: Bool) {
        guard role == .hosting, let session, let model, !session.connectedPeers.isEmpty else { return }
        let timer = model.groupTimer(hostName: myName, members: members)
        if !force, let lastSent, lastSent.blockID == timer.blockID, lastSent.state == timer.state,
           lastSent.phase == timer.phase, lastSent.planned == timer.planned { return }
        lastSent = timer
        send(GroupMessage(kind: .timer, timer: timer), to: session.connectedPeers, reliable: true)
    }

    // MARK: Joining

    /// Looks for groups nearby, for the Study together sheet.
    func startLooking() {
        guard role == .none, browser == nil else { return }
        let peer = me ?? MCPeerID(displayName: myName)
        me = peer
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stopLooking() {
        browser?.stopBrowsingForPeers()
        browser = nil
        nearby = []
    }

    func join(_ group: NearbyGroup) {
        guard let browser else { return }
        let session = makeSession()
        hostPeer = group.peer
        role = .joining(group.hostName)
        lastProblem = nil
        browser.invitePeer(group.peer, to: session, withContext: nil, timeout: 15)
    }

    // MARK: Leaving

    /// Leaves the group, or ends it for everyone when hosting. Your own timer carries on.
    func leave() {
        heartbeat?.invalidate()
        heartbeat = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        stopLooking()
        hostPeer = nil
        followingBlock = nil
        lastSent = nil
        names = [:]
        members = []
        role = .none
    }

    // MARK: Messages

    private func send(_ message: GroupMessage, to peers: [MCPeerID], reliable: Bool) {
        guard let session, !peers.isEmpty, let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: peers, with: reliable ? .reliable : .unreliable)
    }

    fileprivate func received(_ data: Data, from peer: MCPeerID) {
        guard let message = try? JSONDecoder().decode(GroupMessage.self, from: data) else { return }
        switch message.kind {
        case .hello:
            guard role == .hosting else { return }
            names[peer] = message.name.map { String($0.prefix(30)) } ?? peer.displayName
            refreshMembers()
            broadcast(force: true)
        case .timer:
            guard let timer = message.timer, peer == hostPeer, let model else { return }
            if case .joining = role { role = .following(host: timer.hostName) }
            members = timer.members
            let action = GroupSync.action(local: model.groupLocal(following: followingBlock), host: timer, now: Date())
            if case let .start(blockID, _, _, _, _) = action { followingBlock = blockID }
            if case .stop = action { followingBlock = nil }
            model.applyGroup(action)
        }
    }

    fileprivate func peer(_ peer: MCPeerID, changed state: MCSessionState) {
        switch role {
        case .hosting:
            if state == .notConnected { names[peer] = nil }
            if state == .connected, names[peer] == nil { names[peer] = peer.displayName }
            refreshMembers()
            if state == .connected { broadcast(force: true) }
        case .joining, .following:
            guard peer == hostPeer else { return }
            if state == .connected {
                stopLooking()
                send(GroupMessage(kind: .hello, name: myName), to: [peer], reliable: true)
            } else if state == .notConnected {
                // Out of range or the host ended it: keep the timer going on its own.
                lastProblem = isFollowing ? "Lost touch with the group. Your timer carries on." : "Couldn't join that group."
                let problem = lastProblem
                leave()
                lastProblem = problem
            }
        case .none:
            break
        }
    }

    private func refreshMembers() {
        guard let session else { return }
        let others = session.connectedPeers.map { names[$0] ?? $0.displayName }.sorted()
        members = [myName] + others
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard !nearby.contains(where: { $0.peer == peer }) else { return }
        nearby.append(NearbyGroup(peer: peer, hostName: info?["host"] ?? peer.displayName))
    }

    fileprivate func lost(_ peer: MCPeerID) {
        nearby.removeAll { $0.peer == peer }
    }

    fileprivate func invited(by peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        guard role == .hosting, let session, session.connectedPeers.count < Self.maximumMembers - 1 else {
            handler(false, nil)
            return
        }
        handler(true, session)
    }
}

// Multipeer Connectivity calls these on its own queues; each hops to the main actor.

extension StudyGroup: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in self.peer(peerID, changed: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.received(data, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension StudyGroup: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Called once, on the main actor, to answer this one invitation.
        nonisolated(unsafe) let handler = invitationHandler
        Task { @MainActor in self.invited(by: peerID, handler: handler) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.lastProblem = "Couldn't start the group. Check that Pomofocus may find devices on your network in System Settings → Privacy & Security → Local Network."
            self.leave()
        }
    }
}

extension StudyGroup: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in self.found(peerID, info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.lost(peerID) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.lastProblem = "Couldn't look for groups. Check that Pomofocus may find devices on your network in System Settings → Privacy & Security → Local Network."
        }
    }
}
