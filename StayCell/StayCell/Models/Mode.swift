import Foundation

/// The five operating modes of the StayCell app.
/// Each mode defines which categories of websites are blocked.
enum Mode: String, Codable, CaseIterable, Sendable {
    case deepWork
    case shallowWork
    case personalTime
    case offline

    var displayName: String {
        switch self {
        case .deepWork: "Deep Work"
        case .shallowWork: "Shallow Work"
        case .personalTime: "Personal"
        case .offline: "Offline"
        }
    }

    var shortName: String {
        switch self {
        case .deepWork: "DW"
        case .shallowWork: "SW"
        case .personalTime: "P"
        case .offline: "OFF"
        }
    }

    /// Color name for the menubar dot (SF Symbol color)
    var dotColorName: String {
        switch self {
        case .deepWork: "systemRed"
        case .shallowWork: "systemOrange"
        case .personalTime: "systemGreen"
        case .offline: "systemPurple"
        }
    }

    /// Categories blocked in this mode
    var blockedCategories: Set<BlockCategory> {
        switch self {
        case .deepWork:
            [.social, .video, .porn, .gore, .news, .imageboard]
        case .shallowWork:
            [.social, .video, .porn, .gore, .news, .imageboard]
        case .personalTime:
            [.porn, .gore]
        case .offline:
            [.social, .video, .porn, .gore, .news, .imageboard]
        }
    }

    /// All domains that should be blocked in this mode
    var blockedDomains: [String] {
        blockedCategories.flatMap(\.domains).sorted()
    }
}

/// Categories of websites that can be blocked
enum BlockCategory: String, Codable, CaseIterable, Sendable {
    case social
    case video
    case porn
    case gore
    case news
    case imageboard

    var domains: [String] {
        switch self {
        case .social:
            BlockedDomains.social
        case .video:
            BlockedDomains.video
        case .porn:
            BlockedDomains.porn
        case .gore:
            BlockedDomains.gore
        case .news:
            BlockedDomains.news
        case .imageboard:
            BlockedDomains.imageboard
        }
    }
}
