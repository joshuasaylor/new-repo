import Foundation

/// Converts a domain list into WKContentRuleList JSON for Safari content blockers.
enum ContentRuleCompiler {
    /// Safari refuses content rule lists larger than this.
    static let maxRules = 50_000

    static func json(for domains: [String]) throws -> Data {
        let rules: [[String: Any]] = domains.prefix(maxRules).map { domain in
            [
                "trigger": [
                    "url-filter": urlFilter(for: domain),
                    "url-filter-is-case-sensitive": false,
                ],
                "action": ["type": "block"],
            ]
        }
        return try JSONSerialization.data(withJSONObject: rules)
    }

    /// Matches the domain itself and any subdomain, over http or https.
    static func urlFilter(for domain: String) -> String {
        "^[a-z]+://([^/]+\\.)?" + escape(domain) + "(/|:|\\?|$)"
    }

    private static func escape(_ domain: String) -> String {
        domain.replacingOccurrences(of: ".", with: "\\.")
    }
}
