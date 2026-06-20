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
$script:LastDockerSearchResults = @()

function Get-DockerDesktopCustomStorageRoots {
    param(
        [string]$LocalAppDataRoot = $env:LOCALAPPDATA,
        [string]$AppDataRoot = $env:APPDATA
    )

    $roots = New-Object System.Collections.ArrayList
    $defaultDockerWslRoot = Join-Path $LocalAppDataRoot "Docker\wsl"
    $dockerDesktopWslRoot = Join-Path $defaultDockerWslRoot "DockerDesktopWSL"

    if (Test-Path -LiteralPath $dockerDesktopWslRoot) {
        [void]$roots.Add([PSCustomObject]@{
            Path = $dockerDesktopWslRoot
            Label = "Docker Desktop GUI disk image folder (DockerDesktopWSL)"
        })
    }

    $settingsPath = Join-Path $AppDataRoot "Docker\settings.json"
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settingsRaw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($settingsRaw)) {
                $settings = $settingsRaw | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace($settings.customWslDistroDir)) {
                    $customRoot = [Environment]::ExpandEnvironmentVariables($settings.customWslDistroDir)
                    if (-not [string]::IsNullOrWhiteSpace($customRoot)) {
                        [void]$roots.Add([PSCustomObject]@{
                            Path = $customRoot
                            Label = "Docker Desktop customWslDistroDir from settings.json"
                        })
                    }
                }
            }
        }
        catch {
            Write-Log "Unable to read Docker Desktop settings for custom storage paths: $settingsPath ($($_.Exception.Message))" "WARN"
        }
    }

    return @($roots)
}

function Get-DockerDesktopSearchTargets {
    param(
        [string]$LocalAppDataRoot = $env:LOCALAPPDATA,
        [string]$AppDataRoot = $env:APPDATA
    )

    $dockerWslRoot = Join-Path $LocalAppDataRoot "Docker\wsl"
    $targets = New-Object System.Collections.ArrayList

    $knownRelativeTargets = @(
        @{ RelativePath = "data\ext4.vhdx"; Label = "Legacy docker-desktop-data store" },
        @{ RelativePath = "distro\ext4.vhdx"; Label = "Legacy docker-desktop engine store" },
        @{ RelativePath = "main\ext4.vhdx"; Label = "Docker Desktop engine VM" },
        @{ RelativePath = "disk\ext4.vhdx"; Label = "Docker Desktop unified disk image" },
        @{ RelativePath = "disk\docker_data.vhdx"; Label = "Legacy Docker data disk" }
    )

    foreach ($knownTarget in $knownRelativeTargets) {
        [void]$targets.Add([PSCustomObject]@{
            Path = Join-Path $dockerWslRoot $knownTarget.RelativePath
            Label = $knownTarget.Label
            Layout = $knownTarget.RelativePath
            IsCustomRoot = $false
        })
    }

    foreach ($customRoot in (Get-DockerDesktopCustomStorageRoots -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot)) {
        [void]$targets.Add([PSCustomObject]@{
            Path = $customRoot.Path
            Label = $customRoot.Label
            Layout = "custom root"
            IsCustomRoot = $true
        })
    }

    return @($targets)
}

