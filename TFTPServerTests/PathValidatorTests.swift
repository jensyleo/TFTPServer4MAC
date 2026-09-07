// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class PathValidatorTests: XCTestCase {
    func testRejectsTraversal() {
        let url = URL(fileURLWithPath: "/Users/someone/TFTP/../../etc")
        XCTAssertFalse(PathValidator.isValidRoot(url))
    }

    func testRejectsSystemPaths() {
        XCTAssertFalse(PathValidator.isValidRoot(URL(fileURLWithPath: "/System/Library")))
        XCTAssertFalse(PathValidator.isValidRoot(URL(fileURLWithPath: "/usr/libexec")))
    }

    func testAcceptsExistingUserDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
        XCTAssertTrue(PathValidator.isValidRoot(tempDir))
    }

    func testRejectsNonExistentDirectory() {
        let missing = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString)")
        XCTAssertFalse(PathValidator.isValidRoot(missing))
    }
}
