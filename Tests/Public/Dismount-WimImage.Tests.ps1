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
    Describe "Dismount-WimImage" {
        BeforeAll {
            # Mock Test-Path for mount path existence check
            Mock Test-Path { $true }

            # Mock Get-WindowsImage for mounted image check
            Mock Get-WindowsImage -ParameterFilter { $Mounted } {
                @(
                    @{
                        Path = "TestDrive:\mount"
                        ImagePath = "TestDrive:\test.wim"
                        Index = 1
                    }
                )
            }

            # Mock Dismount-WindowsImage
            Mock Dismount-WindowsImage { }

            # Mock Get-ChildItem for empty directory check
            Mock Get-ChildItem { @() }

            # Mock Remove-Item for directory cleanup
            Mock Remove-Item { }
        }

        Context "Parameter validation" {
            It "Should throw when mount path doesn't exist" {
                Mock Test-Path { $false }
                { Dismount-WimImage -MountPath "NonExistentPath" } |
                    Should -Throw "Mount path not found"
            }

            It "Should throw when path is not a mounted image" {
                Mock Get-WindowsImage -ParameterFilter { $Mounted } { @() }
                { Dismount-WimImage -MountPath "TestDrive:\mount" } |
                    Should -Throw "No mounted image found"
            }
        }

        Context "Successful dismounting" {
            It "Should dismount without saving changes by default" {
                Dismount-WimImage -MountPath "TestDrive:\mount"
                Should -Invoke Dismount-WindowsImage -ParameterFilter {
                    $Path -eq "TestDrive:\mount" -and
                    $Save -eq $false
                }
            }

            It "Should dismount and save changes when -Save is specified" {
                Dismount-WimImage -MountPath "TestDrive:\mount" -Save
                Should -Invoke Dismount-WindowsImage -ParameterFilter {
                    $Path -eq "TestDrive:\mount" -and
                    $Save -eq $true
                }
            }

            It "Should remove empty mount directory after dismounting" {
                Dismount-WimImage -MountPath "TestDrive:\mount"
                Should -Invoke Remove-Item -ParameterFilter {
                    $Path -eq "TestDrive:\mount"
                }
            }
        }

        Context "Error handling" {
            It "Should throw when dismount fails" {
                Mock Dismount-WindowsImage { throw "Dismount failed" }
                { Dismount-WimImage -MountPath "TestDrive:\mount" } |
                    Should -Throw "Failed to dismount image"
            }

            It "Should verify dismount was successful" {
                Mock Get-WindowsImage -ParameterFilter { $Mounted } {
                    @(
                        @{
                            Path = "TestDrive:\mount"
                        }
                    )
                } -ParameterFilter { -not $First }
                { Dismount-WimImage -MountPath "TestDrive:\mount" } |
                    Should -Throw "Failed to dismount image"
            }
        }
    }
}
