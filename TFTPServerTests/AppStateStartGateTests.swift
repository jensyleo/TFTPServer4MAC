// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

/// El usuario pidió (2026-09-08) que el servidor no pueda arrancar mientras
/// haya un problema de permisos sin resolver — en vez de dejar que
/// `NativeTFTPService.start()` lo intente y falle más adelante de forma
/// menos clara.
@MainActor
final class AppStateStartGateTests: XCTestCase {
    func testStartRefusesWhenWorkingPathPermissionsAreBroken() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateStartGateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tempDir.path)

        let appState = AppState()
        appState.configuration.rootDirectory = tempDir

        await appState.start()

        XCTAssertEqual(appState.lastError, .permissionsMustBeFixedFirst)
        XCTAssertNotEqual(appState.serverStatus, .running)
    }
}
