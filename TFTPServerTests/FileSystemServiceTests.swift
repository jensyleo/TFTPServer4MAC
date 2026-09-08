// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class FileSystemServiceTests: XCTestCase {
    private var tempDir: URL!
    private let service = FileSystemService()

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSystemServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRepairPermissionsFixesUnreadableDirectory() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tempDir.path)
        XCTAssertFalse(service.hasAppropriatePermissions(tempDir))

        XCTAssertTrue(service.repairPermissions(tempDir))
        XCTAssertTrue(service.hasAppropriatePermissions(tempDir))
    }

    func testRepairPermissionsOnAlreadyReadableDirectoryIsANoOpSuccess() {
        XCTAssertTrue(service.hasAppropriatePermissions(tempDir))
        XCTAssertTrue(service.repairPermissions(tempDir))
        XCTAssertTrue(service.hasAppropriatePermissions(tempDir))
    }

    func testRepairPermissionsFailsForNonExistentDirectory() {
        let missing = tempDir.appendingPathComponent("does-not-exist")
        XCTAssertFalse(service.repairPermissions(missing))
    }
}
