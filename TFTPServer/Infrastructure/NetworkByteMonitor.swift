// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Lee bytes transmitidos en vivo por un proceso vía `nettop -x` (sin sudo:
/// funciona porque `tftpd` corre como el usuario actual, no root — ver
/// `NativeTFTPService.plistContents`, clave `UserName`). Es la única fuente
/// real de progreso byte a byte: `tftpd` no expone esto por ningún otro medio
/// (log, API) — verificado en vivo (2026-09-05).
enum NetworkByteMonitor {
    struct ByteCounts {
        let bytesIn: Int64
        let bytesOut: Int64
    }

    /// `nil` si el proceso no existe o `nettop` no devolvió datos.
    ///
    /// Formato esperado de `nettop -x -J bytes_in,bytes_out`:
    /// ```
    ///                             bytes_in    bytes_out
    /// tftpd.66974                   123456     839296734
    ///    udp6 *.57770<->*.*         123456     839296734
    /// ```
    /// Se toma la línea del proceso (segunda línea no vacía), los dos
    /// últimos campos en orden bytes_in, bytes_out.
    static func byteCounts(forPID pid: Int32) async -> ByteCounts? {
        guard let output = try? await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/nettop"),
            arguments: ["-p", String(pid), "-l", "1", "-x", "-J", "bytes_in,bytes_out"]
        ) else {
            return nil
        }

        let lines = output.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }
        let fields = lines[1].split(separator: " ").compactMap { Int64($0) }
        guard fields.count >= 2 else { return nil }
        return ByteCounts(bytesIn: fields[fields.count - 2], bytesOut: fields[fields.count - 1])
    }

    static func currentPID() async -> Int32? {
        guard let output = try? await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
            arguments: ["-f", "/usr/libexec/tftpd"]
        ) else {
            return nil
        }
        let firstLine = output.standardOutput
            .split(separator: "\n")
            .first.map(String.init) ?? ""
        return Int32(firstLine.trimmingCharacters(in: .whitespaces))
    }
}
