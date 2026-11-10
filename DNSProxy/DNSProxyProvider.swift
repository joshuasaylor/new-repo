import Foundation
import Network
import NetworkExtension

/// System-wide DNS filter. Queries for blocked domains get an NXDOMAIN reply.
/// All other UDP DNS queries are forwarded unchanged to an upstream resolver.
/// Nothing is logged or stored.
final class DNSProxyProvider: NEDNSProxyProvider {
    private let blocklist = DNSBlocklist()
    private let upstreamHost = NWEndpoint.Host("1.1.1.1")
    private let upstreamPort = NWEndpoint.Port(rawValue: 53)!

    override func startProxy(options: [String: Any]?, completionHandler: @escaping (Error?) -> Void) {
        blocklist.reload()
        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // TCP DNS and any other flow is left alone and goes direct.
        guard let udpFlow = flow as? NEAppProxyUDPFlow else { return false }
        blocklist.reloadIfStale()
        udpFlow.open(withLocalEndpoint: nil) { [weak self] error in
            guard error == nil, let self else {
                udpFlow.closeReadWithError(error)
                udpFlow.closeWriteWithError(error)
                return
            }
            self.readLoop(udpFlow)
        }
        return true
    }

    private func readLoop(_ flow: NEAppProxyUDPFlow) {
        flow.readDatagrams { [weak self] datagrams, endpoints, error in
            guard let self, error == nil, let datagrams, let endpoints else {
                flow.closeReadWithError(error)
                return
            }
            for (query, endpoint) in zip(datagrams, endpoints) {
                self.handle(query: query, sentTo: endpoint, on: flow)
            }
            self.readLoop(flow)
        }
    }

    private func handle(query: Data, sentTo endpoint: NWEndpoint, on flow: NEAppProxyUDPFlow) {
        guard let question = DNSMessage.parseQuestion(query) else { return }

        if blocklist.blocks(question.name) {
            if let reply = DNSMessage.nxdomainReply(to: query) {
                flow.writeDatagrams([reply], sentBy: [endpoint]) { _ in }
            }
            return
        }

        forward(query) { reply in
            guard let reply else { return }
            flow.writeDatagrams([reply], sentBy: [endpoint]) { _ in }
        }
    }

    /// Sends one query to the upstream resolver and returns the first reply, or nil on failure.
    private func forward(_ query: Data, completion: @escaping (Data?) -> Void) {
        let connection = NWConnection(host: upstreamHost, port: upstreamPort, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: query, completion: .contentProcessed { _ in
                    connection.receiveMessage { data, _, _, _ in
                        completion(data)
                        connection.cancel()
                    }
                })
            case .failed, .cancelled:
                completion(nil)
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        // Give up on a silent upstream so connections do not pile up.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }
}

/// Thread-safe copy of the blocked-domain set, refreshed from the App Group.
final class DNSBlocklist {
    private let lock = NSLock()
    private var domains = Set<String>()
    private var loadedAt = Date.distantPast
    private let refreshInterval: TimeInterval = 60

    func reload() {
        let loaded = BlocklistStore.loadDomains()
        lock.lock()
        domains = loaded
        loadedAt = Date()
        lock.unlock()
    }

    func reloadIfStale() {
        lock.lock()
        let stale = Date().timeIntervalSince(loadedAt) > refreshInterval
        lock.unlock()
        if stale { reload() }
    }

    func blocks(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return BlocklistStore.isBlocked(name, in: domains)
    }
}
