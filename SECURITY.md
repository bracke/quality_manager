# Security Policy

## Supported Versions

Security fixes are provided for the current `main` branch. No released stable version exists yet.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting for
`bracke/quality_manager`, or email the maintainer address listed in `alire.toml`. Include the affected revision,
reproduction steps, expected impact, and any known workaround. You should receive an acknowledgement within seven
days. Disclosure timing will be coordinated after a fix is available.

## Security Boundaries

Treat coordinator databases, approval records, signing private keys, integration configuration, and model-runner
workspaces as sensitive. A report is especially useful when it concerns authorization bypass, task duplication,
incorrect evidence binding, unsafe recovery, command execution, or acceptance of stale/incomplete quality evidence.

Never attach production databases, credentials, private keys, or proprietary source to a report. Use minimized
fixtures and redact diagnostics before sharing them.
