function New-MockVhdxItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName,
        [long]$Length = 1073741824,
        [datetime]$LastWriteTime = [datetime]'2026-01-01T00:00:00'
    )

    $parentDirectory = Split-Path -Path $FullName -Parent

    return [PSCustomObject]@{
        FullName = $FullName
        PSIsContainer = $false
        Extension = [System.IO.Path]::GetExtension($FullName)
        Length = $Length
        LastWriteTime = $LastWriteTime
        Directory = [PSCustomObject]@{
            Name = Split-Path -Path $parentDirectory -Leaf
        }
    }
}

function New-MockDirectoryItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    return [PSCustomObject]@{
        FullName = $FullName
        PSIsContainer = $true
        Extension = ''
    }
}

function New-MockRegistryDistribution {
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyName,
        [string]$BasePath,
        [string]$DistributionName,
        [string]$VhdFileName = 'ext4.vhdx'
    )

    return [PSCustomObject]@{
        PSChildName = $KeyName
        PSPath = "Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Lxss\$KeyName"
        BasePath = $BasePath
        DistributionName = $DistributionName
        VhdFileName = $VhdFileName
    }
}

function Register-MockFileSystem {
    param(
        [hashtable]$Files = @{},
        [hashtable]$Directories = @{},
        [hashtable]$RegistryEntries = @{}
    )

    Mock Test-Path {
        param($LiteralPath, $Path)

        $targetPath = if ($LiteralPath) { $LiteralPath } else { $Path }
        if ($null -eq $targetPath) {
            return $false
        }

        return $Directories.ContainsKey($targetPath) -or $Files.ContainsKey($targetPath)
    }

    Mock Get-Item {
        param($LiteralPath, $Path)

        $targetPath = if ($LiteralPath) { $LiteralPath } else { $Path }
        if ($Files.ContainsKey($targetPath)) {
            return $Files[$targetPath]
        }

        if ($Directories.ContainsKey($targetPath)) {
            return $Directories[$targetPath]
        }

        throw "Item not found: $targetPath"
    }

    Mock Get-ChildItem {
        param(
            $LiteralPath,
            $Path,
            $Recurse,
            $Filter,
            $ErrorAction
        )

        $targetPath = if ($LiteralPath) { $LiteralPath } else { $Path }

        if ($RegistryEntries.ContainsKey($targetPath)) {
            return @($RegistryEntries[$targetPath])
        }

        $results = New-Object System.Collections.ArrayList

        foreach ($filePath in $Files.Keys) {
            $file = $Files[$filePath]
            $isDirectChild = (Split-Path -Path $filePath -Parent) -eq $targetPath
            $isUnderPath = $Recurse -and $filePath.StartsWith("$targetPath\", [System.StringComparison]::OrdinalIgnoreCase)

            if (-not $isDirectChild -and -not $isUnderPath) {
                continue
            }

            if ($Filter -and ([System.IO.Path]::GetFileName($filePath) -ne $Filter)) {
                continue
            }

            [void]$results.Add($file)
        }

        return @($results)
    }

    Mock Get-ItemProperty {
        param($Path, $ErrorAction)

        foreach ($entryList in $RegistryEntries.Values) {
            foreach ($entry in $entryList) {
                if ($entry.PSPath -eq $Path) {
                    return [PSCustomObject]@{
                        BasePath = $entry.BasePath
                        DistributionName = $entry.DistributionName
                        VhdFileName = $entry.VhdFileName
                    }
                }
            }
        }

        throw "Registry entry not found: $Path"
    }
}
