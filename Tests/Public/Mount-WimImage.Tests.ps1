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
    Describe "Mount-WimImage" {
        BeforeAll {
            # Mock Test-Path to simulate file existence checks
            Mock Test-Path {
                param($Path)
                return $Path -eq "TestDrive:\test.wim"
            } -ParameterFilter { $Path -match "\.wim$" }

            # Mock New-Item for mount directory creation
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }

            # Mock Get-ChildItem for empty directory check
            Mock Get-ChildItem { @() }

            # Mock Mount-WindowsImage
            Mock Mount-WindowsImage { }

            # Mock Get-WindowsImage for mount verification
            Mock Get-WindowsImage {
                @(
                    @{
                        Path = "TestDrive:\mount"
                        ImagePath = "TestDrive:\test.wim"
                        Index = 1
                    }
                )
            }
        }

        Context "Parameter validation" {
            It "Should throw when ImagePath is invalid" {
                { Mount-WimImage -ImagePath "invalid.txt" -MountPath "TestDrive:\mount" } |
                    Should -Throw "The file specified must be a .wim file"
            }

            It "Should throw when ImagePath doesn't exist" {
                { Mount-WimImage -ImagePath "nonexistent.wim" -MountPath "TestDrive:\mount" } |
                    Should -Throw "Image file not found"
            }

            It "Should throw when Index is out of range" {
                { Mount-WimImage -ImagePath "TestDrive:\test.wim" -MountPath "TestDrive:\mount" -Index 0 } |
                    Should -Throw
                { Mount-WimImage -ImagePath "TestDrive:\test.wim" -MountPath "TestDrive:\mount" -Index 100 } |
                    Should -Throw
            }
        }

        Context "Successful mounting" {
            It "Should create mount directory if it doesn't exist" {
                Mount-WimImage -ImagePath "TestDrive:\test.wim" -MountPath "TestDrive:\mount"
                Should -Invoke New-Item -ParameterFilter {
                    $Path -eq "TestDrive:\mount" -and $ItemType -eq "Directory"
                }
            }

            It "Should mount the image successfully" {
                Mount-WimImage -ImagePath "TestDrive:\test.wim" -MountPath "TestDrive:\mount"
                Should -Invoke Mount-WindowsImage -ParameterFilter {
                    $ImagePath -eq "TestDrive:\test.wim" -and
                    $Path -eq "TestDrive:\mount" -and
                    $Index -eq 1
                }
            }

            It "Should verify the mount was successful" {
                Mount-WimImage -ImagePath "TestDrive:\test.wim" -MountPath "TestDrive:\mount"
                Should -Invoke Get-WindowsImage
            }
        }
    }
}
