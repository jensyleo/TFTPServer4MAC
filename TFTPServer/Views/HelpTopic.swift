// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One page of the Help window — a sidebar of topics rather than one long
/// scrolling page, so a question has a place to be looked up rather than
/// scrolled to. Structure and styling deliberately mirror `HelpTopic`/
/// `HelpView` from jensyleo's own ROMForge/HardwareSentry (2026-09-05
/// request: "el help de la app debe ser como el de ROMForge") — same
/// `HelpSection`/`Row` shape, same searchable sidebar, same term-row styling
/// for enumerable settings/actions.
///
/// **Mantenimiento:** cada vez que se agregue una característica a la app,
/// actualizar el topic correspondiente aquí — es el único lugar donde vive
/// el contenido de ayuda, separado de `HelpView.swift` (que solo renderiza).
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let sections: [HelpSection]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HelpSection: Identifiable, Hashable {
    let id = UUID()
    var heading: String?
    var paragraphs: [String] = []
    /// Term-and-explanation rows, for actions and settings enumerated one
    /// after another (every toolbar button, every status color).
    var rows: [Row] = []

    struct Row: Identifiable, Hashable {
        let id = UUID()
        let term: String
        let detail: String
        /// A quiet tag beside the term — a default value, "Off by default".
        var note: String?
    }
}

