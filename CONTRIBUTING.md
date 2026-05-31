# Contributing

Thank you for considering a contribution to WSL2 Disk Volume Optimizer. This project touches WSL2 and VHDX files, so safety and clear documentation matter as much as code changes.

## Development Environment

Recommended environment:

- Windows 10/11 with WSL2 enabled
- PowerShell 5.1 or later
- Git
- Visual Studio Code with the PowerShell extension
- Optional: PSScriptAnalyzer and Pester

Install optional PowerShell tooling:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Pester -Scope CurrentUser
```

## Local Validation

Run static analysis when possible:

```powershell
Invoke-ScriptAnalyzer -Path .\Optimize-WSL2Disk.ps1
```

Check PowerShell syntax:

```powershell
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content .\Optimize-WSL2Disk.ps1 -Raw), [ref]$null)
```

## Safe Testing

Do not test destructive or disk-level changes on your daily WSL distribution first.

Recommended approach:

1. Create or import a disposable WSL2 distribution.
2. Confirm it contains no important data.
3. Back it up with `wsl --export`.
4. Run the optimizer from an elevated shell.
5. Confirm the disposable distribution still starts.
6. Delete it when finished.

Example cleanup:

```powershell
wsl --unregister TestUbuntu
```

## Pull Request Flow

1. Open or reference an Issue when changing behavior.
2. Create a topic branch from `main`.
3. Keep changes focused and easy to review.
4. Update README or docs when behavior, requirements, or safety guidance changes.
5. Include validation steps in the PR description.

Pull Requests may be written in English or Japanese.

## Documentation Standards

When documenting disk operations:

- State whether administrator privileges are required.
- Explain whether WSL is shut down.
- Include backup guidance.
- Avoid implying a guaranteed amount of recovered disk space.
- Prefer user-measured before/after values over fixed benchmark claims.

## Security and Safety

Please do not publicly disclose vulnerabilities that could cause data loss, unsafe path handling, or unexpected disk operations. Follow [SECURITY.md](SECURITY.md) for security reports.
