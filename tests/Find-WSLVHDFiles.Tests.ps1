#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $scriptRoot 'tests\helpers\MockFileSystem.ps1')
    . (Join-Path $scriptRoot 'Optimize-WSL2Disk.ps1')
}

Describe 'Find-WSLVHDFiles path detection' {
    BeforeEach {
        $script:LastVHDSearchLocations = @()
        $script:LastDockerSearchResults = @()
    }

    Context 'Standard WSL paths' {
        It 'Detects ext4.vhdx under the WSL package store layout' {
            $packagesRoot = 'C:\MockAppData\Local\Packages'
            $packageVhdx = Join-Path $packagesRoot 'CanonicalGroupLimited.Ubuntu_79abcdef\LocalState\ext4.vhdx'

            Register-MockFileSystem -Files @{
                $packageVhdx = New-MockVhdxItem -FullName $packageVhdx -Length 2147483648
            } -Directories @{
                $packagesRoot = New-MockDirectoryItem -FullName $packagesRoot
            }

            $results = Find-WSLVHDFiles -SearchPaths @($packagesRoot) -SkipRegistrySearch -SkipDockerSearch

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $packageVhdx
            $results[0].Source | Should -Be 'Standard path'
            $results[0].SizeGB | Should -Be 2
        }

        It 'Detects ext4.vhdx under the LOCALAPPDATA\wsl fallback path' {
            $wslRoot = 'C:\MockAppData\Local\wsl'
            $wslVhdx = Join-Path $wslRoot '12345678-1234-1234-1234-123456789012\ext4.vhdx'

            Register-MockFileSystem -Files @{
                $wslVhdx = New-MockVhdxItem -FullName $wslVhdx
            } -Directories @{
                $wslRoot = New-MockDirectoryItem -FullName $wslRoot
            }

            $results = Find-WSLVHDFiles -SearchPaths @($wslRoot) -SkipRegistrySearch -SkipDockerSearch

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $wslVhdx
            $results[0].Source | Should -Be 'Standard path'
        }
    }

    Context 'Docker Desktop paths' {
        It 'Detects ext4.vhdx from a known Docker Desktop layout target' {
            $dockerVhdx = 'C:\MockAppData\Local\Docker\wsl\disk\ext4.vhdx'
            $dockerTarget = [PSCustomObject]@{
                Path = $dockerVhdx
                Label = 'Docker Desktop unified disk image'
                Layout = 'disk\ext4.vhdx'
                IsCustomRoot = $false
            }

            Register-MockFileSystem -Files @{
                $dockerVhdx = New-MockVhdxItem -FullName $dockerVhdx -Length 3221225472
            } -Directories @{
                'C:\MockAppData\Local\Docker\wsl\disk' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl\disk'
                'C:\MockAppData\Local\Docker\wsl' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl'
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch -SearchPaths @() -DockerSearchTargets @($dockerTarget) -LocalAppDataRoot 'C:\MockAppData\Local'

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $dockerVhdx
            $results[0].Source | Should -Be 'Docker Desktop'
            $results[0].DockerLabel | Should -Be 'Docker Desktop unified disk image'
            $results[0].SizeGB | Should -Be 3
            ($script:LastDockerSearchResults | Where-Object { $_.Status -eq 'Detected' }).Count | Should -Be 1
        }

        It 'Detects legacy docker_data.vhdx from Docker Desktop targets' {
            $dockerDataVhdx = 'C:\MockAppData\Local\Docker\wsl\disk\docker_data.vhdx'
            $dockerTarget = [PSCustomObject]@{
                Path = $dockerDataVhdx
                Label = 'Legacy Docker data disk'
                Layout = 'disk\docker_data.vhdx'
                IsCustomRoot = $false
            }

            Register-MockFileSystem -Files @{
                $dockerDataVhdx = New-MockVhdxItem -FullName $dockerDataVhdx -Length 5368709120
            } -Directories @{
                'C:\MockAppData\Local\Docker\wsl\disk' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl\disk'
                'C:\MockAppData\Local\Docker\wsl' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl'
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch -SearchPaths @() -DockerSearchTargets @($dockerTarget) -LocalAppDataRoot 'C:\MockAppData\Local'

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $dockerDataVhdx
            $results[0].Source | Should -Be 'Docker Desktop'
        }

        It 'Records missing Docker layout paths when the parent directory exists' {
            $missingDockerVhdx = 'C:\MockAppData\Local\Docker\wsl\main\ext4.vhdx'
            $dockerTarget = [PSCustomObject]@{
                Path = $missingDockerVhdx
                Label = 'Docker Desktop engine VM'
                Layout = 'main\ext4.vhdx'
                IsCustomRoot = $false
            }

            Register-MockFileSystem -Directories @{
                'C:\MockAppData\Local\Docker\wsl\main' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl\main'
                'C:\MockAppData\Local\Docker\wsl' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl'
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch -SearchPaths @() -DockerSearchTargets @($dockerTarget) -LocalAppDataRoot 'C:\MockAppData\Local'

            $results.Count | Should -Be 0
            ($script:LastDockerSearchResults | Where-Object { $_.Status -eq 'NotFound' -and $_.Path -eq $missingDockerVhdx }).Count | Should -Be 1
        }

        It 'Skips unsupported Docker layouts when the parent directory is absent' {
            $missingLayoutVhdx = 'C:\MockAppData\Local\Docker\wsl\distro\ext4.vhdx'
            $dockerTarget = [PSCustomObject]@{
                Path = $missingLayoutVhdx
                Label = 'Legacy docker-desktop engine store'
                Layout = 'distro\ext4.vhdx'
                IsCustomRoot = $false
            }

            Register-MockFileSystem -Directories @{
                'C:\MockAppData\Local\Docker\wsl' = New-MockDirectoryItem -FullName 'C:\MockAppData\Local\Docker\wsl'
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch -SearchPaths @() -DockerSearchTargets @($dockerTarget) -LocalAppDataRoot 'C:\MockAppData\Local'

            $results.Count | Should -Be 0
            ($script:LastDockerSearchResults | Where-Object { $_.Status -eq 'MissingLayout' -and $_.Path -eq $missingLayoutVhdx }).Count | Should -Be 1
        }

        It 'Detects Docker VHDX files inside a custom Docker Desktop storage root' {
            $customRoot = 'D:\DockerStorage\DockerDesktopWSL'
            $customVhdx = Join-Path $customRoot 'disk\ext4.vhdx'
            $dockerTarget = [PSCustomObject]@{
                Path = $customRoot
                Label = 'Docker Desktop customWslDistroDir from settings.json'
                Layout = 'custom root'
                IsCustomRoot = $true
            }

            Register-MockFileSystem -Files @{
                $customVhdx = New-MockVhdxItem -FullName $customVhdx
            } -Directories @{
                $customRoot = New-MockDirectoryItem -FullName $customRoot
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch -SearchPaths @() -DockerSearchTargets @($dockerTarget) -LocalAppDataRoot 'C:\MockAppData\Local'

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $customVhdx
            $results[0].DockerLabel | Should -Be 'Docker Desktop customWslDistroDir from settings.json'
        }
    }

    Context 'WSL registry paths' {
        It 'Detects a registered distribution VHDX from registry BasePath and default filename' {
            $registryRoot = 'TestDrive:\Lxss'
            $basePath = 'C:\MockUsers\user\AppData\Local\Packages\Ubuntu'
            $registeredVhdx = Join-Path $basePath 'ext4.vhdx'
            $registryEntry = New-MockRegistryDistribution -KeyName '{11111111-1111-1111-1111-111111111111}' -BasePath $basePath -DistributionName 'Ubuntu'

            Register-MockFileSystem -Files @{
                $registeredVhdx = New-MockVhdxItem -FullName $registeredVhdx
            } -Directories @{
                $registryRoot = New-MockDirectoryItem -FullName $registryRoot
            } -RegistryEntries @{
                $registryRoot = @($registryEntry)
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch:$false -SkipDockerSearch -RegistryRoot $registryRoot -SearchPaths @()

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $registeredVhdx
            $results[0].Source | Should -Be 'WSL registry'
            $results[0].Distribution | Should -Be 'Ubuntu'
        }

        It 'Detects a registered distribution VHDX when VhdFileName is an absolute path' {
            $registryRoot = 'TestDrive:\Lxss'
            $customVhdx = 'D:\CustomWSL\custom-disk.vhdx'
            $registryEntry = New-MockRegistryDistribution -KeyName '{22222222-2222-2222-2222-222222222222}' -BasePath 'C:\Ignored\BasePath' -DistributionName 'CustomUbuntu' -VhdFileName $customVhdx

            Register-MockFileSystem -Files @{
                $customVhdx = New-MockVhdxItem -FullName $customVhdx
            } -Directories @{
                $registryRoot = New-MockDirectoryItem -FullName $registryRoot
            } -RegistryEntries @{
                $registryRoot = @($registryEntry)
            }

            $results = Find-WSLVHDFiles -SkipRegistrySearch:$false -SkipDockerSearch -RegistryRoot $registryRoot -SearchPaths @()

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $customVhdx
            $results[0].Distribution | Should -Be 'CustomUbuntu'
        }
    }

    Context 'Custom and unsupported paths' {
        It 'Detects an explicit VHDX file path passed through -ExplicitPaths' {
            $customVhdx = 'E:\Backups\custom\ext4.vhdx'

            Register-MockFileSystem -Files @{
                $customVhdx = New-MockVhdxItem -FullName $customVhdx
            }

            $results = Find-WSLVHDFiles -ExplicitPaths @($customVhdx) -SkipRegistrySearch -SkipDockerSearch -SearchPaths @()

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $customVhdx
            $results[0].Source | Should -Be 'Explicit path'
        }

        It 'Detects ext4.vhdx files inside an explicit directory path' {
            $customRoot = 'E:\CustomWSL'
            $customVhdx = Join-Path $customRoot 'ext4.vhdx'

            Register-MockFileSystem -Files @{
                $customVhdx = New-MockVhdxItem -FullName $customVhdx
            } -Directories @{
                $customRoot = New-MockDirectoryItem -FullName $customRoot
            }

            $results = Find-WSLVHDFiles -ExplicitPaths @($customRoot) -SkipRegistrySearch -SkipDockerSearch -SearchPaths @()

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $customVhdx
            $results[0].Source | Should -Be 'Explicit path'
        }

        It 'Skips non-VHDX files and missing explicit paths without failing' {
            $unsupportedFile = 'Z:\Unsupported\data.vhd'
            $missingPath = 'Z:\Missing\ext4.vhdx'

            Register-MockFileSystem -Files @{
                $unsupportedFile = [PSCustomObject]@{
                    FullName = $unsupportedFile
                    PSIsContainer = $false
                    Extension = '.vhd'
                    Length = 1073741824
                    LastWriteTime = [datetime]'2026-01-01T00:00:00'
                    Directory = [PSCustomObject]@{ Name = 'Unsupported' }
                }
            }

            $results = Find-WSLVHDFiles -ExplicitPaths @($unsupportedFile, $missingPath) -SkipRegistrySearch -SkipDockerSearch -SearchPaths @('Z:\NotPresent')

            $results.Count | Should -Be 0
            ($script:LastVHDSearchLocations -contains "Explicit path - $unsupportedFile") | Should -BeTrue
            ($script:LastVHDSearchLocations -contains "Explicit path - $missingPath") | Should -BeTrue
        }

        It 'Does not search unsupported network-drive locations unless explicitly provided' {
            $networkRoot = '\\server\share\wsl'
            $networkVhdx = Join-Path $networkRoot 'ext4.vhdx'

            Register-MockFileSystem -Files @{
                $networkVhdx = New-MockVhdxItem -FullName $networkVhdx
            } -Directories @{
                $networkRoot = New-MockDirectoryItem -FullName $networkRoot
            }

            $defaultResults = Find-WSLVHDFiles -SkipRegistrySearch -SkipDockerSearch -SearchPaths @('C:\MockAppData\Local\wsl')
            $explicitResults = Find-WSLVHDFiles -ExplicitPaths @($networkVhdx) -SkipRegistrySearch -SkipDockerSearch -SearchPaths @()

            $defaultResults.Count | Should -Be 0
            $explicitResults.Count | Should -Be 1
            $explicitResults[0].Path | Should -Be $networkVhdx
        }

        It 'Deduplicates the same VHDX discovered from multiple sources' {
            $sharedVhdx = 'C:\Shared\ext4.vhdx'
            $registryRoot = 'TestDrive:\Lxss'
            $registryEntry = New-MockRegistryDistribution -KeyName '{33333333-3333-3333-3333-333333333333}' -BasePath 'C:\Shared' -DistributionName 'SharedUbuntu'

            Register-MockFileSystem -Files @{
                $sharedVhdx = New-MockVhdxItem -FullName $sharedVhdx
            } -Directories @{
                $registryRoot = New-MockDirectoryItem -FullName $registryRoot
            } -RegistryEntries @{
                $registryRoot = @($registryEntry)
            }

            $results = Find-WSLVHDFiles -ExplicitPaths @($sharedVhdx) -SkipRegistrySearch:$false -SkipDockerSearch -RegistryRoot $registryRoot -SearchPaths @()

            $results.Count | Should -Be 1
            $results[0].Path | Should -Be $sharedVhdx
        }
    }
}
