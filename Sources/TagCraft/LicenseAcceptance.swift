import Foundation

enum LicenseAcceptance {
    static func isAcknowledged(defaults: UserDefaults, release: String) -> Bool {
        defaults.string(forKey: "acknowledgedUsageNoticeVersion") == LicenseTerms.version &&
        defaults.string(forKey: "acknowledgedUsageNoticeSupplementVersion") == LicenseTerms.supplementVersion &&
        defaults.string(forKey: "acknowledgedUsageNoticeHash") == LicenseTerms.documentHash &&
        defaults.string(forKey: "acknowledgedUsageNoticeAppRelease") == release &&
        defaults.object(forKey: "usageNoticeAcknowledgedAt") is Date
    }
    // Call only from the explicit Continue action; reading/quitting must not write records.
    static func acknowledge(defaults: UserDefaults, release: String, at date: Date = Date()) {
        defaults.set(LicenseTerms.version, forKey: "acknowledgedUsageNoticeVersion")
        defaults.set(LicenseTerms.supplementVersion, forKey: "acknowledgedUsageNoticeSupplementVersion")
        defaults.set(LicenseTerms.documentHash, forKey: "acknowledgedUsageNoticeHash")
        defaults.set(release, forKey: "acknowledgedUsageNoticeAppRelease")
        defaults.set(date, forKey: "usageNoticeAcknowledgedAt")
    }
}
