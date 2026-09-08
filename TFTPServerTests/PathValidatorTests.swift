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

    /// Auditoría de seguridad (2026-09-07): sin este rechazo, una carpeta con
    /// un salto de línea en el nombre podía terminar antes de tiempo el
    /// heredoc de shell que `NativeTFTPService` ejecuta con privilegios de
    /// administrador, inyectando comandos arbitrarios como root. Se rechaza
    /// cualquier carácter de control, no solo `\n`, por ser el punto de
    /// validación común a todo el flujo.
    func testRejectsControlCharactersInPath() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathValidatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let withNewline = URL(fileURLWithPath: base.path + "\nTFTPSERVER_PLIST_EOF\nrm -rf /")
        XCTAssertFalse(PathValidator.isValidRoot(withNewline))

        // La carpeta real, sin el sufijo malicioso, sigue siendo válida —
        // confirma que el rechazo es por el carácter de control, no por
        // casualidad de la ruta.
        XCTAssertTrue(PathValidator.isValidRoot(base))
    }
}
