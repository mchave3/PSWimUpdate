$here = (Split-Path -Parent $MyInvocation.MyCommand.Path).Replace((Join-Path "Tests" Public), (Join-Path PSWimUpdate Public))
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

. (Join-Path $here $sut)

# To make test runable from project root, and from test directory itself. Do quick validation.
$testsPath = Join-Path "Tests" "Public"
if ((Get-Location).Path -match [Regex]::Escape($testsPath)) {
    $psmPath = (Resolve-Path "..\..\PSWimUpdate\PSWimUpdate.psm1").Path    
} else {
    $psmPath = (Resolve-Path ".\PSWimUpdate\PSWimUpdate.psm1").Path
}

Import-Module $psmPath -Force -NoClobber

InModuleScope "PSWimUpdate" {
    Describe "Get-WimImageInfo" {
        BeforeAll {
            # Mock Test-Path
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "TestDrive:\test.wim" }
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "TestDrive:\mount" -and $PathType -eq "Container" }
            
            # Mock Get-WindowsImage for .wim file
            Mock Get-WindowsImage -ParameterFilter { $ImagePath } {
                @(
                    @{
                        ImagePath = "TestDrive:\test.wim"
                        ImageIndex = 1
                        ImageName = "Windows 10 Pro"
                        ImageDescription = "Windows 10 Pro x64"
                        ImageSize = 20GB
                    },
                    @{
                        ImagePath = "TestDrive:\test.wim"
                        ImageIndex = 2
                        ImageName = "Windows 10 Enterprise"
                        ImageDescription = "Windows 10 Enterprise x64"
                        ImageSize = 25GB
                    }
                )
            }

            # Mock Get-WindowsImage for mounted images
            Mock Get-WindowsImage -ParameterFilter { $Mounted } {
                @(
                    @{
                        ImagePath = "TestDrive:\test.wim"
                        Path = "TestDrive:\mount"
                        ImageIndex = 1
                        ImageName = "Windows 10 Pro"
                        ImageDescription = "Windows 10 Pro x64"
                        ImageSize = 20GB
                    }
                )
            }
        }

        Context "Parameter validation" {
            It "Should throw when path doesn't exist" {
                Mock Test-Path { $false }
                { Get-WimImageInfo -Path "NonExistent.wim" } |
                    Should -Throw "Path not found"
            }

            It "Should throw when path is not a .wim file or directory" {
                Mock Test-Path { $true }
                { Get-WimImageInfo -Path "test.txt" } |
                    Should -Throw "Path must be either a .wim file or a directory"
            }

            It "Should throw when index is out of range" {
                { Get-WimImageInfo -Path "TestDrive:\test.wim" -Index 0 } |
                    Should -Throw
                { Get-WimImageInfo -Path "TestDrive:\test.wim" -Index 100 } |
                    Should -Throw
            }
        }

        Context "Getting image information" {
            It "Should return all images from a .wim file" {
                $result = Get-WimImageInfo -Path "TestDrive:\test.wim"
                $result.Count | Should -Be 2
                $result[0].Index | Should -Be 1
                $result[1].Index | Should -Be 2
            }

            It "Should return specific index from a .wim file" {
                $result = Get-WimImageInfo -Path "TestDrive:\test.wim" -Index 1
                $result.Count | Should -Be 1
                $result.Index | Should -Be 1
                $result.Name | Should -Be "Windows 10 Pro"
            }

            It "Should return mounted images when -Mounted is specified" {
                $result = Get-WimImageInfo -Mounted
                $result.Count | Should -Be 1
                $result.IsMounted | Should -Be $true
                $result.MountPath | Should -Be "TestDrive:\mount"
            }

            It "Should return mounted images for specific mount path" {
                $result = Get-WimImageInfo -Path "TestDrive:\mount"
                $result.Count | Should -Be 1
                $result.IsMounted | Should -Be $true
                $result.MountPath | Should -Be "TestDrive:\mount"
            }
        }

        Context "Error handling" {
            It "Should handle Get-WindowsImage errors" {
                Mock Get-WindowsImage { throw "Access denied" }
                { Get-WimImageInfo -Path "TestDrive:\test.wim" } |
                    Should -Throw "Failed to get image information"
            }
        }
    }
}
