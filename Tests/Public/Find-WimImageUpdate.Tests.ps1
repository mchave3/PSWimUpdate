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
    Describe "Find-WimImageUpdate" {
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

            # Mock Get-WindowsImage for image info
            Mock Get-WindowsImage {
                @{
                    Version = "10.0.19041.1"
                    Architecture = "amd64"
                    EditionId = "Professional"
                    InstallationType = "Client"
                }
            }

            # Mock Get-WindowsPackage for installed updates
            Mock Get-WindowsPackage {
                @(
                    @{
                        PackageName = "Package_for_KB123456"
                        PackageState = "Installed"
                    }
                )
            }

            # Mock Get-Module for PSWindowsUpdate availability
            Mock Get-Module { $false }

            # Mock Invoke-RestMethod for update catalog query
            Mock Invoke-RestMethod {
                @(
                    @{
                        Identity = "Update1"
                        KBNumber = "KB789012"
                        Title = "Security Update"
                        Description = "Test Update 1"
                        Classification = "Security"
                        ReleaseDate = (Get-Date)
                        Size = 1024
                        DownloadUrl = "http://test.com/update1"
                        IsSuperseded = $false
                        RequiresReboot = $true
                    },
                    @{
                        Identity = "Update2"
                        KBNumber = "KB345678"
                        Title = "Critical Update"
                        Description = "Test Update 2"
                        Classification = "Critical"
                        ReleaseDate = (Get-Date)
                        Size = 2048
                        DownloadUrl = "http://test.com/update2"
                        IsSuperseded = $false
                        RequiresReboot = $false
                    }
                )
            }
        }

        Context "Parameter validation" {
            It "Should throw when image path doesn't exist" {
                Mock Test-Path { $false }
                { Find-WimImageUpdate -ImagePath "NonExistent.wim" -Index 1 } |
                    Should -Throw "Image file not found"
            }

            It "Should throw when mount path doesn't exist" {
                Mock Test-Path { $false }
                { Find-WimImageUpdate -MountPath "NonExistent" } |
                    Should -Throw "Mount path not found"
            }

            It "Should throw when file is not a .wim" {
                Mock Test-Path { $true }
                { Find-WimImageUpdate -ImagePath "test.txt" -Index 1 } |
                    Should -Throw "must be a .wim file"
            }

            It "Should throw when MaxResults is out of range" {
                { Find-WimImageUpdate -MountPath "TestDrive:\mount" -MaxResults 0 } |
                    Should -Throw
                { Find-WimImageUpdate -MountPath "TestDrive:\mount" -MaxResults 1001 } |
                    Should -Throw
            }
        }

        Context "Update search functionality" {
            It "Should return available updates" {
                $result = Find-WimImageUpdate -MountPath "TestDrive:\mount"
                $result.Count | Should -Be 2
                $result[0].KB | Should -Be "KB789012"
            }

            It "Should respect MaxResults parameter" {
                $result = Find-WimImageUpdate -MountPath "TestDrive:\mount" -MaxResults 1
                $result.Count | Should -Be 1
            }

            It "Should exclude installed updates when specified" {
                Mock Get-WindowsPackage {
                    @(
                        @{
                            PackageName = "Package_for_KB789012"
                            PackageState = "Installed"
                        }
                    )
                }
                
                $result = Find-WimImageUpdate -MountPath "TestDrive:\mount" -ExcludeInstalled
                $result.Count | Should -Be 1
                $result[0].KB | Should -Not -Be "KB789012"
            }
        }

        Context "Image handling" {
            It "Should mount and dismount image when using ImagePath" {
                Find-WimImageUpdate -ImagePath "TestDrive:\test.wim" -Index 1
                Should -Invoke Mount-WindowsImage -Times 1
                Should -Invoke Dismount-WindowsImage -Times 1
            }

            It "Should cleanup temporary mount point" {
                Find-WimImageUpdate -ImagePath "TestDrive:\test.wim" -Index 1
                Should -Invoke Remove-Item -Times 1
            }
        }

        Context "Error handling" {
            It "Should handle Get-WindowsImage errors" {
                Mock Get-WindowsImage { throw "Access denied" }
                { Find-WimImageUpdate -MountPath "TestDrive:\mount" } |
                    Should -Throw "Failed to get image information"
            }

            It "Should handle update catalog query errors" {
                Mock Invoke-RestMethod { throw "Network error" }
                $result = Find-WimImageUpdate -MountPath "TestDrive:\mount"
                $result | Should -BeNullOrEmpty
            }

            It "Should cleanup on error" {
                Mock Get-WindowsImage { throw "Error" }
                { Find-WimImageUpdate -ImagePath "TestDrive:\test.wim" -Index 1 } |
                    Should -Throw
                Should -Invoke Dismount-WindowsImage -Times 1
                Should -Invoke Remove-Item -Times 1
            }
        }
    }
}
