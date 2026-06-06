# WSL2 Disk Volume Optimizer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/en-us/windows)
[![WSL2](https://img.shields.io/badge/WSL2-Compatible-green.svg)](https://docs.microsoft.com/en-us/windows/wsl/)

Safely compact WSL2 and Docker Desktop VHDX files to reclaim disk space on Windows.

## The Problem

WSL2 stores each Linux distribution in an `ext4.vhdx` virtual disk. That file can grow large over time, especially when using package caches, build artifacts, Docker images, and containers.

Deleting files inside WSL2 does not always return the space to Windows. The Linux filesystem may have free blocks, but the host-side `ext4.vhdx` can remain large until it is compacted. Manual compaction with `diskpart` is possible, but the sequence is easy to get wrong and can damage a distribution if the VHDX is still in use.

## What This Tool Does

WSL2 Disk Volume Optimizer automates the safer path:

- Detects `ext4.vhdx` files in common WSL2 and Docker Desktop locations.
- Optionally runs `docker system prune --force` inside WSL before compaction.
- Runs `wsl --shutdown` before touching VHDX files so they are not mounted.
- Compacts each VHDX with `Optimize-VHD` when available, then falls back to `diskpart`.
- Reports before/after file sizes so you can confirm how much host disk space was reclaimed.

## Quick Start

**TL;DR**: free up WSL2 disk space in 3 steps:

1. Download the latest release or clone this repository.
2. Open Command Prompt or PowerShell as Administrator.
3. Run `WSL2-DiskOptimizer.bat`.

```cmd
git clone https://github.com/kyto64/WSL2_Disk_Volume_Optimizer.git
cd WSL2_Disk_Volume_Optimizer
WSL2-DiskOptimizer.bat
```

> Important: export or otherwise back up important WSL distributions before compacting VHDX files.

## Requirements

- Windows 10/11 with WSL2 enabled
- PowerShell 5.1 or later
- Administrator privileges
- Windows `diskpart` utility
- Optional: Hyper-V PowerShell module for `Optimize-VHD`

## Usage

### Interactive Batch Wrapper

Use this for normal manual runs:

```cmd
WSL2-DiskOptimizer.bat
```

The wrapper checks administrator privileges, verifies that `Optimize-WSL2Disk.ps1` is present, asks whether to run Docker cleanup, and then starts the PowerShell script.

The Docker cleanup menu can:

- skip Docker cleanup
- run `docker system prune --force` in the default WSL distribution
- run `docker system prune --force` in a named WSL distribution

This standard Docker prune does not remove volumes and does not remove all unused tagged images.

### Direct PowerShell Execution

Use this when integrating with your own scripts:

```powershell
.\Optimize-WSL2Disk.ps1
```

To skip the confirmation prompt:

```powershell
.\Optimize-WSL2Disk.ps1 -Force
```

To run Docker cleanup before WSL shutdown and VHDX compaction:

```powershell
.\Optimize-WSL2Disk.ps1 -DockerPrune
```

To run Docker cleanup in a specific WSL distribution:

```powershell
.\Optimize-WSL2Disk.ps1 -DockerPrune -DockerPruneDistro Ubuntu
```

To include a VHDX file or directory that automatic detection misses:

```powershell
.\Optimize-WSL2Disk.ps1 -VHDPath "C:\Users\user\AppData\Local\wsl\{guid}\ext4.vhdx"
```

## Measuring Results

The amount of recovered space depends on your workload, deleted files, Docker usage, filesystem state, and Windows storage behavior. Instead of relying on a fixed benchmark, measure your own environment before and after a run.

Check VHDX file sizes from Windows:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Packages\*\LocalState\ext4.vhdx" -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{Name="SizeGB";Expression={[Math]::Round($_.Length / 1GB, 2)}}

Get-ChildItem "$env:LOCALAPPDATA\Docker" -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue |
    Select-Object FullName, @{Name="SizeGB";Expression={[Math]::Round($_.Length / 1GB, 2)}}

Get-ChildItem "$env:LOCALAPPDATA\wsl" -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue |
    Select-Object FullName, @{Name="SizeGB";Expression={[Math]::Round($_.Length / 1GB, 2)}}
```

Check filesystem usage from inside WSL:

```bash
wsl -d Ubuntu -- df -h /
```

Record the execution environment with your result:

| Item | Example |
|------|---------|
| Windows version | Windows 11 23H2 |
| WSL2 distribution | Ubuntu 22.04 |
| Docker Desktop | Installed / Not installed |
| Before VHDX size | Your measured value |
| After VHDX size | Your measured value |
| Recovered space | Calculated from your measured values |

## Example Logs

### Successful Run

The exact sizes and paths depend on your machine.

```text
[2026-05-31 14:30:00] [INFO] Starting WSL2 Disk Volume Optimizer
[2026-05-31 14:30:00] [INFO] Checking WSL status...
[2026-05-31 14:30:01] [INFO] Shutting down WSL...
[2026-05-31 14:30:04] [SUCCESS] WSL shutdown completed
[2026-05-31 14:30:04] [INFO] Searching for WSL VHD files...
[2026-05-31 14:30:05] [INFO] Found VHD files:
[2026-05-31 14:30:05] [INFO]   - C:\Users\user\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_...\LocalState\ext4.vhdx (Size: <before> GB, Last Modified: ...)
[2026-05-31 14:30:05] [INFO] Optimizing VHD file: C:\Users\user\AppData\Local\Packages\...\ext4.vhdx
[2026-05-31 14:30:05] [WARN] Optimize-VHD is not available: ...
[2026-05-31 14:30:05] [INFO] Compressing VHD using diskpart: C:\Users\user\AppData\Local\Packages\...\ext4.vhdx
[2026-05-31 14:35:20] [SUCCESS] VHD compression completed using diskpart
[2026-05-31 14:35:20] [SUCCESS] Optimization completed: C:\Users\user\AppData\Local\Packages\...\ext4.vhdx
[2026-05-31 14:35:20] [INFO]   Before: <before> GB
[2026-05-31 14:35:20] [INFO]   After: <after> GB
[2026-05-31 14:35:20] [SUCCESS]   Space saved: <saved> GB
[2026-05-31 14:35:20] [INFO] Optimization process completed
[2026-05-31 14:35:20] [INFO] Success: 1 / 1 files
[2026-05-31 14:35:20] [SUCCESS] Please restart WSL to verify the results
```

### Administrator Privileges Missing

```text
[ERROR] This script requires administrator privileges.

Please follow these steps:
1. Open Command Prompt or PowerShell as "Run as administrator"
2. Navigate to this folder
3. Run this batch file
```

### No VHDX Files Found

```text
[2026-05-31 14:30:00] [INFO] Starting WSL2 Disk Volume Optimizer
[2026-05-31 14:30:01] [SUCCESS] WSL shutdown completed
[2026-05-31 14:30:01] [INFO] Searching for WSL VHD files...
[2026-05-31 14:30:02] [ERROR] No VHD files found
```

## Safety

VHDX compaction is a disk operation. Read [docs/SAFETY.md](docs/SAFETY.md) before using this tool on an important distribution.

### Why Administrator Privileges Are Required

The script uses Windows disk-management operations (`Optimize-VHD` or `diskpart`) against VHDX files. These operations require elevated permissions because they attach, inspect, and compact virtual disks.

### Why WSL Is Shut Down

The script runs `wsl --shutdown` before compaction so that distributions and Docker Desktop WSL backends release their VHDX file locks. Compacting a mounted or active VHDX is unsafe.

### Backup Recommendation

Export important distributions before running the optimizer:

```powershell
wsl --export Ubuntu D:\Backups\Ubuntu-before-vhdx-compact.tar
```

For Docker Desktop data, use Docker's own backup/export process for important images, volumes, and containers.

## Process Flow

1. Verify administrator privileges.
2. Check WSL availability.
3. Ask for confirmation unless `-Force` is used.
4. Optionally run `docker system prune --force` inside WSL.
5. Run `wsl --shutdown`.
6. Search registered WSL distributions and common locations for `ext4.vhdx`.
7. Compact each VHDX with `Optimize-VHD` or `diskpart`.
8. Report before/after sizes and success counts.

## Known Limitations

- WSL1 distributions are not supported.
- The search logic checks registered WSL2 distributions, `%LOCALAPPDATA%\wsl`, `%LOCALAPPDATA%\Packages`, and `%LOCALAPPDATA%\Docker`.
- Custom VHDX locations can be included with `-VHDPath`.
- Docker Desktop VHDX paths can vary by Docker Desktop version.
- Network-drive based WSL installations are not supported.
- The tool does not currently provide dry-run mode, JSON output, or interactive per-path selection.
- Compaction can take minutes to hours depending on VHDX size and disk speed.

## Troubleshooting

| Issue | Likely Cause | Resolution |
|-------|--------------|------------|
| `Optimize-VHD is not available` | Hyper-V module is unavailable | Expected behavior; the script falls back to `diskpart` |
| `This script must be run with administrator privileges` | The shell is not elevated | Reopen Command Prompt or PowerShell as Administrator |
| `Docker system prune failed` | Docker is unavailable in the selected WSL distribution | Start Docker or select the WSL distribution where Docker CLI works |
| `No VHD files found` | VHDX files are not registered or are in an unusual location | Check the searched locations in the log and rerun with `-VHDPath <path-to-ext4.vhdx>` |
| WSL distribution does not start after compaction | VHDX corruption or interrupted disk operation | Restore from a `wsl --export` backup |

Diagnostic commands:

```powershell
wsl --list --verbose
wsl -d <distribution> -- df -h /
```

## Documentation

- [Safety Guide](docs/SAFETY.md)
- [Roadmap](docs/ROADMAP.md)
- [Japanese README](README-JP.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)

## Support

- Open GitHub Issues for bug reports and feature requests.
- Pull Requests are welcome for documentation, tests, and safer automation.
- Include Windows version, WSL distro, Docker Desktop status, command used, and relevant logs when reporting a problem.

## License

This project is distributed under the MIT License. See [LICENSE](LICENSE).

## References

- [Microsoft WSL Documentation](https://docs.microsoft.com/en-us/windows/wsl/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Original Solution Reference](https://qiita.com/siruku6/items/c91a40d460095013540d)

---

**Important**: Back up important WSL distributions before compacting VHDX files.
