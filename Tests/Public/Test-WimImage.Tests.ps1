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
    Describe "Test-WimImage" {
        BeforeAll {
            # Mock Test-Path
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "TestDrive:\test.wim" }
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "TestDrive:\mount" }

            # Mock Get-WindowsImage for basic image info
            Mock Get-WindowsImage -ParameterFilter { $ImagePath -and -not $Verify } {
                @(
                    @{
                        ImagePath = "TestDrive:\test.wim"
                        ImageIndex = 1
                        ImageName = "Windows 10 Pro"
                    },
                    @{
                        ImagePath = "TestDrive:\test.wim"
                        ImageIndex = 2
                        ImageName = "Windows 10 Enterprise"
                    }
                )
            }

            # Mock Get-WindowsImage for verification
            Mock Get-WindowsImage -ParameterFilter { $Verify } { $null }

            # Mock Get-WindowsImage for mounted images
            Mock Get-WindowsImage -ParameterFilter { $Mounted } {
                @(
                    @{
                        ImagePath = "TestDrive:\test.wim"
                        Path = "TestDrive:\mount"
                        ImageIndex = 1
                        ImageName = "Windows 10 Pro"
                    }
                )
            }
        }

        Context "Parameter validation" {
            It "Should throw when image path doesn't exist" {
                Mock Test-Path { $false }
                { Test-WimImage -ImagePath "NonExistent.wim" } |
                    Should -Throw "Image file not found"
            }

            It "Should throw when file is not a .wim" {
                Mock Test-Path { $true }
                { Test-WimImage -ImagePath "test.txt" } |
                    Should -Throw "must be a .wim file"
            }

            It "Should throw when index is out of range" {
                { Test-WimImage -ImagePath "TestDrive:\test.wim" -Index 0 } |
                    Should -Throw
                { Test-WimImage -ImagePath "TestDrive:\test.wim" -Index 100 } |
                    Should -Throw
            }
        }

        Context "Basic validation" {
            It "Should return success for valid image" {
                $result = Test-WimImage -ImagePath "TestDrive:\test.wim"
                $result.IsValid | Should -Be $true
                $result.IssueCount | Should -Be 0
            }

            It "Should validate specific index" {
                $result = Test-WimImage -ImagePath "TestDrive:\test.wim" -Index 1
                $result.IsValid | Should -Be $true
            }

            It "Should detect invalid index" {
                Mock Get-WindowsImage -ParameterFilter { $ImagePath -and -not $Verify } {
                    @(
                        @{
                            ImageIndex = 1
                            ImageName = "Windows 10 Pro"
                        }
                    )
                }
                { Test-WimImage -ImagePath "TestDrive:\test.wim" -Index 2 } |
                    Should -Throw "Index 2 not found"
            }
        }

        Context "Detailed validation" {
            It "Should return detailed results when requested" {
                Mock Get-WindowsImage -ParameterFilter { $Verify } { throw "Corruption detected" }
                $result = Test-WimImage -ImagePath "TestDrive:\test.wim" -Detailed
                $result.IsValid | Should -Be $false
                $result.Issues.Count | Should -BeGreaterThan 0
                $result.Details | Should -Not -BeNullOrEmpty
            }

            It "Should check mount state when requested" {
                Mock Test-Path { $false } -ParameterFilter { $Path -eq "TestDrive:\mount" }
                $result = Test-WimImage -ImagePath "TestDrive:\test.wim" -CheckMountState -Detailed
                $result.IsValid | Should -Be $false
                $result.Details[1].Issues | Should -Contain "*Mount path not found*"
            }
        }

        Context "Error handling" {
            It "Should handle Get-WindowsImage errors" {
                Mock Get-WindowsImage -ParameterFilter { $ImagePath -and -not $Verify } { throw "Access denied" }
                $result = Test-WimImage -ImagePath "TestDrive:\test.wim"
                $result.IsValid | Should -Be $false
                $result.IssueCount | Should -BeGreaterThan 0
            }

            It "Should handle verification errors" {
                Mock Get-WindowsImage -ParameterFilter { $Verify } { throw "Verification failed" }
                $result = Test-WimImage -ImagePath "TestDrive:\test.wim" -Detailed
                $result.IsValid | Should -Be $false
                $result.Issues | Should -Contain "*Verification failed*"
            }
        }
    }
}
