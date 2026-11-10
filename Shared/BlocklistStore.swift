import Foundation

/// The App Group shared by the app and both extensions.
enum AppGroup {
    /// Must match the App Group in every target's entitlements.
    static let identifier = "group.com.yourcompany.adblock"

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.temporaryDirectory
    }
}

/// Stores the blocked-domain list and the compiled Safari rules in the App Group.
enum BlocklistStore {
    static let domainsFileName = "blocked-domains.txt"
    static let safariRulesFileName = "safari-rules.json"

    /// Upper bound on the number of domains kept (keeps memory and rule counts sane).
    static let maxDomains = 200_000

    /// Default community hosts list. Check its license before shipping.
    static let defaultListURL = URL(string: "https://adaway.org/hosts.txt")!

    /// Used until the first list update. Small, well-known ad and tracker domains.
    static let seedDomains: [String] = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "adservice.google.com", "googletagservices.com", "2mdn.net",
        "advertising.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net",
        "taboola.com", "outbrain.com", "scorecardresearch.com", "amazon-adsystem.com",
        "moatads.com", "pubmatic.com", "rubiconproject.com", "openx.net",
        "smartadserver.com", "casalemedia.com", "media.net", "zedo.com",
        "popads.net", "propellerads.com", "adform.net", "serving-sys.com",
        "quantserve.com", "ads.yahoo.com", "ads.twitter.com", "ads-api.twitter.com",
        "app-measurement.com", "branch.io", "adjust.com", "appsflyer.com",
        "unityads.unity3d.com", "applovin.com", "ironsrc.com", "vungle.com",
        "startapp.com", "mopub.com", "inmobi.com", "chartboost.com",
    ]

    static var domainsURL: URL {
        AppGroup.containerURL.appendingPathComponent(domainsFileName)
    }

    static var safariRulesURL: URL {
        AppGroup.containerURL.appendingPathComponent(safariRulesFileName)
    }

    static func loadDomains() -> Set<String> {
        guard let text = try? String(contentsOf: domainsURL, encoding: .utf8) else {
            return Set(seedDomains)
        }
        let parsed = parse(hostsText: text)
        return parsed.isEmpty ? Set(seedDomains) : parsed
    }

    /// Writes the domain list and regenerates the Safari rules file.
    static func save(domains: Set<String>) throws {
        let sorted = domains.sorted()
        try sorted.joined(separator: "\n").write(to: domainsURL, atomically: true, encoding: .utf8)
        let rules = try ContentRuleCompiler.json(for: sorted)
        try rules.write(to: safariRulesURL, options: .atomic)
    }

    /// Accepts both hosts-file lines ("0.0.0.0 example.com") and plain domain lines.
    static func parse(hostsText: String) -> Set<String> {
        var result = Set<String>()
        for rawLine in hostsText.split(whereSeparator: { $0.isNewline }) {
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard !fields.isEmpty else { continue }
            let candidate = fields.count >= 2 ? fields[1] : fields[0]
            let host = candidate.lowercased()
            if isValidDomain(host) {
                result.insert(host)
            }
            if result.count >= maxDomains { break }
        }
        return result
    }

    static func isValidDomain(_ host: String) -> Bool {
        guard host.count <= 253,
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("..") else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.allSatisfy({ allowed.contains($0) }) else { return false }
        // The top-level label must contain a letter, which rejects bare IP addresses.
        guard let tld = host.split(separator: ".").last, tld.contains(where: { $0.isLetter }) else {
            return false
        }
        return true
    }

    /// True if `name` or any parent domain of it is in `domains`.
    /// For example "securepubads.g.doubleclick.net" matches "doubleclick.net".
    static func isBlocked(_ name: String, in domains: Set<String>) -> Bool {
        var candidate = Substring(name)
        while !candidate.isEmpty {
            if domains.contains(String(candidate)) { return true }
            guard let dot = candidate.firstIndex(of: ".") else { break }
            candidate = candidate[candidate.index(after: dot)...]
        }
        return false
    }
}
