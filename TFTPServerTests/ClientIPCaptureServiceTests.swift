// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import XCTest
@testable import TFTPServer

final class ClientIPCaptureServiceTests: XCTestCase {
    func testParsesSourceIPFromTypicalLine() {
        let line = "08:52:00.123456 IP 10.4.200.5.54321 > 10.4.200.197.69: UDP, length 34"
        XCTAssertEqual(ClientIPCaptureService.parseSourceIP(from: line), "10.4.200.5")
    }

    func testParsesSourceIPWithDifferentPorts() {
        let line = "12:00:00.000000 IP 192.168.1.42.1024 > 10.4.200.197.69: UDP, length 40"
        XCTAssertEqual(ClientIPCaptureService.parseSourceIP(from: line), "192.168.1.42")
    }

    func testReturnsNilForUnrelatedLine() {
        XCTAssertNil(ClientIPCaptureService.parseSourceIP(from: "listening on en0, link-type EN10MB"))
        XCTAssertNil(ClientIPCaptureService.parseSourceIP(from: ""))
    }

    /// Bug real encontrado en vivo (2026-09-08): `-i any` en macOS capturó el
    /// mismo paquete de loopback dos veces, a 16 microsegundos de
    /// diferencia — timestamps distintos, mismo contenido después de eso.
    /// Sin colapsar duplicados, la siguiente transferencia real consumiría
    /// esa línea de más y le asignaría la IP equivocada.
    func testCollapsesDuplicateCaptureOfSamePacket() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClientIPCaptureServiceTests-\(UUID().uuidString).log").path
        let content = """
        09:26:53.852800 IP6 ::1.49163 > ::1.69: UDP, length 63
        09:26:53.852816 IP6 ::1.49163 > ::1.69: UDP, length 63
        09:26:58.100000 IP 10.4.200.5.1024 > 10.4.200.197.69: UDP, length 40
        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let lines = ClientIPCaptureService.readCapturedLines(path: path)

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(ClientIPCaptureService.parseSourceIP), ["::1", "10.4.200.5"])
    }
}
