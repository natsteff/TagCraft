import Foundation

struct UpdateVersion: Comparable, Equatable {
    let parts: [Int]
    let stage: Int // alpha < beta < release candidate < stable
    let build: Int
    init?(_ tag: String, build: Int = 0, prerelease: Bool = false) {
        let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let components = value.split(separator: "-", maxSplits: 1)
        guard let core = components.first else { return nil }
        let digits = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard digits.count == 3, digits.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = digits.map { $0! }; self.build = build
        let suffix = components.count > 1 ? components[1].lowercased() : ""
        if suffix.hasPrefix("alpha") { stage = 0 }
        else if suffix.hasPrefix("beta") { stage = 1 }
        else if suffix.hasPrefix("rc") { stage = 2 }
        else if suffix.isEmpty { stage = prerelease ? 0 : 3 }
        else { return nil }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.parts != rhs.parts { return lhs.parts.lexicographicallyPrecedes(rhs.parts) }
        if lhs.stage != rhs.stage { return lhs.stage < rhs.stage }
        return lhs.build < rhs.build
    }
}
struct GitHubUpdateRelease: Decodable {
    struct Asset: Decodable {
        var name: String
        var browser_download_url: URL
        var state: String
    }
    var tag_name: String
    var name: String?
    var body: String?
    var html_url: URL
    var draft: Bool
    var prerelease: Bool
    var assets: [Asset]
    var build: Int {
        let text = (name ?? "") + "\n" + (body ?? "")
        guard let range = text.range(of: #"\bBuild\s+([0-9]+)\b"#, options: [.regularExpression, .caseInsensitive]) else { return 0 }
        return Int(text[range].split(whereSeparator: { !$0.isNumber }).last ?? "") ?? 0
    }
    var version: UpdateVersion? { UpdateVersion(tag_name, build: build, prerelease: prerelease) }
    var isProjectRelease: Bool {
        html_url.scheme == "https" && html_url.host == "github.com" && html_url.path.hasPrefix("/natsteff/TagCraft/releases/tag/")
    }
    func download(architecture: String) -> URL? {
        let matches = assets.filter {
            let name = $0.name.lowercased()
            return $0.state == "uploaded" && name.hasSuffix(".dmg") && name.contains("macos")
                && (name.contains("-" + architecture + ".") || name.contains("-universal."))
                && $0.browser_download_url.scheme == "https" && $0.browser_download_url.host == "github.com"
                && $0.browser_download_url.path.hasPrefix("/natsteff/TagCraft/releases/download/")
        }
        return matches.sorted { $0.name < $1.name }.first?.browser_download_url
    }
}
enum UpdateCheckError: LocalizedError {
    case http(Int), invalidResponse, noReleases
    var errorDescription: String? {
        switch self {
        case .http(403), .http(429): return "GitHub temporarily limited update checks. Try again later or open Releases."
        case .http(let code): return "GitHub could not provide release information (HTTP \(code)). Try again later."
        case .invalidResponse: return "The release information could not be understood. Open Releases to check manually."
        case .noReleases: return "No recognized public releases were found. Open Releases to check manually."
        }
    }
}
enum UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/natsteff/TagCraft/releases")!
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    static func newest(_ releases: [GitHubUpdateRelease], includePrereleases: Bool) -> GitHubUpdateRelease? {
        releases.filter { !$0.draft && $0.isProjectRelease && $0.version != nil && (includePrereleases || !$0.prerelease) }
            .max { $0.version! < $1.version! }
    }
    static func check(includePrereleases: Bool, session: URLSession = .shared) async throws -> GitHubUpdateRelease {
        // Public request only: no credentials, library paths, filenames or tags are sent.
        // Follow pages to avoid mistaking the first page for the complete release list.
        var releases: [GitHubUpdateRelease] = []
        for page in 1...10 {
            try Task.checkCancellation()
            let url = URL(string: "https://api.github.com/repos/natsteff/TagCraft/releases?per_page=100&page=\(page)")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("TagCraft-Update-Check", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
            guard response.statusCode == 200 else { throw UpdateCheckError.http(response.statusCode) }
            guard data.count <= 10_000_000, let pageReleases = try? JSONDecoder().decode([GitHubUpdateRelease].self, from: data) else { throw UpdateCheckError.invalidResponse }
            releases += pageReleases
            if pageReleases.count < 100 {
                guard let release = newest(releases, includePrereleases: includePrereleases) else { throw UpdateCheckError.noReleases }
                return release
            }
        }
        throw UpdateCheckError.invalidResponse // Never claim up-to-date after a truncated result.
    }
}
