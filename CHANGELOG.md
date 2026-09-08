# Changelog

All notable changes to this project are documented in this file.

## [1.0.0] - 2026-09-08

First stable release. No functional changes from 0.1.1 — every feature listed in 0.1.0 and 0.1.1 has now been exercised live end-to-end (concurrent transfers, permission repair, client IP capture, root-folder validation, integrity verified with MD5/SHA1 on multi-gigabyte transfers), with no known outstanding issues.

## [0.1.1] - 2026-09-08

### Added

- "Detecting" panel now caps its height with its own scroll view, matching the Downloads/Uploads panels.

### Changed

- "Change Path" is now disabled while the server is running, instead of accepting a change that only takes effect after a restart.

### Fixed

- A batch of very small, fast transfers (found live with 50 sequential tiny downloads) could get stuck permanently in the "Detecting" panel — their direction never resolved because they completed faster than the first progress poll. A second fallback now infers direction from whether the requested file already existed when the transfer was detected.

## [0.1.0] - 2026-09-08

Initial public release.

### Added

- Native `tftpd` management via a temporary LaunchDaemon — Start/Stop with a one-time macOS administrator authorization, no Terminal `sudo`, nothing left running after Stop.
- Independent Downloads and Uploads panels tracking genuinely concurrent transfers, each with real progress, speed, estimated time remaining, and its own Cancel button.
- Optional client IP display, captured narrowly (only the first packet of each request) and folded into Start's own authorization when enabled beforehand.
- One-click "Fix" for the most common setup mistake — an unreadable TFTP folder or its parent — with no extra authorization.
- A prompt with an inline "Fix" button right after picking a folder with a permission problem via "Change Path".
- Orphaned-server detection on launch, so a force-quit or crash never leaves the daemon silently listening.
- Transfer history tab (time, direction, filename, client IP, size, status, duration).
- Searchable in-app Help covering usage, security, and the TFTP protocol (RFC 1350 and its extensions).
- A TFTP root folder is validated to reject the filesystem root, top-level folders, system paths, and directory traversal.

### Fixed

- The chosen TFTP folder's path is now escaped before being embedded in the daemon's plist XML and transported as base64 instead of a raw shell heredoc, closing an injection class that a maliciously crafted folder name could otherwise exploit against a command run with administrator privileges.
- The client IP capture's log file was moved out of `/tmp` (a directory writable by any local user) into the current user's own cache folder, closing a symlink-race window against a command run as root.
- Applying a configuration change to an already-running server (e.g. toggling client IP capture) now uses a single authorization instead of two separate ones.
