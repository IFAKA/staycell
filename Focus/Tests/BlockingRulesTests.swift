import Testing
@testable import Focus

@Suite("Blocking Rules")
struct BlockingRulesTests {
    @Test("Deep work blocks all categories except break-only")
    func deepWorkBlocking() {
        let mode = FocusMode.deepWork
        #expect(mode.blockedCategories.contains(.social))
        #expect(mode.blockedCategories.contains(.video))
        #expect(mode.blockedCategories.contains(.porn))
        #expect(mode.blockedCategories.contains(.gore))
        #expect(mode.blockedCategories.contains(.news))
    }

    @Test("Personal time only blocks porn and gore")
    func personalTimeBlocking() {
        let mode = FocusMode.personalTime
        #expect(!mode.blockedCategories.contains(.social))
        #expect(!mode.blockedCategories.contains(.video))
        #expect(mode.blockedCategories.contains(.porn))
        #expect(mode.blockedCategories.contains(.gore))
        #expect(!mode.blockedCategories.contains(.news))
    }

    @Test("Offline blocks everything")
    func offlineBlocking() {
        let mode = FocusMode.offline
        #expect(mode.blockedCategories.contains(.social))
        #expect(mode.blockedCategories.contains(.video))
        #expect(mode.blockedCategories.contains(.porn))
        #expect(mode.blockedCategories.contains(.gore))
        #expect(mode.blockedCategories.contains(.news))
    }

    @Test("Blocked domains list is non-empty for all blocking modes")
    func blockedDomainsNonEmpty() {
        for mode in FocusMode.allCases {
            if !mode.blockedCategories.isEmpty {
                #expect(!mode.blockedDomains.isEmpty, "Mode \(mode.rawValue) should have blocked domains")
            }
        }
    }

    @Test("All domains are valid hostnames")
    func domainsAreValidHostnames() {
        for category in BlockCategory.allCases {
            for domain in category.domains {
                #expect(!domain.contains(" "), "Domain '\(domain)' contains spaces")
                #expect(!domain.hasPrefix("http"), "Domain '\(domain)' should not include protocol")
                #expect(domain.contains("."), "Domain '\(domain)' should contain a dot")
            }
        }
    }
}