function Write-DockerDetectionReport {
    param([array]$VHDFiles)

    $dockerRegistryFiles = @($VHDFiles | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Distribution) -and $_.Distribution -match '^docker-desktop'
    })

    Write-Log "Docker Desktop detection summary:"
    $reportedPaths = @{}

    foreach ($result in $script:LastDockerSearchResults) {
        if ($result.Status -ne "Detected") {
            continue
        }

        $reportedPaths[$result.Path.ToLowerInvariant()] = $true
        Write-Log "  [DETECTED] $($result.Path) ($($result.Label))" "SUCCESS"
    }

    foreach ($file in $dockerRegistryFiles) {
        $key = $file.Path.ToLowerInvariant()
        if ($reportedPaths.ContainsKey($key)) {
            continue
        }

        $reportedPaths[$key] = $true
        Write-Log "  [DETECTED] $($file.Path) (Registered WSL distribution: $($file.Distribution))" "SUCCESS"
    }

    foreach ($result in $script:LastDockerSearchResults) {
        switch ($result.Status) {
            "NotFound" {
                Write-Log "  [NOT FOUND] $($result.Path) ($($result.Label))" "WARN"
            }
            "MissingCustomRoot" {
                Write-Log "  [NOT FOUND] $($result.Path) ($($result.Label))" "WARN"
            }
            "MissingRoot" {
                Write-Log "  [NOT FOUND] $($result.Path) ($($result.Label))" "WARN"
            }
            "MissingLayout" {
                Write-Log "  [SKIPPED] $($result.Path) ($($result.Label)) - layout not present on this system"
            }
            "CustomRootEmpty" {
                Write-Log "  [NOT FOUND] $($result.Path) ($($result.Label)) - no Docker VHDX files found in custom location" "WARN"
            }
        }
    }

    if ($dockerRegistryFiles.Count -eq 0 -and -not ($script:LastDockerSearchResults | Where-Object { $_.Status -eq "Detected" })) {
        Write-Log "  No Docker Desktop VHDX files detected. Docker Desktop may not be installed, may use an unsupported layout, or may require -VHDPath." "WARN"
    }
}

