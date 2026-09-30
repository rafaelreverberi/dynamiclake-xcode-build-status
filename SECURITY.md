# Security

Version 0.1.x is supported. Use GitHub's private vulnerability reporting for this repository instead of publishing sensitive reproduction data in an issue.

The plugin reads local Xcode build metadata and completed logs. It sends minimal UI frames only to the host-provided local Unix socket. It does not make network requests or collect telemetry. It never modifies Xcode, projects, schemes or build databases. Mutable duration history is stored separately in user Application Support, with hashed bucket names and private permissions.

Diagnostic titles are sanitized, limited and suppressed when they mention obvious secret-related terms. Compiler diagnostics may still expose private identifier names on screen. Do not attach raw xcactivitylog files, source, credentials, environment dumps or private full paths to a public report. Prefer a synthetic minimal fixture.

Malformed, unknown or oversized inputs degrade to omission/dismissal. Socket validation errors are reported generically and cause exit rather than an endless stream of rejected messages. The host removes activities when the client disconnects. Release builds are ad-hoc signed and not notarized.
