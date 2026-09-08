# Changelog

All notable changes to this project are documented in this file.

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