# Search for VHD files
function Find-WSLVHDFiles {
    param(
        [string[]]$ExplicitPaths,
        [string[]]$SearchPaths,
        [switch]$SkipRegistrySearch,
        [switch]$SkipDockerSearch,
        [string]$RegistryRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss",
        [string]$LocalAppDataRoot = $env:LOCALAPPDATA,
        [string]$AppDataRoot = $env:APPDATA,
        [array]$DockerSearchTargets
    )

    $vhdFiles = New-Object System.Collections.ArrayList
    $seenPaths = @{}
    $script:LastVHDSearchLocations = @()
    $script:LastDockerSearchResults = @()

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
            [string]$DistributionName = "",
            [string]$DockerLabel = ""
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
                DockerLabel = $DockerLabel
            })
        }
        catch {
            Write-Log "Unable to inspect VHDX candidate: $Path ($($_.Exception.Message))" "WARN"
        }
    }

    function Add-DockerSearchResult {
        param(
            [string]$Status,
            [string]$Path,
            [string]$Label,
            [string]$Message = ""
        )

        [void]$script:LastDockerSearchResults.Add([PSCustomObject]@{
            Status = $Status
            Path = $Path
            Label = $Label
            Message = $Message
        })
    }

    function Add-DockerVHDFilesFromRoot {
        param(
            [string]$RootPath,
            [string]$Label
        )

        Add-SearchLocation -Path $RootPath -Source "Docker Desktop"
        if (-not (Test-Path -LiteralPath $RootPath)) {
            Add-DockerSearchResult -Status "MissingCustomRoot" -Path $RootPath -Label $Label -Message "Custom Docker Desktop storage root not found"
            Write-Log "Docker Desktop custom storage path not found: $RootPath ($Label)" "WARN"
            return
        }

        Write-Log "Searching Docker Desktop custom storage path: $RootPath ($Label)"
        $dockerFileNames = @("ext4.vhdx", "docker_data.vhdx")
        $foundAny = $false

        foreach ($fileName in $dockerFileNames) {
            $files = Get-ChildItem -LiteralPath $RootPath -Recurse -Filter $fileName -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $foundAny = $true
                Add-VHDFile -Path $file.FullName -Source "Docker Desktop" -DockerLabel $Label
                Add-DockerSearchResult -Status "Detected" -Path $file.FullName -Label $Label
            }
        }

        if (-not $foundAny) {
            Add-DockerSearchResult -Status "CustomRootEmpty" -Path $RootPath -Label $Label -Message "No Docker VHDX files found in custom storage root"
            Write-Log "Docker Desktop custom storage path checked but no VHDX files were found: $RootPath ($Label)" "WARN"
        }
    }

    function Search-DockerDesktopVHDFiles {
        param([array]$Targets)

        $dockerWslRoot = Join-Path $LocalAppDataRoot "Docker\wsl"
        if (-not (Test-Path -LiteralPath $dockerWslRoot)) {
            Add-DockerSearchResult -Status "MissingRoot" -Path $dockerWslRoot -Label "Docker Desktop WSL root" -Message "Docker Desktop WSL directory not present"
            Write-Log "Docker Desktop WSL directory not found: $dockerWslRoot. Docker Desktop may not be installed or may use a custom-only layout." "WARN"
        }

        foreach ($target in $Targets) {
            if ($target.IsCustomRoot) {
                Add-DockerVHDFilesFromRoot -RootPath $target.Path -Label $target.Label
                continue
            }

            Add-SearchLocation -Path $target.Path -Source "Docker Desktop"
            if (Test-Path -LiteralPath $target.Path) {
                Add-VHDFile -Path $target.Path -Source "Docker Desktop" -DockerLabel $target.Label
                Add-DockerSearchResult -Status "Detected" -Path $target.Path -Label $target.Label
                continue
            }

            $parentPath = Split-Path -Path $target.Path -Parent
            if (Test-Path -LiteralPath $parentPath) {
                Add-DockerSearchResult -Status "NotFound" -Path $target.Path -Label $target.Label -Message "Expected Docker Desktop layout path exists but VHDX file was not found"
                Write-Log "Docker Desktop path checked but VHDX not found: $($target.Path) ($($target.Label))" "WARN"
            }
            else {
                Add-DockerSearchResult -Status "MissingLayout" -Path $target.Path -Label $target.Label -Message "Docker Desktop layout not present on this system"
            }
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

    if (-not $SkipRegistrySearch -and (Test-Path $RegistryRoot)) {
        Add-SearchLocation -Path $RegistryRoot -Source "WSL registry"
        Write-Log "Searching registered WSL distributions from registry..."
        $distributions = Get-ChildItem -Path $RegistryRoot -ErrorAction SilentlyContinue
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

    if ($null -eq $SearchPaths) {
        $SearchPaths = @(
            (Join-Path $LocalAppDataRoot "wsl"),
            (Join-Path $LocalAppDataRoot "Packages")
        )
    }

    foreach ($searchPath in $SearchPaths) {
        Add-VHDFilesFromDirectory -Path $searchPath -Source "Standard path"
    }

    if (-not $SkipDockerSearch) {
        if ($null -eq $DockerSearchTargets) {
            $DockerSearchTargets = Get-DockerDesktopSearchTargets -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        }

        Search-DockerDesktopVHDFiles -Targets $DockerSearchTargets
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
        $dockerLabelText = ""
        if (-not [string]::IsNullOrWhiteSpace($vhd.DockerLabel)) {
            $dockerLabelText = ", Docker: $($vhd.DockerLabel)"
        }
        Write-Host "    Size: $($vhd.SizeGB) GB, Last Modified: $($vhd.LastModified), Source: $($vhd.Source)$distributionText$dockerLabelText"

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
    Write-DockerDetectionReport -VHDFiles $vhdFiles

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
        $dockerLabelText = ""
        if (-not [string]::IsNullOrWhiteSpace($_.DockerLabel)) {
            $dockerLabelText = ", Docker: $($_.DockerLabel)"
        }
        Write-Log "  - $($_.Path) (Size: $($_.SizeGB) GB, Last Modified: $($_.LastModified), Source: $($_.Source)$distributionText$dockerLabelText)"
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

# Execute script when run directly, not when dot-sourced for tests.
if ($MyInvocation.InvocationName -ne '.' -and (Split-Path -Leaf $MyInvocation.InvocationName) -eq (Split-Path -Leaf $PSCommandPath)) {
    try {
        Main
    }
    catch {
        Write-Log "An unexpected error occurred: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}
