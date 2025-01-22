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
    Describe "Get-WimImageUpdate" {
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

            # Mock Get-WindowsPackage
            Mock Get-WindowsPackage {
                @(
                    @{
                        PackageName = "Security Update KB123456"
                        Description = "Security Update"
                        Version = "1.0.0.0"
                        InstallTime = (Get-Date)
                        ReleaseType = "Security Update"
                        ProductName = "Windows"
                        ProductVersion = "10.0"
                        Company = "Microsoft"
                        InstallPackageName = "update.msu"
                        SupportInformation = "http://support.microsoft.com"
                        PackageState = "Installed"
                    },
                    @{
                        PackageName = "Critical Update KB789012"
                        Description = "Critical Update"
                        Version = "1.0.0.0"
                        InstallTime = (Get-Date)
                        ReleaseType = "Critical Update"
                        ProductName = "Windows"
                        ProductVersion = "10.0"
                        Company = "Microsoft"
                        InstallPackageName = "update.msu"
                        SupportInformation = "http://support.microsoft.com"
                        PackageState = "Installed"
                    }
                )
            }
        }

        Context "Parameter validation" {
            It "Should throw when image path doesn't exist" {
                Mock Test-Path { $false }
                { Get-WimImageUpdate -ImagePath "NonExistent.wim" -Index 1 } |
                    Should -Throw "Image file not found"
            }

            It "Should throw when mount path doesn't exist" {
                Mock Test-Path { $false }
                { Get-WimImageUpdate -MountPath "NonExistent" } |
                    Should -Throw "Mount path not found"
            }

            It "Should throw when file is not a .wim" {
                Mock Test-Path { $true }
                { Get-WimImageUpdate -ImagePath "test.txt" -Index 1 } |
                    Should -Throw "must be a .wim file"
            }

            It "Should throw when index is out of range" {
                { Get-WimImageUpdate -ImagePath "test.wim" -Index 0 } |
                    Should -Throw
                { Get-WimImageUpdate -ImagePath "test.wim" -Index 100 } |
                    Should -Throw
            }
        }

        Context "Update retrieval from mounted image" {
            It "Should return all updates by default" {
                $result = Get-WimImageUpdate -MountPath "TestDrive:\mount"
                $result.Count | Should -Be 2
            }

            It "Should filter security updates" {
                $result = Get-WimImageUpdate -MountPath "TestDrive:\mount" -UpdateType Security
                $result.Count | Should -Be 1
                $result[0].Name | Should -BeLike "*KB123456*"
            }

            It "Should return detailed information when requested" {
                $result = Get-WimImageUpdate -MountPath "TestDrive:\mount" -Detailed
                $result[0].Description | Should -Not -BeNullOrEmpty
                $result[0].Company | Should -Not -BeNullOrEmpty
                $result[0].Support | Should -Not -BeNullOrEmpty
            }
        }

        Context "Update retrieval from .wim file" {
            It "Should mount and dismount image automatically" {
                Get-WimImageUpdate -ImagePath "TestDrive:\test.wim" -Index 1
                Should -Invoke Mount-WindowsImage -Times 1
                Should -Invoke Dismount-WindowsImage -Times 1
            }

            It "Should cleanup temporary mount point" {
                Get-WimImageUpdate -ImagePath "TestDrive:\test.wim" -Index 1
                Should -Invoke Remove-Item -Times 1
            }
        }

        Context "Error handling" {
            It "Should handle Get-WindowsPackage errors" {
                Mock Get-WindowsPackage { throw "Access denied" }
                { Get-WimImageUpdate -MountPath "TestDrive:\mount" } |
                    Should -Throw "Failed to get update information"
            }

            It "Should cleanup on error" {
                Mock Get-WindowsPackage { throw "Error" }
                { Get-WimImageUpdate -ImagePath "TestDrive:\test.wim" -Index 1 } |
                    Should -Throw
                Should -Invoke Dismount-WindowsImage -Times 1
                Should -Invoke Remove-Item -Times 1
            }
        }
    }
}