enum HelpLibrary {
    static let topics: [HelpTopic] = [
        HelpTopic(id: "what-it-does", title: "What TFTP Server does", symbol: "sparkles", sections: [
            HelpSection(paragraphs: [
                "TFTP Server is a native macOS GUI for the TFTP service already built into macOS (`tftpd`, RFC 1350). It does not reimplement the TFTP protocol — it manages the real Apple binary via a temporary LaunchDaemon, so every transfer is handled by the same code Apple ships.",
                "It is a server only: it responds to requests from other devices (routers, switches, PXE clients) that ask it for files. It does not act as a TFTP client itself — there is no \"download from another server\" feature.",
            ]),
            HelpSection(heading: "Security warning", paragraphs: [
                "TFTP is an unauthenticated, unencrypted protocol from 1980. Any device that can reach this Mac's TFTP port can request files from the configured TFTP folder. Only run this on trusted, isolated networks — never expose it to the open internet.",
            ]),
        ]),
        HelpTopic(id: "getting-started", title: "Getting Started", symbol: "play.circle", sections: [
            HelpSection(paragraphs: [
                "1. Choose a TFTP folder (\"Change Path\"). 2. Copy the file a device needs into that folder. 3. Press Start and authorize once. 4. Configure the device with this Mac's IP (shown next to the network interface picker). 5. Press Stop when done.",
            ]),
            HelpSection(heading: "The bottom status bar", paragraphs: [
                "Shows three columns: Server status (with the Start/Stop button), Working path permissions, and Parent folder permissions. If either permissions column ever shows \"Fix needed\", a \"Fix\" button appears right there — it adds the missing read/traverse permission for your own user account, without needing any password (this app only ever touches folders you already own).",
            ]),
            HelpSection(heading: "Toolbar", rows: [
                .init(term: "Start / Stop TFTP", detail: "Loads or unloads the TFTP daemon. Both require a one-time macOS administrator authorization dialog — see \"Why the password prompts\"."),
                .init(term: "Change Path", detail: "Picks the folder the server reads from and writes to. Rejects the entire disk (\"/\"), top-level folders like /Users or /Applications, system folders, and paths containing \"..\" — a TFTP root must be a real folder of your own, at least two levels deep, so a misconfigured server can never expose more than one specific folder."),
                .init(term: "Reveal", detail: "Opens the current TFTP folder in Finder."),
                .init(term: "Create File", detail: "Creates an empty placeholder file in the TFTP folder — useful for preparing an upload target, since by default `tftpd` can only overwrite a file that already exists."),
                .init(term: "Refresh", detail: "Re-reads the file list and permission checks without restarting the server."),
            ]),
        ]),
        HelpTopic(id: "transfers", title: "Transfers & progress", symbol: "arrow.up.arrow.down.circle", sections: [
            HelpSection(heading: "The progress panel", paragraphs: [
                "Appears automatically the moment a device requests a file, as a floating panel — not a window that blocks the rest of the app. Shows a real percentage (not simulated) for downloads, since the file's total size is already known from disk; for uploads it shows bytes received so far, since the total size isn't reliably knowable in advance.",
                "Also shows live transfer speed, an estimated time remaining (downloads only), and an elapsed-time counter that becomes a final duration once the transfer ends.",
            ]),
            HelpSection(heading: "Multiple simultaneous transfers", paragraphs: [
                "The native `tftpd` genuinely serves more than one device at a time — this isn't simulated. Each active transfer gets its own card, with its own progress, speed, and Cancel button, independent of the others, even when two devices request the exact same file at the same time.",
                "TFTP has no file-locking of its own: if two devices upload to the same filename at the same time, both transfers complete without any error, but only one ends up as the file's final content — whichever one finishes writing last. This is inherent to the protocol, not something this app or macOS's `tftpd` can prevent.",
            ]),
            HelpSection(heading: "Two separate panels: Downloads and Uploads", paragraphs: [
                "Downloads and uploads appear in two independent floating panels (bottom-right and bottom-left) so it's immediately clear which devices are pulling files and which are pushing them. A brand-new transfer briefly shows in a small \"Detecting…\" panel (top-right) until its direction is determined — usually a fraction of a second — then moves into the matching panel.",
                "Each panel has its own combined progress and its own \"Done\" button. Starting a new transfer never affects the other panel, and never hides or dismisses cards that already finished — a finished card with its \"Done\" button still showing stays exactly as it is even if a new transfer starts (in the same panel or the other one) before you click it. There is no \"server busy\" state: every transfer is tracked independently by its own process, from the moment it's detected until it ends.",
                "When two or more downloads are running at once, the Downloads panel shows a combined progress bar above the individual cards, summing bytes transferred against total bytes across every download with a known size. Uploads have no reliable total to sum (see below), so the Uploads panel instead shows a running count and total bytes received.",
            ]),
            HelpSection(heading: "Cancel", rows: [
                .init(term: "Cancel", detail: "Stops the in-progress transfer immediately. Does not require re-entering a password — the transfer process runs as your own user, not as root."),
            ]),
            HelpSection(heading: "The \"Transfers\" tab", paragraphs: [
                "A running history of every transfer this session: time, direction, filename, size, status (Completed/Cancelled), and duration. Cleared when the app quits — it is not saved to disk.",
            ]),
            HelpSection(heading: "What isn't shown, and why", paragraphs: [
                "The requesting device's IP address isn't shown: reading it would require another administrator authorization just for that one detail, which isn't worth the friction. Whether the transfer is a firmware read or a config write is detected automatically a fraction of a second after it starts — briefly shown as \"Detecting…\".",
            ]),
        ]),
        HelpTopic(id: "security-permissions", title: "Security & permissions", symbol: "lock.shield", sections: [
            HelpSection(heading: "Why Start/Stop ask for a password", paragraphs: [
                "Listening on TFTP's standard port (UDP 69) requires macOS administrator privileges — that's an operating-system rule, not a choice made by this app. The app never uses Terminal `sudo`; it uses macOS's own native authorization dialog (Touch ID or your password), once per Start and once per Stop.",
                "Nothing is left behind: Stop removes every trace of the temporary service registration. If the app is force-quit or crashes while the server is running, the next launch detects this and requires you to authorize stopping it before the app can be used — see \"Orphaned server on launch\".",
            ]),
            HelpSection(heading: "Uploads — a real limitation of the native daemon", paragraphs: [
                "This app has no setting to enable uploads — there used to be one (\"Allow uploads\", passing `-w` to `tftpd`), but it was removed (2026-09-07) after testing showed `-w` doesn't reliably enable creating brand-new files in the per-user mode this app deliberately uses (see \"Why Start/Stop ask for a password\"). Apple's own manual page for `-w` notes it \"only works in directories writable by the user specified with -u option\", which points at the `-s`/`-u` chroot mode instead — a materially different, not-yet-investigated architecture.",
                "The one reliable way to receive an upload, with no setting needed: the target file must already exist in the TFTP folder and be writable by everyone. Use \"Create File\" to prepare an empty placeholder first, then let the device overwrite it.",
                "This also means `tftpd` will overwrite any file that already exists in the TFTP folder if that file's own permissions make it writable by everyone, whether or not you intended it as an upload target — this app can't override that. The safest setup is to keep files in the TFTP folder read-only unless you specifically intend them to be overwritten.",
            ]),
            HelpSection(heading: "No overwrite detection or confirmation", paragraphs: [
                "TFTP itself has no concept of confirming a write. When a device sends a file to a name that already exists (and is writable), `tftpd` overwrites it immediately — no warning, no \"are you sure?\", no backup of the previous content. This app cannot intervene: by the time it can tell a transfer is an upload (by watching bytes actually being written), the overwrite has already started or finished. The only real protection is prevention, not detection: keep \"Allow uploads\" off, and keep files in the TFTP folder read-only unless you specifically intend them to be replaceable.",
            ]),
        ]),
        HelpTopic(id: "protocol", title: "The TFTP protocol (RFC 1350)", symbol: "network", sections: [
            HelpSection(paragraphs: [
                "TFTP (Trivial File Transfer Protocol) dates to 1980 (RFC 1350) and was designed to be small enough to fit in the boot ROM of diskless workstations and network devices — which is exactly why it's still the standard way to push firmware and configs to routers, switches, and PXE boot clients today. \"Trivial\" is accurate: there is no login, no directory listing, no permissions model of its own, and no encryption.",
            ]),
            HelpSection(heading: "How a transfer works", rows: [
                .init(term: "RRQ (Read Request)", detail: "A client asks to download a file — this is a normal transfer through the app's \"Current Path\" folder."),
                .init(term: "WRQ (Write Request)", detail: "A client asks to upload a file — see \"Uploads\" and \"No overwrite detection\" above for what this actually allows."),
                .init(term: "DATA / ACK", detail: "The file moves in fixed-size blocks (512 bytes by default); each block is acknowledged individually before the next one is sent — this lockstep design is why TFTP is simple but slow compared to modern protocols on lossy networks."),
                .init(term: "ERROR", detail: "Sent instead of the above when something fails — file not found, access violation, disk full, illegal operation."),
            ]),
            HelpSection(heading: "Transfer modes", rows: [
                .init(term: "octet", detail: "Raw binary, byte for byte — what every real-world use case (firmware, configs, images) needs, and what this daemon is verified to use."),
                .init(term: "netascii", detail: "A text mode with its own line-ending conversion rules, mainly a historical artifact from the protocol's original Unix/text-file era. Not something a modern binary transfer would use."),
            ]),
            HelpSection(heading: "Extensions macOS's `tftpd` actually negotiates", paragraphs: [
                "Later RFCs (2347, 2348, 2349, 7440) added optional negotiation for transfer size, block size, timeout, and window size. macOS's own `tftpd` supports all of these — but they are negotiated by the requesting client, not configurable from this app. If a device's own TFTP client asks for a larger block size or a transfer-size confirmation, the daemon accommodates it automatically.",
            ]),
            HelpSection(heading: "Why this still matters for security", paragraphs: [
                "Nothing above includes authentication, encryption, or integrity checking beyond a per-block checksum implied by the transport. Anyone who can reach the configured UDP port can request any file the server will serve, under whatever name they ask for. This is inherent to the 1980 design, not a bug in macOS's implementation or this app — see \"Security warning\" in \"What TFTP Server does\".",
            ]),
        ]),
        HelpTopic(id: "limitations", title: "Known limitations", symbol: "exclamationmark.triangle", sections: [
            HelpSection(rows: [
                .init(term: "No control over client-negotiated options", detail: "Block size, timeout, and retry count are chosen by the requesting device, not configurable from this app — the native daemon accepts what the client asks for."),
                .init(term: "No per-IP allow/deny list", detail: "macOS's `tftpd` has no such feature; enforcing this would require separate firewall rules, which this app does not manage."),
                .init(term: "Large files may fail against real embedded clients", detail: "RFC 1350's 16-bit block number caps a standard transfer at about 32MB. Going further requires a non-standard \"block rollover\" extension — many TFTP clients built into routers, switches, and PXE boot ROMs (this app's own target use case) don't implement it. A firmware file over ~32MB may fail or behave unpredictably against such a device even though it transfers perfectly with a modern desktop TFTP client."),
            ]),
        ]),
        HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", sections: [
            HelpSection(heading: "Orphaned server on launch", paragraphs: [
                "If the app was force-quit or crashed while the server was running, the next launch shows a screen requiring you to authorize stopping it (or quit the app without resolving it) before you can use the app again — this prevents a TFTP server silently staying active without your knowledge.",
            ]),
            HelpSection(heading: "\"Access violation\" when a device tries to write a file", paragraphs: [
                "Either \"Allow uploads\" is off, or the target file doesn't already exist and isn't writable by everyone. Use \"Create File\" to prepare an empty, writable placeholder first, or enable uploads in Settings.",
            ]),
            HelpSection(heading: "A device times out trying to reach this Mac", paragraphs: [
                "Confirm \"Server status\" reads Running, confirm you gave the device the IP shown next to the correct network interface (not a different one, like a VPN), and confirm nothing else on this Mac is also listening on UDP 69 — the app already checks for macOS's own built-in TFTP service and refuses to start if it's active, but a third-party tool could still conflict.",
            ]),
        ]),
    ]
}
