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
            XCTAssertFalse(section.comingSoonBlurb.isEmpty, "\(section): comingSoonBlurb")
        }
    }

    func test_everyCase_targetsAPhaseBetween2And5() {
        for section in SidebarSection.allCases {
            XCTAssertTrue((2...5).contains(section.phase),
                          "\(section): phase \(section.phase) out of range")
        }
    }

    func test_onlyStudioCarriesAProBadge() {
        for section in SidebarSection.allCases {
            if section == .studio {
                XCTAssertEqual(section.badge, "Pro")
            } else {
                XCTAssertNil(section.badge, "\(section) should have no badge")
            }
        }
    }

    func test_id_equalsRawValue() {
        for section in SidebarSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
        }
    }
}
