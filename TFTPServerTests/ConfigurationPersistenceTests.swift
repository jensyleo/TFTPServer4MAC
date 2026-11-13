// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

@MainActor
final class ConfigurationPersistenceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ConfigurationPersistenceTests-\(UUID().uuidString)")!
    }

    func testSavedFolderAndCaptureToggleSurviveRelaunch() throws {
        let defaults = makeDefaults()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigPersist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = AppState(defaults: defaults)
        first.configuration.rootDirectory = dir
        first.configuration.isClientIPCaptureEnabled = false

        let second = AppState(defaults: defaults)
        XCTAssertEqual(second.configuration.rootDirectory.path, dir.path)
        XCTAssertFalse(second.configuration.isClientIPCaptureEnabled)
    }

    func testDeletedSavedFolderFallsBackToDefault() throws {
        let defaults = makeDefaults()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConfigPersist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let first = AppState(defaults: defaults)
        first.configuration.rootDirectory = dir
        try FileManager.default.removeItem(at: dir)

        let second = AppState(defaults: defaults)
        XCTAssertEqual(second.configuration.rootDirectory, TFTPConfiguration.conservativeDefault.rootDirectory)
    }

    func testFreshInstallUsesDefaults() {
        let state = AppState(defaults: makeDefaults())
        XCTAssertEqual(state.configuration, TFTPConfiguration.conservativeDefault)
    }
}
