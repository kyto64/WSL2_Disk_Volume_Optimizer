# WSL2 Disk Volume Optimizer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/en-us/windows)
[![WSL2](https://img.shields.io/badge/WSL2-Compatible-green.svg)](https://docs.microsoft.com/en-us/windows/wsl/)

## Overview

The WSL2 Disk Volume Optimizer is a PowerShell-based automation tool designed to resolve disk space issues in Windows Subsystem for Linux 2 (WSL2) environments. This tool automatically detects and compresses WSL2's `ext4.vhdx` files to reclaim disk space on the host Windows system.

## Quick Start

**TL;DR**: Quickly free up WSL2 disk space in 3 steps:

1. **Download** the latest release or clone this repository
2. **Run as Administrator**: Execute `WSL2-DiskOptimizer.bat`
3. **Wait**: The tool will automatically optimize your WSL2 disk volumes

```cmd
# Clone the repository
git clone https://github.com/kyto64/wsl2-disk-volume-resolver.git
cd wsl2-disk-volume-resolver

# Run the optimizer (requires admin privileges)
WSL2-DiskOptimizer.bat
```

> ⚠️ **Important**: Always backup your WSL environments before running this tool!

## Problem Statement

WSL2 environments often experience disk space issues where:
- The `ext4.vhdx` virtual disk file grows over time but does not shrink when files are deleted within WSL
- Manual `diskpart` operations are time-consuming and error-prone
- Docker containers and images consume significant disk space within WSL
- System administrators require an automated solution for disk space management

## Solution Features

This tool provides:
- Automated detection of WSL2 VHD files across standard installation paths
- Intelligent compression using either `Optimize-VHD` cmdlet or `diskpart` as fallback
- Comprehensive error handling and logging
- Multiple execution methods for different operational requirements

## Technical Specifications

### System Requirements
- Windows 10/11 with WSL2 enabled
- PowerShell 5.1 or higher
- Administrator privileges
- Standard Windows `diskpart` utility

### Supported Environments
- All WSL2 distributions
- Docker Desktop for Windows with WSL2 backend
- Corporate and personal Windows environments

## Installation and Deployment

### Prerequisites
1. Ensure WSL2 is properly installed and configured
2. Verify PowerShell execution policy allows script execution
3. Obtain administrator privileges for the target system

### File Structure
```
wsl2-disk-volume-resolver/
├── Optimize-WSL2Disk.ps1      # Core VHD optimization PowerShell script
├── WSL2-DiskOptimizer.bat     # Interactive batch wrapper for easy execution
├── README.md                  # English documentation (this file)
├── README-JP.md               # Japanese documentation (日本語版)
└── LICENSE                    # MIT License terms
```

#### File Descriptions

- **`Optimize-WSL2Disk.ps1`**: The main PowerShell script that performs the actual VHD compression. Contains all the core logic for detecting WSL2 VHD files, shutting down WSL services, and executing compression operations.

- **`WSL2-DiskOptimizer.bat`**: A user-friendly batch file wrapper that provides an interactive interface. Handles administrator privilege checks and provides clear feedback during execution.

- **`README.md`**: Comprehensive English documentation covering installation, usage, troubleshooting, and best practices.

- **`README-JP.md`**: Complete Japanese translation of the documentation for Japanese-speaking users.

- **`LICENSE`**: MIT License file specifying the terms of use and distribution.

## Operational Procedures

### Method 1: Interactive Execution (Recommended for Production)

1. Open Command Prompt with administrator privileges
2. Navigate to the tool directory
3. Execute the interactive batch file:
   ```cmd
   WSL2-DiskOptimizer.bat
   ```
4. Execute VHD compression

### Method 2: Direct PowerShell Execution

For integration with existing automation frameworks:
```powershell
# VHD compression
.\Optimize-WSL2Disk.ps1

# Suppress confirmation prompts
.\Optimize-WSL2Disk.ps1 -Force
```

### Sample Output

A typical execution will produce output similar to:

```
[2024-10-01 14:30:00] [INFO] WSL2 Disk Volume Optimizer started
[2024-10-01 14:30:00] [INFO] Administrator privileges confirmed
[2024-10-01 14:30:01] [INFO] Shutting down WSL...
[2024-10-01 14:30:03] [SUCCESS] WSL shutdown completed
[2024-10-01 14:30:03] [INFO] Searching for VHD files...
[2024-10-01 14:30:04] [INFO] Found VHD: C:\Users\username\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx
[2024-10-01 14:30:04] [INFO] Original size: 45.2 GB
[2024-10-01 14:30:04] [INFO] Compressing VHD...
[2024-10-01 14:32:15] [SUCCESS] Compression completed
[2024-10-01 14:32:15] [INFO] New size: 12.8 GB
[2024-10-01 14:32:15] [SUCCESS] Space recovered: 32.4 GB (71.7% reduction)
[2024-10-01 14:32:15] [SUCCESS] Optimization completed successfully
```

## Process Flow

### Phase 1: Preparation
1. Administrator privilege verification
2. WSL status assessment
3. Required file existence validation
4. User confirmation (unless `-Force` parameter specified)

### Phase 2: WSL Management
1. Graceful shutdown of all WSL distributions
2. Process termination verification
3. File system lock release confirmation

### Phase 3: VHD Optimization
1. Automatic detection of `ext4.vhdx` files in standard locations:
   - `%LOCALAPPDATA%\Packages`
   - `%LOCALAPPDATA%\Docker`
2. Compression attempt using `Optimize-VHD` cmdlet
3. Fallback to `diskpart` if `Optimize-VHD` unavailable
4. Size comparison and space recovery calculation

### Phase 4: Verification and Reporting
1. Process completion status
2. Space recovery metrics
3. Operation success/failure summary
4. Recommendations for verification

## Expected Outcomes

### Performance Improvements
- Disk space recovery: Typically 20-80% of original VHD size
- I/O performance enhancement due to reduced file fragmentation
- Faster WSL startup times
- Improved system responsiveness

### Quantifiable Results
Example before/after comparison:
```
Before optimization:
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        250G  180G   57G  76% /

After optimization:
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        250G   45G  193G  19% /
```

## Risk Assessment and Mitigation

### Critical Warnings
- **Data Loss Risk**: Improper execution may result in WSL environment corruption
- **System Availability**: WSL services will be temporarily unavailable during optimization
- **Recovery Requirement**: Complete WSL environment backup is mandatory before execution

### Mitigation Strategies
1. **Mandatory Backup**: Execute WSL export before optimization
2. **Testing Protocol**: Validate in non-production environment first
3. **Rollback Plan**: Maintain verified backup and recovery procedures
4. **Monitoring**: Verify WSL functionality post-optimization

## Troubleshooting Guide

### Common Issues and Resolutions

| Issue | Cause | Resolution |
|-------|-------|------------|
| "Optimize-VHD not found" | Windows edition limitation | Expected behavior; tool uses diskpart automatically |
| "Administrator privileges required" | Insufficient permissions | Execute as administrator |
| "WSL distribution not starting" | Optimization failure | Restore from backup |

### Diagnostic Commands
```powershell
# Verify WSL status
wsl --list --verbose

# Check disk usage
wsl -d <distribution> -- df -h

# Validate file integrity
wsl -d <distribution> -- fsck /dev/sdb
```

## Maintenance and Support

### Regular Operations
- Schedule periodic execution (monthly recommended)
- Monitor disk space trends
- Maintain current backups
- Review execution logs for anomalies

### Version Control
This tool is maintained under Git version control with semantic versioning.

### Support Channels
- GitHub Issues for bug reports
- Pull Requests for contributions
- Documentation updates via repository

## Compliance and Licensing

This software is distributed under the MIT License, providing:
- Commercial use permission
- Modification rights
- Distribution authorization
- Private use allowance

### Disclaimer
This tool is provided "as-is" without warranties. Users assume full responsibility for:
- Data backup and recovery
- Testing in appropriate environments
- Compliance with organizational policies
- Risk assessment and mitigation

## References and Documentation

- [Microsoft WSL Documentation](https://docs.microsoft.com/en-us/windows/wsl/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Original Solution Reference](https://qiita.com/siruku6/items/c91a40d460095013540d)

---

**IMPORTANT**: Ensure complete WSL environment backup before executing this tool in production environments.
