import Foundation

/// ID3v2.3/v2.4 USLT: encoding, language, terminated descriptor, lyrics.
struct LyricsFrame {
    var language: String
    var descriptor: String
    var text: String
    static func decode(_ payload: Data) throws -> LyricsFrame {
        let bytes = [UInt8](payload)
        guard bytes.count >= 5, bytes[0] <= 3,
              let language = String(bytes: bytes[1..<4], encoding: .ascii) else {
            throw TagError(message: "Malformed or unsupported lyrics frame; file left unchanged.")
        }
        let encoding = bytes[0], unit = (encoding == 1 || encoding == 2) ? 2 : 1
        var end = 4
        while end + unit <= bytes.count {
            if bytes[end..<end+unit].allSatisfy({ $0 == 0 }) { break }
            end += unit
        }
        guard end + unit <= bytes.count else { throw TagError(message: "Lyrics descriptor is not terminated; file left unchanged.") }
        let descriptorBytes = Data(bytes[4..<end])
        func string(_ data: Data) -> String? {
            if data.isEmpty { return "" }
            switch encoding {
            case 0: return String(data: data, encoding: .isoLatin1)
            case 1:
                if data.starts(with: [0xff,0xfe]) || data.starts(with: [0xfe,0xff]) { return String(data: data, encoding: .utf16) }
                if descriptorBytes.starts(with: [0xff,0xfe]) { return String(data: data, encoding: .utf16LittleEndian) }
                if descriptorBytes.starts(with: [0xfe,0xff]) { return String(data: data, encoding: .utf16BigEndian) }
                return nil
            case 2: return String(data: data, encoding: .utf16BigEndian)
            case 3: return String(data: data, encoding: .utf8)
            default: return nil
            }
        }
        guard let descriptor = string(descriptorBytes), var text = string(Data(bytes[(end+unit)...])) else {
            throw TagError(message: "Lyrics text cannot be decoded safely; file left unchanged.")
        }
        while text.last == "\0" { text.removeLast() }
        return LyricsFrame(language: language, descriptor: descriptor, text: text)
    }
    func payload(version: Int) -> Data {
        let encoding: UInt8 = version == 4 ? 3 : 1
        let codec: String.Encoding = version == 4 ? .utf8 : .utf16
        var result = Data([encoding]); result.append(Data(language.utf8))
        result.append(descriptor.data(using: codec)!)
        result.append(Data(repeating: 0, count: version == 4 ? 1 : 2))
        result.append(text.data(using: codec)!)
        return result
    }
}
