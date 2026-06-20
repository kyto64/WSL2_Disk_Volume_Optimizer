# Safety Guide

This project automates VHDX compaction for WSL2 and Docker Desktop environments. VHDX compaction can reclaim disk space on Windows, but it is still a low-level disk operation. Read this guide before using the tool on an important WSL distribution.

## What This Tool Changes

The tool changes the host-side VHDX file that backs a WSL2 distribution or Docker Desktop WSL backend. Specifically, it attempts to compact unused blocks inside `ext4.vhdx` so the file occupies less space on the Windows filesystem.

The script:

- Searches common locations under `%LOCALAPPDATA%\Packages` and `%LOCALAPPDATA%\Docker`.
- Runs `wsl --shutdown` to release WSL file locks.
- Uses `Optimize-VHD -Mode Full` when available.
- Falls back to a `diskpart` script that attaches the VHDX read-only, runs `compact vdisk`, and detaches it.
- Reports before/after VHDX file sizes.

## What This Tool Does Not Change

The tool is not intended to modify data inside your Linux distribution.

It does not intentionally change:

- Files inside your WSL filesystem.
- Installed Linux packages.
- `wsl.conf` or other distro configuration files.
- Windows registry settings.
- Docker images, containers, or volumes at the Docker object level.
- Windows user files outside the VHDX files it detects.

However, a failed or interrupted VHDX operation can still make the entire distribution unusable. Treat compaction as a risky maintenance task and keep backups.

## Pre-flight Checklist

Before running the optimizer:

- Confirm you are on Windows 10/11 with WSL2 enabled.
- Close terminals, editors, Docker workloads, and background services that may be using WSL.
- Back up important distributions with `wsl --export`.
- Back up important Docker Desktop data using Docker-supported export or backup workflows.
- Ensure the machine has stable power and will not sleep during compaction.
- Ensure Windows has enough free space for normal disk operations.
- Run the tool from an elevated Command Prompt or PowerShell window.

Example WSL backup:

```powershell
wsl --list --verbose
wsl --export Ubuntu D:\Backups\Ubuntu-before-vhdx-compact.tar
```

## Recovery Procedures

### If a WSL Distribution Fails to Start

1. Stop WSL completely:

   ```powershell
   wsl --shutdown
   ```

2. Confirm the distribution status:

   ```powershell
   wsl --list --verbose
   ```

3. If the distribution remains unusable, restore from a previously exported backup:

   ```powershell
   wsl --unregister Ubuntu
   wsl --import Ubuntu C:\WSL\Ubuntu D:\Backups\Ubuntu-before-vhdx-compact.tar --version 2
   ```

Use the correct distribution name and install path for your environment. `wsl --unregister` deletes the existing distribution, so only run it after confirming that your backup is valid.

### Docker Desktop Backup Considerations

Before compacting Docker Desktop VHDX files:

- Quit Docker Desktop completely so WSL-backed Docker disks are not in use.
- Export or otherwise back up important images, containers, and volumes. Example image backup:

  ```powershell
  docker save my-image:tag -o D:\Backups\my-image.tar
  ```

- If you moved Docker Desktop storage through Settings → Resources → Disk image location, confirm the custom path in `%APPDATA%\Docker\settings.json` (`customWslDistroDir`) is included in the detection summary or pass it explicitly with `-VHDPath`.
- Review the Docker Desktop detection summary in the script output before proceeding. It reports which Docker-related VHDX files were detected, which expected paths were missing, and which layouts were skipped because they are not used on your system.
- Use `-WhatIf` first when you want to confirm Docker detection without shutting down WSL or compacting anything.

Common Docker Desktop WSL2 backend paths checked by the tool include:

- `%LOCALAPPDATA%\Docker\wsl\data\ext4.vhdx`
- `%LOCALAPPDATA%\Docker\wsl\distro\ext4.vhdx`
- `%LOCALAPPDATA%\Docker\wsl\main\ext4.vhdx`
- `%LOCALAPPDATA%\Docker\wsl\disk\ext4.vhdx`
- `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx`
- Custom roots such as `%LOCALAPPDATA%\Docker\wsl\DockerDesktopWSL` or `customWslDistroDir`

### If Docker Desktop Data Is Affected

Docker Desktop stores data in WSL-backed virtual disks when using the WSL2 backend. If Docker Desktop no longer starts after compaction:

- Restart Docker Desktop.
- Run `wsl --shutdown`, then start Docker Desktop again.
- Restore critical images, volumes, or containers from your own backups.
- As a last resort, use Docker Desktop's reset or factory reset options. This can delete local Docker data.

## Known Risks

- VHDX corruption if the compaction process is interrupted.
- WSL distributions becoming unavailable until restored from backup.
- Docker Desktop local data requiring restore or reset.
- Long execution time on large VHDX files.
- Temporary system slowdown while Windows performs disk operations.
- Missed VHDX files when distributions are stored in custom locations.

## Safer Testing Strategy

For development or review, test on a disposable WSL distribution instead of your daily environment:

```powershell
wsl --import TestUbuntu C:\WSL\TestUbuntu D:\Images\ubuntu-rootfs.tar --version 2
```

After testing, remove the disposable distribution:

```powershell
wsl --unregister TestUbuntu
```

### Dry-run Preview

Before running the actual optimizer, use dry-run mode to review detected VHDX files and planned commands without making changes:

```powershell
.\Optimize-WSL2Disk.ps1 -WhatIf
```

Dry-run mode:

- Lists detected VHDX paths, sizes, and sources.
- Shows planned `docker system prune`, `wsl --shutdown`, and compaction commands.
- Prints safety warnings and an estimated risk level.
- Does not call `wsl --shutdown`, `Optimize-VHD`, `diskpart`, or `docker system prune`.

Use `-DryRun` as an alias for `-WhatIf`. Dry-run mode does not require administrator privileges because it only reports detection results and planned actions.

## Reporting Safety Issues

If you find behavior that could unexpectedly delete data, compact the wrong file, bypass confirmation, or damage a distribution, please report it through the repository's security process. See [SECURITY.md](../SECURITY.md).
