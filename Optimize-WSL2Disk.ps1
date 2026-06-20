<#
.SYNOPSIS
    Tool for freeing up WSL2 disk space

.DESCRIPTION
    Automatically detects WSL2's ext4.vhdx files and compresses them using Optimize-VHD or diskpart.
    Shuts down WSL before execution and verifies results after completion.

.PARAMETER Force
    Skip confirmation prompts and execute

.PARAMETER WhatIf
    Report detected VHDX files, planned commands, and safety warnings without making changes.
    Does not run wsl --shutdown, Optimize-VHD, diskpart, or docker system prune.
    Alias: DryRun

.PARAMETER DockerPrune
    Run docker system prune --force inside WSL before shutting down WSL and compacting VHD files

.PARAMETER DockerPruneDistro
    Optional WSL distribution name used for Docker prune. Uses the default distribution when omitted.

.PARAMETER VHDPath
    Optional VHDX file path or directory path to include when automatic detection misses a distribution.

.EXAMPLE
    .\Optimize-WSL2Disk.ps1

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -Force

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -WhatIf

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -DryRun -DockerPrune

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -DockerPrune

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -DockerPrune -DockerPruneDistro Ubuntu

.EXAMPLE
    .\Optimize-WSL2Disk.ps1 -VHDPath "C:\Users\user\AppData\Local\wsl\{guid}\ext4.vhdx"

.NOTES
    Actual compaction requires administrator privileges.
    Use -WhatIf to preview planned actions without elevation.
    It is strongly recommended to backup your WSL environment before execution.
#>

param(
    [switch]$Force,
    [Alias("DryRun")]
    [switch]$WhatIf,
    [switch]$DockerPrune,
    [string]$DockerPruneDistro,
    [string[]]$VHDPath
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

# Run Docker cleanup inside WSL before VHD compaction
function Invoke-WSLDockerSystemPrune {
    param([string]$Distro)

    try {
        $wslArgs = @()
        if ([string]::IsNullOrWhiteSpace($Distro)) {
            Write-Log "Running Docker system prune in the default WSL distribution..."
            $wslArgs = @("--", "docker", "system", "prune", "--force")
        }
        else {
            Write-Log "Running Docker system prune in WSL distribution: $Distro"
            $wslArgs = @("-d", $Distro, "--", "docker", "system", "prune", "--force")
        }

        & wsl @wslArgs
        if ($LASTEXITCODE -ne 0) {
            throw "docker system prune failed. Exit code: $LASTEXITCODE"
        }

        Write-Log "Docker system prune completed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Docker system prune failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Search locations are kept for diagnostics when no VHDX files are found.
$script:LastVHDSearchLocations = @()

# Search for VHD files
function Find-WSLVHDFiles {
    param([string[]]$ExplicitPaths)

    $vhdFiles = New-Object System.Collections.ArrayList
    $seenPaths = @{}
    $script:LastVHDSearchLocations = @()

    function Add-SearchLocation {
        param([string]$Path, [string]$Source)

        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $script:LastVHDSearchLocations += "$Source - $Path"
        }
    }

    function Add-VHDFile {
        param(
            [string]$Path,
            [string]$Source,
            [string]$DistributionName = ""
        )

        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            if ($item.PSIsContainer) {
                return
            }

            if ($item.Extension -ne ".vhdx") {
                Write-Log "Skipping non-VHDX file: $Path" "WARN"
                return
            }

            $key = $item.FullName.ToLowerInvariant()
            if ($seenPaths.ContainsKey($key)) {
                return
            }

            $seenPaths[$key] = $true
            [void]$vhdFiles.Add([PSCustomObject]@{
                Path = $item.FullName
                SizeGB = [Math]::Round($item.Length / 1GB, 2)
                LastModified = $item.LastWriteTime
                Directory = $item.Directory.Name
                Source = $Source
                Distribution = $DistributionName
            })
        }
        catch {
            Write-Log "Unable to inspect VHDX candidate: $Path ($($_.Exception.Message))" "WARN"
        }
    }

    function Add-VHDFilesFromDirectory {
        param([string]$Path, [string]$Source)

        if (Test-Path -LiteralPath $Path) {
            Add-SearchLocation -Path $Path -Source $Source
            Write-Log "Searching for VHD files: $Path"
            $files = Get-ChildItem -LiteralPath $Path -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                Add-VHDFile -Path $file.FullName -Source $Source
            }
        }
    }

    if ($ExplicitPaths) {
        foreach ($explicitPath in $ExplicitPaths) {
            Add-SearchLocation -Path $explicitPath -Source "Explicit path"
            if (-not (Test-Path -LiteralPath $explicitPath)) {
                Write-Log "Explicit VHD path does not exist: $explicitPath" "WARN"
                continue
            }

            $explicitItem = Get-Item -LiteralPath $explicitPath -ErrorAction SilentlyContinue
            if ($null -eq $explicitItem) {
                continue
            }

            if ($explicitItem.PSIsContainer) {
                Write-Log "Searching for VHD files in explicit directory: $explicitPath"
                $files = Get-ChildItem -LiteralPath $explicitPath -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue
                foreach ($file in $files) {
                    Add-VHDFile -Path $file.FullName -Source "Explicit path"
                }
            }
            else {
                Add-VHDFile -Path $explicitItem.FullName -Source "Explicit path"
            }
        }
    }

    $lxssRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"
    if (Test-Path $lxssRoot) {
        Add-SearchLocation -Path $lxssRoot -Source "WSL registry"
        Write-Log "Searching registered WSL distributions from registry..."
        $distributions = Get-ChildItem -Path $lxssRoot -ErrorAction SilentlyContinue
        foreach ($distribution in $distributions) {
            try {
                $properties = Get-ItemProperty -Path $distribution.PSPath -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($properties.BasePath)) {
                    continue
                }

                $vhdFileName = $properties.VhdFileName
                if ([string]::IsNullOrWhiteSpace($vhdFileName)) {
                    $vhdFileName = "ext4.vhdx"
                }

                if ([System.IO.Path]::IsPathRooted($vhdFileName)) {
                    $registeredVhdPath = $vhdFileName
                }
                else {
                    $registeredVhdPath = Join-Path -Path $properties.BasePath -ChildPath $vhdFileName
                }

                Add-VHDFile -Path $registeredVhdPath -Source "WSL registry" -DistributionName $properties.DistributionName
            }
            catch {
                Write-Log "Failed to inspect WSL registry entry $($distribution.PSChildName): $($_.Exception.Message)" "WARN"
            }
        }
    }

    $searchPaths = @(
        "$env:LOCALAPPDATA\wsl",
        "$env:LOCALAPPDATA\Packages",
        "$env:LOCALAPPDATA\Docker"
    )

    foreach ($searchPath in $searchPaths) {
        Add-VHDFilesFromDirectory -Path $searchPath -Source "Standard path"
    }

    return @($vhdFiles)
}

