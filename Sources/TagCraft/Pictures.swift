import Foundation
struct EmbeddedPicture: Identifiable {
    var id: Int
    var type: UInt8
    var mime: String
    var data: Data
    var label: String { type == 3 ? "Front cover" : type == 4 ? "Back cover" : type == 8 ? "Artist" : "Picture type \(type)" }
    static func type(_ frame: ID3.Frame) -> UInt8? {
        guard frame.id == "APIC", frame.payload.count > 4, let end = frame.payload.dropFirst().firstIndex(of: 0), end + 1 < frame.payload.count else { return nil }
        return frame.payload[end + 1]
    }
    static func read(_ parsed: ID3) -> [EmbeddedPicture] {
        parsed.frames.enumerated().compactMap { offset, frame in
            let bytes = Array(frame.payload)
            guard frame.id == "APIC", bytes.count > 4, let end = bytes[1...].firstIndex(of: 0), end + 2 < bytes.count else { return nil }
            let mime = String(bytes: bytes[1..<end], encoding: .utf8) ?? "Unknown"
            var cursor = end + 2
            if bytes[0] == 0 || bytes[0] == 3 { while cursor < bytes.count && bytes[cursor] != 0 { cursor += 1 }; cursor += 1 }
            else { while cursor + 1 < bytes.count && !(bytes[cursor] == 0 && bytes[cursor+1] == 0) { cursor += 2 }; cursor += 2 }
            guard cursor < bytes.count else { return nil }
            return .init(id: offset, type: bytes[end+1], mime: mime, data: Data(bytes[cursor...]))
        }
    }
}
