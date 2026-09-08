# Security

## TFTP has no security model of its own

TFTP (RFC 1350) predates modern network security entirely. It has:

- **No authentication.** Any device that can reach the configured UDP port can request or write files, with no login of any kind.
- **No encryption.** File contents, filenames, and all protocol traffic are sent in plaintext.
- **No overwrite confirmation.** If a write request targets a file that already exists and is writable, the daemon overwrites it immediately — no warning, no confirmation, no backup.
- **No access control beyond filesystem permissions.** Whatever the configured TFTP folder and its files allow via normal Unix permissions is what a remote device can do.

None of this is specific to this app or to macOS's implementation — it is inherent to the 1980 protocol design.

## What this app does to reduce risk

- **Uploads only overwrite, never create.** There is no setting to enable uploads — the native daemon only allows overwriting a file that already exists in the TFTP folder and is writable by everyone. A device can never cause a brand-new file to appear.
- **No persistent exposure.** The TFTP service is only active between Start and Stop. Stopping (including an automatic stop on quit, or an orphaned-server check on the next launch after a crash) removes the service registration entirely — nothing keeps listening in the background.
- **Least privilege for transfers.** The actual file-transfer process runs under your own user account, not root, minimizing what a successful attack against it could reach.
- **No telemetry, no network calls beyond the TFTP service itself.** The app makes no external connections and collects no usage data.
- **Optional client IP visibility.** An opt-out toggle captures only the first packet of each request (never the transfer's actual data) so you can see which device is talking to the server — off requires no extra step, and turning it on before Start needs no separate authorization beyond Start's own.
- **Folder root can't be the entire disk.** The configured TFTP folder is validated to reject the filesystem root, top-level folders, system paths, and directory traversal — a misconfiguration can never expose more than one specific folder.

## What you should do

- **Only run this on trusted, isolated networks** — a lab network, an isolated VLAN, or a direct link to the device you're configuring. Never expose UDP port 69 to the open internet.
- **Don't make files in the TFTP folder writable by everyone** unless you intend for them to be overwritten by any device that can reach the service.
- **Stop the server when you're done** — don't leave it running longer than the task requires.

## Reporting a vulnerability

If you find a security issue in this app itself (as opposed to inherent TFTP protocol limitations, which are documented above and not considered vulnerabilities in this project), please open a GitHub issue describing the problem. This is a personal, non-commercial project maintained on a best-effort basis.
