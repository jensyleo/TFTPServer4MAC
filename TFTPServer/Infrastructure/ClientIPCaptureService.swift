// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Captura la IP de origen real del datagrama inicial (RRQ/WRQ) de cada
/// transferencia — la única forma real de obtenerla, confirmada en vivo
/// (2026-09-08): ni `lsof` ni `nettop` la exponen porque `tftpd` nunca hace
/// `connect()` a un peer específico (usa `recvfrom`/`sendto` genérico), así
/// que solo queda en el header IP de cada paquete — visible únicamente
/// capturando el tráfico.
///
/// Diseño deliberadamente acotado (feedback del usuario, 2026-09-08):
/// - Filtro de `tcpdump` restringido a `udp dst port 69` — solo el paquete
///   inicial de cada solicitud (RRQ/WRQ) pasa por ahí; la transferencia real
///   se mueve a un puerto efímero que este filtro nunca ve. El costo real de
///   `tcpdump` lo determina el filtro BPF (que descarta en el kernel todo lo
///   que no matchea, sin llegar a userspace), no la interfaz — por eso se usa
///   `-i any` en vez de rastrear cuál interfaz es "la correcta": cubre red
///   real y loopback sin ningún costo adicional relevante, ya que el filtro
///   ya excluye el volumen real de la transferencia.
/// - Sin resolución DNS (`-n`) ni verbosidad extra (`-q`): la única
///   información que se necesita es "IP origen . puerto > IP destino
///   . puerto", una sola línea corta por solicitud.
/// - La IP de origen no cambia durante una transferencia, así que no hace
///   falta seguir capturando después del primer paquete de cada una — el
///   filtro por puerto 69 ya logra eso por sí solo (nunca ve el resto del
///   tráfico de la transferencia).
///
/// Requiere root (capturar paquetes en macOS exige acceso a `/dev/bpf*`,
/// restringido a root en este sistema — confirmado en vivo, sin grupo
/// alternativo). Se lanza dentro de la MISMA elevación de Start (vía
/// `PrivilegedShellRunner`), sin pedir autorización aparte.
///
/// Registrado como su propio LaunchDaemon (2026-09-08) — no como
/// `nohup tcpdump ... &` suelto: eso falló en vivo con
/// `nohup: can't detach from console`, porque `do shell script ... with
/// administrator privileges` no deja sobrevivir de forma confiable a un
/// proceso puesto en segundo plano con `&` una vez que el script termina
/// (el proceso moría al instante). Un LaunchDaemon propio, cargado con
/// `launchctl load` igual que el de `tftpd`, es el mismo patrón ya probado
/// en este proyecto y no depende de que el shell padre siga vivo.
enum ClientIPCaptureService {
    static let logPath = "/tmp/com.jensyleo.tftpserver.client_ips.log"
    static let label = "com.jensyleo.tftpserver.capture"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    private static func plistContents() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/sbin/tcpdump</string>
                <string>-i</string>
                <string>any</string>
                <string>-n</string>
                <string>-q</string>
                <string>-l</string>
                <string>udp</string>
                <string>dst</string>
                <string>port</string>
                <string>69</string>
            </array>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>/dev/null</string>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }

    /// Se añade al MISMO comando elevado que ya escribe el plist de `tftpd`
    /// y hace `launchctl load` — una sola autorización cubre ambas cosas.
    /// El plist propio viaja en base64 por la misma razón que el de
    /// `tftpd` (ver `NativeTFTPService.start`): evita cualquier clase de
    /// inyección de shell sin importar el contenido.
    static func startCaptureShellFragment() -> String {
        let base64 = Data(plistContents().utf8).base64EncodedString()
        return """
        launchctl unload -w \(plistPath) 2>/dev/null
        rm -f \(logPath)
        touch \(logPath)
        chmod 644 \(logPath)
        echo \(base64) | base64 -D -o \(plistPath)
        launchctl load -w \(plistPath)
        """
    }

    /// Se añade al comando elevado de Stop.
    static func stopCaptureShellFragment() -> String {
        """
        launchctl unload -w \(plistPath) 2>/dev/null
        rm -f \(plistPath) \(logPath)
        """
    }

    /// Extrae la IP de origen de una línea de salida de `tcpdump -n -q`,
    /// p. ej. `08:52:00.123456 IP 10.4.200.5.54321 > 10.4.200.197.69: UDP, length 34`.
    /// La IP puede incluir puntos (IPv4) — el puerto es el último segmento
    /// tras el último punto.
    static func parseSourceIP(from line: String) -> String? {
        guard let range = line.range(of: #"IP6?\s+(\S+)\s+>"#, options: .regularExpression) else {
            return nil
        }
        let hostPort = String(line[range])
            .replacingOccurrences(of: #"^IP6?\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+>$"#, with: "", options: .regularExpression)
        guard let lastDot = hostPort.lastIndex(of: ".") else { return nil }
        return String(hostPort[..<lastDot])
    }

    /// Lee las líneas del archivo de captura en el orden en que llegaron
    /// (la más vieja primero) — `AppState` las consume en ese mismo orden
    /// para emparejarlas con las transferencias detectadas, que también
    /// llegan aproximadamente en orden de llegada.
    ///
    /// Colapsa capturas duplicadas del mismo paquete consecutivas: en vivo
    /// (2026-09-08) el mismo request produjo 2 líneas con el mismo par
    /// IP:puerto → IP:puerto a 16 microsegundos de diferencia — `-i any` en
    /// macOS puede capturar el mismo paquete de loopback dos veces por
    /// distintos puntos de captura. Sin colapsarlas, la siguiente
    /// transferencia real consumiría esa línea de más y le asignaría la IP
    /// equivocada (desfase de a uno en el emparejamiento FIFO). Se compara
    /// ignorando el timestamp inicial (que sí difiere), no la línea completa.
    static func readCapturedLines(path: String = logPath) -> [String] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let lines = contents.split(separator: "\n").map(String.init)
        var collapsed: [String] = []
        var lastSignature: String?
        for line in lines {
            let signature = signature(of: line)
            guard signature != lastSignature else { continue }
            collapsed.append(line)
            lastSignature = signature
        }
        return collapsed
    }

    /// La parte de la línea después del timestamp (`IP ... : UDP, length N`),
    /// usada para detectar duplicados del mismo paquete.
    private static func signature(of line: String) -> String {
        guard let firstSpace = line.firstIndex(of: " ") else { return line }
        return String(line[line.index(after: firstSpace)...])
    }
}
