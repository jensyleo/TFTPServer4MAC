// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

private struct FakePrivilegedShellRunner: PrivilegedShellRunning {
    var shouldThrow: PrivilegedShellError?
    func runElevated(_ shellCommand: String) throws {
        if let shouldThrow { throw shouldThrow }
    }
}

final class TFTPServiceManagerTests: XCTestCase {
    func testStartRejectsInvalidRootBeforeElevating() async {
        // No debe pedir privilegios si el root ya es inválido: falla rápido y
        // sin molestar al usuario con un diálogo de autorización inútil.
        var config = TFTPConfiguration.conservativeDefault
        config.rootDirectory = URL(fileURLWithPath: "/System/Library")
        let service = NativeTFTPService(
            privilegedShellRunner: FakePrivilegedShellRunner(),
            configuration: config
        )

        do {
            try await service.start()
            XCTFail("Expected rootDirectoryInvalid")
        } catch TFTPServiceError.rootDirectoryInvalid {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartMapsUserCancelledToPermissionDenied() async {
        let service = NativeTFTPService(
            privilegedShellRunner: FakePrivilegedShellRunner(shouldThrow: .userCancelled)
        )

        do {
            try await service.start()
            XCTFail("Expected permissionDenied")
        } catch TFTPServiceError.permissionDenied {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdateConfigurationRejectsInvalidRoot() async {
        let service = NativeTFTPService(privilegedShellRunner: FakePrivilegedShellRunner())
        var config = TFTPConfiguration.conservativeDefault
        config.rootDirectory = URL(fileURLWithPath: "/System/Library")

        do {
            try await service.updateConfiguration(config)
            XCTFail("Expected rootDirectoryInvalid")
        } catch TFTPServiceError.rootDirectoryInvalid {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
