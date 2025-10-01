#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Tool for freeing up WSL2 disk space

.DESCRIPTION
    Automatically detects WSL2's ext4.vhdx files and compresses them using Optimize-VHD or diskpart.
    Shuts down WSL before execution and verifies results after completion.

.PARAMETER Force
    Skip confirmation prompts and execute

.EXAMPLE
    .\Optimize-WSL2Disk.ps1

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -Force

.NOTES
    This script must be run with administrator privileges.
    It is strongly recommended to backup your WSL environment before execution.
#>

param(
    [switch]$Force
)

# Error handling
$ErrorActionPreference = "Stop"

# Log function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Administrator privilege check
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Get WSL distribution list
function Get-WSLDistributions {
    try {
        $wslList = wsl --list --verbose 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "WSL not found or not working properly"
        }
        return $wslList
    }
    catch {
        Write-Log "Failed to get WSL list: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

# Search for VHD files
function Find-WSLVHDFiles {
    $vhdFiles = @()
    $searchPaths = @(
        "$env:LOCALAPPDATA\Packages",
        "$env:LOCALAPPDATA\Docker"
    )

    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            Write-Log "Searching for VHD files: $searchPath"
            $files = Get-ChildItem -Path $searchPath -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $vhdFiles += [PSCustomObject]@{
                    Path = $file.FullName
                    SizeGB = [Math]::Round($file.Length / 1GB, 2)
                    LastModified = $file.LastWriteTime
                    Directory = $file.Directory.Name
                }
            }
        }
    }

    return $vhdFiles
}

# VHD optimization using Optimize-VHD
function Optimize-VHDNative {
    param([string]$VHDPath)

    try {
        Write-Log "Compressing VHD using Optimize-VHD: $VHDPath"
        Optimize-VHD -Path $VHDPath -Mode Full
        Write-Log "VHD compression completed using Optimize-VHD" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Optimize-VHD is not available: $($_.Exception.Message)" "WARN"
        return $false
    }
}

# VHD optimization using diskpart
function Optimize-VHDDiskpart {
    param([string]$VHDPath)

    try {
        Write-Log "Compressing VHD using diskpart: $VHDPath"

        # Create diskpart command file
        $diskpartScript = @"
select vdisk file="$VHDPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@

        $scriptPath = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $scriptPath -Value $diskpartScript -Encoding ASCII

        # Execute diskpart
        $result = Start-Process -FilePath "diskpart" -ArgumentList "/s `"$scriptPath`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\diskpart_output.txt" -RedirectStandardError "$env:TEMP\diskpart_error.txt"

        # Delete temporary file
        Remove-Item $scriptPath -Force

        if ($result.ExitCode -eq 0) {
            Write-Log "VHD compression completed using diskpart" "SUCCESS"
            return $true
        }
        else {
            $errorOutput = Get-Content "$env:TEMP\diskpart_error.txt" -ErrorAction SilentlyContinue
            throw "diskpart execution failed. Exit code: $($result.ExitCode). Error: $errorOutput"
        }
    }
    catch {
        Write-Log "VHD compression failed using diskpart: $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        # Cleanup temporary files
        @("$env:TEMP\diskpart_output.txt", "$env:TEMP\diskpart_error.txt") | ForEach-Object {
            if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }
    }
}

# Main process
function Main {
    Write-Log "Starting WSL2 Disk Volume Optimizer"

    # Administrator privilege check
    if (-not (Test-Administrator)) {
        Write-Log "This script must be run with administrator privileges" "ERROR"
        exit 1
    }

    # Warning display
    if (-not $Force) {
        Write-Host ""
        Write-Host "WARNING: IMPORTANT NOTICE" -ForegroundColor Yellow
        Write-Host "This tool will compress WSL2 VHD files."
        Write-Host "It is strongly recommended to backup your WSL environment before proceeding."
        Write-Host "If it fails, WSL2 may become inoperable."
        Write-Host ""
        $confirmation = Read-Host "Do you want to continue? (y/N)"
        if ($confirmation -notmatch '^[yY]$') {
            Write-Log "Operation cancelled"
            exit 0
        }
    }

    # Check WSL status
    Write-Log "Checking WSL status..."
    $wslDistributions = Get-WSLDistributions
    if ($null -eq $wslDistributions) {
        Write-Log "Failed to check WSL status" "ERROR"
        exit 1
    }

    # Shutdown WSL
    Write-Log "Shutting down WSL..."
    try {
        wsl --shutdown
        Start-Sleep -Seconds 3
        Write-Log "WSL shutdown completed" "SUCCESS"
    }
    catch {
        Write-Log "Failed to shutdown WSL: $($_.Exception.Message)" "ERROR"
        exit 1
    }

    # Search for VHD files
    Write-Log "Searching for WSL VHD files..."
    $vhdFiles = Find-WSLVHDFiles

    if ($vhdFiles.Count -eq 0) {
        Write-Log "No VHD files found" "ERROR"
        exit 1
    }

    Write-Log "Found VHD files:"
    $vhdFiles | ForEach-Object {
        Write-Log "  - $($_.Path) (Size: $($_.SizeGB) GB, Last Modified: $($_.LastModified))"
    }

    # Optimize each VHD file
    $successCount = 0
    foreach ($vhd in $vhdFiles) {
        Write-Log "Optimizing VHD file: $($vhd.Path)"
        $beforeSize = $vhd.SizeGB

        # Try Optimize-VHD first
        $optimized = Optimize-VHDNative -VHDPath $vhd.Path

        # If Optimize-VHD fails, use diskpart
        if (-not $optimized) {
            $optimized = Optimize-VHDDiskpart -VHDPath $vhd.Path
        }

        if ($optimized) {
            # Check size after optimization
            $afterSize = [Math]::Round((Get-Item $vhd.Path).Length / 1GB, 2)
            $savedSpace = [Math]::Round($beforeSize - $afterSize, 2)
            Write-Log "Optimization completed: $($vhd.Path)" "SUCCESS"
            Write-Log "  Before: $beforeSize GB"
            Write-Log "  After: $afterSize GB"
            Write-Log "  Space saved: $savedSpace GB" "SUCCESS"
            $successCount++
        }
        else {
            Write-Log "Failed to optimize VHD file: $($vhd.Path)" "ERROR"
        }
    }

    # Results report
    Write-Log "Optimization process completed"
    Write-Log "Success: $successCount / $($vhdFiles.Count) files"

    if ($successCount -gt 0) {
        Write-Log "Please restart WSL to verify the results" "SUCCESS"
        Write-Log "Example verification command: wsl -d Ubuntu -- df -h"
    }
}

# Execute script
try {
    Main
}
catch {
    Write-Log "An unexpected error occurred: $($_.Exception.Message)" "ERROR"
    exit 1
}