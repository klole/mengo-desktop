import XCTest
@testable import MengoDesktop

final class SidebarSectionTests: XCTestCase {

    func test_allCases_areTheFiveSectionsInOrder() {
        XCTAssertEqual(
            SidebarSection.allCases,
            [.memory, .flow, .library, .studio, .settings]
        )
    }

    func test_everyCase_hasNonEmptyPresentationStrings() {
        for section in SidebarSection.allCases {
            XCTAssertFalse(section.displayName.isEmpty, "\(section): displayName")
            XCTAssertFalse(section.systemImage.isEmpty, "\(section): systemImage")
        }
    }

    func test_noSectionCarriesAPaidBadge() {
        for section in SidebarSection.allCases {
            XCTAssertNil(section.badge, "\(section) should have no badge")
        }
    }

    func test_id_equalsRawValue() {
        for section in SidebarSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
        }
    }
}
