import Foundation
import NetworkExtension
import SafariServices

@MainActor
final class AppModel: ObservableObject {
    /// Must match the bundle identifiers set in project.yml.
    static let safariExtensionID = "com.yourcompany.adblock.SafariContentBlocker"
    static let dnsExtensionID = "com.yourcompany.adblock.DNSProxy"

    @Published private(set) var domainCount = 0
    @Published private(set) var dnsEnabled = false
    @Published private(set) var isBusy = false
    @Published var statusMessage = ""
    @Published var listURLText = BlocklistStore.defaultListURL.absoluteString

    func onAppear() async {
        ensureSafariRulesExist()
        domainCount = BlocklistStore.loadDomains().count
        do {
            dnsEnabled = try await loadDNSManager().isEnabled
        } catch {
            statusMessage = "Could not read DNS filter state: \(error.localizedDescription)"
        }
    }

    /// Downloads a hosts-format list, saves it, and reloads Safari's rules.
    func updateLists() async {
        let trimmed = listURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" else {
            statusMessage = "Enter an https:// list URL."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let domains = BlocklistStore.parse(hostsText: String(decoding: data, as: UTF8.self))
            guard !domains.isEmpty else {
                statusMessage = "No domains found in that list."
                return
            }
            try BlocklistStore.save(domains: domains)
            domainCount = domains.count
            if let error = await reloadSafari() {
                statusMessage = "Saved \(domains.count) domains, but Safari reload failed: \(error.localizedDescription)"
            } else {
                statusMessage = "Updated to \(domains.count) domains."
            }
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    /// Turns the system-wide DNS filter on or off. iOS asks the user to approve the first time.
    func setDNSFilter(_ enabled: Bool) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let manager = try await loadDNSManager()
            let proto = NEDNSProxyProviderProtocol()
            proto.providerBundleIdentifier = Self.dnsExtensionID
            manager.providerProtocol = proto
            manager.localizedDescription = "AdBlock"
            manager.isEnabled = enabled
            try await saveDNSManager(manager)
            dnsEnabled = manager.isEnabled
            statusMessage = enabled ? "DNS filter on for all apps." : "DNS filter off."
        } catch {
            statusMessage = "Could not change DNS filter: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func ensureSafariRulesExist() {
        guard !FileManager.default.fileExists(atPath: BlocklistStore.safariRulesURL.path) else { return }
        do {
            try BlocklistStore.save(domains: BlocklistStore.loadDomains())
        } catch {
            statusMessage = "Could not write Safari rules: \(error.localizedDescription)"
        }
    }

    /// Asks Safari to reload the content blocker. Returns an error, or nil on success.
    private func reloadSafari() async -> Error? {
        await withCheckedContinuation { continuation in
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: Self.safariExtensionID) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func loadDNSManager() async throws -> NEDNSProxyManager {
        let manager = NEDNSProxyManager.shared()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        return manager
    }

    private func saveDNSManager(_ manager: NEDNSProxyManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
