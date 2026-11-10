import XCTest

final class DNSTests: XCTestCase {
    /// Builds a minimal A/IN query for `name`.
    private func query(for name: String, id: [UInt8] = [0x12, 0x34]) -> Data {
        var bytes: [UInt8] = id + [0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: Array(label.utf8))
        }
        bytes += [0x00, 0x00, 0x01, 0x00, 0x01]
        return Data(bytes)
    }

    func testParsesAndLowercasesQuestionName() {
        let parsed = DNSMessage.parseQuestion(query(for: "Ads.Example.com"))
        XCTAssertEqual(parsed?.name, "ads.example.com")
    }

    func testRejectsTruncatedPacket() {
        let full = query(for: "ads.example.com")
        XCTAssertNil(DNSMessage.parseQuestion(full.prefix(15)))
    }

    func testNXDOMAINReplyKeepsIDAndSetsRcode() throws {
        let reply = try XCTUnwrap(DNSMessage.nxdomainReply(to: query(for: "ads.example.com")))
        let bytes = [UInt8](reply)
        XCTAssertEqual(Array(bytes[0..<2]), [0x12, 0x34])
        XCTAssertEqual(bytes[2] & 0x80, 0x80, "QR bit should be set")
        XCTAssertEqual(bytes[3] & 0x0F, 3, "RCODE should be NXDOMAIN")
        XCTAssertEqual(Array(bytes[6..<12]), [0, 0, 0, 0, 0, 0])
    }

    func testBlocksDomainAndSubdomains() {
        let blocked: Set<String> = ["doubleclick.net"]
        XCTAssertTrue(BlocklistStore.isBlocked("doubleclick.net", in: blocked))
        XCTAssertTrue(BlocklistStore.isBlocked("securepubads.g.doubleclick.net", in: blocked))
        XCTAssertFalse(BlocklistStore.isBlocked("notdoubleclick.net", in: blocked))
        XCTAssertFalse(BlocklistStore.isBlocked("example.com", in: blocked))
    }

    func testParsesHostsAndPlainFormats() {
        let text = """
        # comment line
        0.0.0.0 ads.example.com # inline comment
        plain.example.org
        127.0.0.1 localhost
        0.0.0.0
        bad..name.com
        """
        XCTAssertEqual(BlocklistStore.parse(hostsText: text), ["ads.example.com", "plain.example.org"])
    }

    func testSafariURLFilterEscapesDots() {
        XCTAssertEqual(
            ContentRuleCompiler.urlFilter(for: "ads.example.com"),
            "^[a-z]+://([^/]+\\.)?ads\\.example\\.com(/|:|\\?|$)"
        )
    }
}