# VHD optimization using Optimize-VHD
function Test-OptimizeVHDAvailable {
    return $null -ne (Get-Command Optimize-VHD -ErrorAction SilentlyContinue)
}

function Get-DiskpartCompactionScript {
    param([string]$VHDPath)

    return @"
select vdisk file="$VHDPath"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@
}

function Get-DockerPruneCommandText {
    param([string]$Distro)

    if ([string]::IsNullOrWhiteSpace($Distro)) {
        return "wsl -- docker system prune --force"
    }

    return "wsl -d `"$Distro`" -- docker system prune --force"
}

function Show-DryRunPlan {
    param(
        [array]$VHDFiles,
        [bool]$IncludeDockerPrune,
        [string]$DockerDistro
    )

    Write-Log "Dry-run mode enabled. No changes will be made." "WARN"
    Write-Host ""

    Write-Host "Safety warnings:" -ForegroundColor Yellow
    Write-Host "  - VHDX compaction is a low-level disk operation and can corrupt a distribution if interrupted."
    Write-Host "  - Export important WSL distributions before running the actual optimizer."
    Write-Host "  - wsl --shutdown stops all running WSL sessions and Docker Desktop WSL backends."
    if ($IncludeDockerPrune) {
        Write-Host "  - docker system prune removes unused Docker images, containers, and networks."
    }
    Write-Host ""

    Write-Host "Planned actions:" -ForegroundColor Cyan
    $step = 1

    if ($IncludeDockerPrune) {
        $dockerCommand = Get-DockerPruneCommandText -Distro $DockerDistro
        Write-Host "  $step. Run Docker cleanup: $dockerCommand"
        $step++
    }

    Write-Host "  $step. Shut down WSL: wsl --shutdown"
    $step++

    if ($VHDFiles.Count -eq 0) {
        Write-Host "  $step. No VHDX files detected. Compaction would not run."
        Write-Log "Dry-run completed. No VHDX files were detected." "WARN"
        return
    }

    Write-Host "  $step. Compact $($VHDFiles.Count) detected VHDX file(s):"
    $step++

    $useOptimizeVHD = Test-OptimizeVHDAvailable
    $totalSizeGB = 0

    foreach ($vhd in $VHDFiles) {
        $totalSizeGB += $vhd.SizeGB
        $distributionText = ""
        if (-not [string]::IsNullOrWhiteSpace($vhd.Distribution)) {
            $distributionText = ", Distribution: $($vhd.Distribution)"
        }

        Write-Host ""
        Write-Host "    Path: $($vhd.Path)" -ForegroundColor White
        Write-Host "    Size: $($vhd.SizeGB) GB, Last Modified: $($vhd.LastModified), Source: $($vhd.Source)$distributionText"

        if ($useOptimizeVHD) {
            Write-Host "    Planned method: Optimize-VHD -Path `"$($vhd.Path)`" -Mode Full"
        }
        else {
            Write-Host "    Planned method: diskpart (Optimize-VHD is not available on this system)"
            Write-Host "    Planned diskpart script:"
            $diskpartScript = Get-DiskpartCompactionScript -VHDPath $vhd.Path
            foreach ($line in ($diskpartScript -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-Host "      $line"
                }
            }
        }
    }

    Write-Host ""
    $estimatedRisk = if ($VHDFiles.Count -gt 0) { "High" } else { "Low" }
    if ($IncludeDockerPrune -and $estimatedRisk -ne "High") {
        $estimatedRisk = "Medium"
    }

    Write-Host "Estimated risk: $estimatedRisk" -ForegroundColor $(if ($estimatedRisk -eq "High") { "Red" } elseif ($estimatedRisk -eq "Medium") { "Yellow" } else { "Green" })
    Write-Host "Detected VHDX total size: $([Math]::Round($totalSizeGB, 2)) GB"
    Write-Host ""
    Write-Log "Dry-run completed. Re-run without -WhatIf to execute these actions." "SUCCESS"
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
        $diskpartScript = Get-DiskpartCompactionScript -VHDPath $VHDPath

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
    if ($WhatIf) {
        Write-Log "Preview mode: destructive operations are disabled" "WARN"
    }

    # Administrator privilege check
    if (-not $WhatIf -and -not (Test-Administrator)) {
        Write-Log "This script must be run with administrator privileges" "ERROR"
        exit 1
    }

    # Warning display
    if (-not $Force -and -not $WhatIf) {
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

    # Search for VHD files before any destructive action
    Write-Log "Searching for WSL VHD files..."
    $vhdFiles = Find-WSLVHDFiles -ExplicitPaths $VHDPath

    if ($WhatIf) {
        Show-DryRunPlan -VHDFiles $vhdFiles -IncludeDockerPrune:$DockerPrune -DockerDistro $DockerPruneDistro
        if ($vhdFiles.Count -eq 0 -and $script:LastVHDSearchLocations.Count -gt 0) {
            Write-Log "Searched locations:"
            $script:LastVHDSearchLocations | ForEach-Object {
                Write-Log "  - $_"
            }
            Write-Log "Run 'wsl --list --verbose' to confirm installed WSL2 distributions."
            Write-Log "If your VHDX is stored in a custom location, rerun with -VHDPath <path-to-ext4.vhdx>."
        }
        exit 0
    }

    if ($vhdFiles.Count -eq 0) {
        Write-Log "No VHD files found" "ERROR"
        if ($script:LastVHDSearchLocations.Count -gt 0) {
            Write-Log "Searched locations:"
            $script:LastVHDSearchLocations | ForEach-Object {
                Write-Log "  - $_"
            }
        }
        Write-Log "Run 'wsl --list --verbose' to confirm installed WSL2 distributions."
        Write-Log "If your VHDX is stored in a custom location, rerun with -VHDPath <path-to-ext4.vhdx>."
        exit 1
    }

    Write-Log "Found VHD files:"
    $vhdFiles | ForEach-Object {
        $distributionText = ""
        if (-not [string]::IsNullOrWhiteSpace($_.Distribution)) {
            $distributionText = ", Distribution: $($_.Distribution)"
        }
        Write-Log "  - $($_.Path) (Size: $($_.SizeGB) GB, Last Modified: $($_.LastModified), Source: $($_.Source)$distributionText)"
    }

    # Optional Docker cleanup before WSL shutdown
    if ($DockerPrune) {
        if (-not (Invoke-WSLDockerSystemPrune -Distro $DockerPruneDistro)) {
            exit 1
        }
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
