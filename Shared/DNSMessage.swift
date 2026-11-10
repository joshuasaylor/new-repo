import Foundation

/// Minimal DNS wire-format helpers (RFC 1035). Only what the proxy needs:
/// reading the first question and building an NXDOMAIN reply.
enum DNSMessage {
    private static let headerLength = 12

    /// Returns the lowercased name of the first question and the byte offset
    /// where that question ends, or nil if the packet is malformed.
    static func parseQuestion(_ packet: Data) -> (name: String, end: Int)? {
        let bytes = [UInt8](packet)
        guard bytes.count > headerLength else { return nil }
        let questionCount = (Int(bytes[4]) << 8) | Int(bytes[5])
        guard questionCount >= 1 else { return nil }

        var offset = headerLength
        var labels: [String] = []
        while true {
            guard offset < bytes.count else { return nil }
            let length = Int(bytes[offset])
            if length == 0 {
                offset += 1
                break
            }
            // Compression pointers (top two bits set) are not allowed in a question.
            guard (length & 0xC0) == 0 else { return nil }
            let start = offset + 1
            let stop = start + length
            guard stop <= bytes.count else { return nil }
            guard let label = String(bytes: bytes[start..<stop], encoding: .ascii) else { return nil }
            labels.append(label.lowercased())
            offset = stop
        }

        // QTYPE and QCLASS follow the name.
        guard offset + 4 <= bytes.count else { return nil }
        return (labels.joined(separator: "."), offset + 4)
    }

    /// Builds a reply to `query` with RCODE 3 (NXDOMAIN) and the original question.
    static func nxdomainReply(to query: Data) -> Data? {
        guard let question = parseQuestion(query) else { return nil }
        var reply = [UInt8](query.prefix(question.end))
        // Byte 2: QR = 1 (response). Keep the opcode and RD bits, clear AA and TC.
        reply[2] = 0x80 | (reply[2] & 0x79)
        // Byte 3: RA = 1, RCODE = 3 (NXDOMAIN).
        reply[3] = 0x80 | 0x03
        // ANCOUNT, NSCOUNT and ARCOUNT are zero: no answers, no additional records.
        for index in 6...11 {
            reply[index] = 0
        }
        return Data(reply)
    }
}
