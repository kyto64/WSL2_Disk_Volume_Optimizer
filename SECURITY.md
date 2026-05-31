# Security Policy

WSL2 Disk Volume Optimizer performs administrator-level disk operations. Please report potential security or data-loss issues responsibly.

## Supported Versions

Only the latest release and the current `main` branch are actively reviewed on a best-effort basis.

## Reporting a Vulnerability

Use GitHub Security Advisories if private vulnerability reporting is available for this repository. If private reporting is not available, open a GitHub Issue with minimal reproduction details and avoid sharing exploit-ready instructions.

Useful report details:

- Windows version
- PowerShell version
- WSL version and distribution
- Docker Desktop version, if relevant
- Command used
- Expected behavior
- Actual behavior
- Relevant logs with personal paths or secrets removed

## In Scope

Please report issues such as:

- Unsafe path handling that could compact or modify the wrong file.
- Confirmation bypasses that trigger disk operations unexpectedly.
- Command injection or arbitrary code execution.
- Behavior that can corrupt a VHDX outside the documented risk model.
- Misleading success reporting after a failed disk operation.

## Out of Scope

The following are expected design constraints, not vulnerabilities by themselves:

- The tool requires administrator privileges.
- The tool shuts down WSL before compaction.
- VHDX compaction carries inherent risk if interrupted.
- Disk space recovery varies by environment.

## Response Expectations

This is an early-stage personal open source project. Reports are handled on a best-effort basis, with priority given to issues that could cause data loss, unexpected disk operations, or unsafe automation.

## Safe Disclosure

Please give the maintainer time to investigate and prepare a fix before public disclosure when a report involves data-loss risk or exploitable behavior.
