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

/// Cuenta cuántas veces se pidió una elevación — usado para confirmar que
/// `restart()` combina detener y arrancar en una sola llamada (bug real
/// reportado en vivo, 2026-09-08: pedía la contraseña dos veces).
private final class RecordingPrivilegedShellRunner: PrivilegedShellRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func runElevated(_ shellCommand: String) throws {
        lock.lock()
        _callCount += 1
        lock.unlock()
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

    func testRestartUsesASingleAuthorization() async {
        let runner = RecordingPrivilegedShellRunner()
        let service = NativeTFTPService(privilegedShellRunner: runner)

        // `restart()` still fails overall here — the fake runner doesn't
        // actually load anything, so the real `launchctl print` check at
        // the end correctly reports "not registered". That's fine: this
        // test only cares whether `runElevated` was called once, not twice.
        _ = try? await service.restart()

        XCTAssertEqual(runner.callCount, 1)
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
