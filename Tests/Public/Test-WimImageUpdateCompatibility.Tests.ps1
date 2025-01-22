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
    Describe "Test-WimImageUpdateCompatibility" {
        BeforeAll {
            # Mock Test-Path
            Mock Test-Path { $true }

            # Mock New-Item for temp directory
            Mock New-Item { }

            # Mock Mount-WindowsImage
            Mock Mount-WindowsImage { }

            # Mock Dismount-WindowsImage
            Mock Dismount-WindowsImage { }

            # Mock Remove-Item
            Mock Remove-Item { }

            # Mock Get-WindowsPackage for installed updates
            Mock Get-WindowsPackage -ParameterFilter { $Path -like "TestDrive:\mount*" } {
                @(
                    @{
                        PackageName = "Package_for_KB123456"
                        PackageState = "Installed"
                        SupersededPackages = @("Package_for_KB111111")
                    },
                    @{
                        PackageName = "Package_for_KB789012"
                        PackageState = "Installed"
                        SupersededPackages = @()
                    }
                )
            }

            # Mock Get-WindowsPackage for .msu file info
            Mock Get-WindowsPackage -ParameterFilter { $Path -like "*.msu" } {
                @{
                    PackageName = "Update_KB999999"
                    Applicable = $true
                    Dependencies = @(
                        @{ Name = "Package_for_KB123456" }
                    )
                    ReleaseType = "Security Update"
                }
            }

            # Create test update objects
            $testUpdates = @(
                @{
                    KB = "999999"
                    Title = "Security Update KB999999"
                    Classification = "Security"
                },
                @{
                    KB = "111111"
                    Title = "Critical Update KB111111"
                    Classification = "Critical"
                }
            )
        }

        Context "Parameter validation" {
            It "Should throw when image path doesn't exist" {
                Mock Test-Path { $false }
                { Test-WimImageUpdateCompatibility -ImagePath "NonExistent.wim" -Index 1 -Update $testUpdates[0] } |
                    Should -Throw "Image file not found"
            }

            It "Should throw when mount path doesn't exist" {
                Mock Test-Path { $false }
                { Test-WimImageUpdateCompatibility -MountPath "NonExistent" -Update $testUpdates[0] } |
                    Should -Throw "Mount path not found"
            }

            It "Should throw when file is not a .wim" {
                Mock Test-Path { $true }
                { Test-WimImageUpdateCompatibility -ImagePath "test.txt" -Index 1 -Update $testUpdates[0] } |
                    Should -Throw "must be a .wim file"
            }

            It "Should throw when Update is null" {
                { Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update $null } |
                    Should -Throw
            }
        }

        Context "Update compatibility checking" {
            It "Should handle update objects from Find-WimImageUpdate" {
                $result = Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update $testUpdates[0]
                $result.KB | Should -Be "999999"
                $result.IsCompatible | Should -BeTrue
            }

            It "Should handle .msu file paths" {
                $result = Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update "TestDrive:\updates\KB999999.msu"
                $result.KB | Should -Be "KB999999"
            }

            It "Should detect superseded updates" {
                $result = Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update $testUpdates[1] -Detailed
                $result.IsCompatible | Should -BeFalse
                $result.Conflicts | Should -Not -BeNullOrEmpty
            }

            It "Should return detailed information when requested" {
                $result = Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update $testUpdates[0] -Detailed
                $result.MissingDependencies | Should -Not -BeNullOrEmpty
                $result.ReleaseType | Should -Not -BeNullOrEmpty
                $result.AlreadyInstalled | Should -Not -BeNullOrEmpty
            }
        }

        Context "Image handling" {
            It "Should mount and dismount image when using ImagePath" {
                Test-WimImageUpdateCompatibility -ImagePath "TestDrive:\test.wim" -Index 1 -Update $testUpdates[0]
                Should -Invoke Mount-WindowsImage -Times 1
                Should -Invoke Dismount-WindowsImage -Times 1
            }

            It "Should cleanup temporary mount point" {
                Test-WimImageUpdateCompatibility -ImagePath "TestDrive:\test.wim" -Index 1 -Update $testUpdates[0]
                Should -Invoke Remove-Item -Times 1
            }
        }

        Context "Error handling" {
            It "Should handle Get-WindowsPackage errors" {
                Mock Get-WindowsPackage { throw "Access denied" }
                { Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update $testUpdates[0] } |
                    Should -Throw "Failed to test update compatibility"
            }

            It "Should cleanup on error" {
                Mock Get-WindowsPackage { throw "Error" }
                { Test-WimImageUpdateCompatibility -ImagePath "TestDrive:\test.wim" -Index 1 -Update $testUpdates[0] } |
                    Should -Throw
                Should -Invoke Dismount-WindowsImage -Times 1
                Should -Invoke Remove-Item -Times 1
            }

            It "Should continue on single update failure" {
                Mock Get-WindowsPackage -ParameterFilter { $Path -like "*.msu" } {
                    if ($Path -like "*KB111111*") { throw "Error" }
                    return @{
                        PackageName = "Update_KB999999"
                        Applicable = $true
                        Dependencies = @()
                        ReleaseType = "Security Update"
                    }
                }

                $result = Test-WimImageUpdateCompatibility -MountPath "TestDrive:\mount" -Update $testUpdates
                $result.Count | Should -Be 1
            }
        }
    }
}
