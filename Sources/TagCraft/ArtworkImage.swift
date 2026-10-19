import AppKit

struct ArtworkImage {
    static func prepare(_ data: Data, maxEdge: Int) throws -> Data {
        guard data.count <= 20_000_000, (data.starts(with: [255,216]) || data.starts(with: [137,80,78,71,13,10,26,10])), let bitmap = NSBitmapImageRep(data: data), let cg = bitmap.cgImage else { throw TagError(message: "Choose a valid JPEG/PNG under 20 MB.") }
        guard maxEdge > 0, max(cg.width, cg.height) > maxEdge else { return data }
        let ratio = Double(maxEdge) / Double(max(cg.width, cg.height))
        let width = max(1, Int(Double(cg.width) * ratio)), height = max(1, Int(Double(cg.height) * ratio))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw TagError(message: "Could not resize artwork.") }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(), let result = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw TagError(message: "Could not encode resized artwork.") }
        return result
    }
    static func details(_ data: Data) -> String {
        let bitmap = NSBitmapImageRep(data: data)
        let format = data.starts(with: [255,216]) ? "JPEG" : data.starts(with: [137,80,78,71]) ? "PNG" : "Image"
        return "\(bitmap?.pixelsWide ?? 0) × \(bitmap?.pixelsHigh ?? 0) px · \(format) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }
}
