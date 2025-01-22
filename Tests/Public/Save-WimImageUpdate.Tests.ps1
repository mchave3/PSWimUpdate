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
    Describe "Save-WimImageUpdate" {
        BeforeAll {
            # Create test directory
            $testPath = "TestDrive:\Updates"
            New-Item -Path $testPath -ItemType Directory -Force

            # Mock Test-Path
            Mock Test-Path { $true } -ParameterFilter { $Path -eq $testPath }
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*.msu" }

            # Mock New-Item
            Mock New-Item { }

            # Mock Remove-Item
            Mock Remove-Item { }

            # Mock Get-Item for file size verification
            Mock Get-Item {
                @{
                    Length = 1024 * 1024  # 1MB
                }
            }

            # Create test update objects
            $testUpdates = @(
                @{
                    KB = "123456"
                    Title = "Security Update KB123456"
                    DownloadUrl = "http://test.com/KB123456.msu"
                    Size = 1024 * 1024  # 1MB
                },
                @{
                    KB = "789012"
                    Title = "Critical Update KB789012"
                    DownloadUrl = "http://test.com/KB789012.msu"
                    Size = 2048 * 1024  # 2MB
                }
            )

            # Mock WebClient
            $mockWebClient = @{
                Headers = @{}
                DownloadFile = { 
                    param($url, $file)
                    New-Item -Path $file -ItemType File -Force
                }
                Dispose = { }
            }

            # Mock New-Object for WebClient
            Mock New-Object -ParameterFilter { $TypeName -eq "System.Net.WebClient" } {
                $mockWebClient
            }
        }

        Context "Parameter validation" {
            It "Should create target directory if it doesn't exist" {
                Mock Test-Path { $false }
                Save-WimImageUpdate -Update $testUpdates[0] -Path $testPath
                Should -Invoke New-Item -ParameterFilter {
                    $Path -eq $testPath -and $ItemType -eq "Directory"
                }
            }

            It "Should throw when Update is null" {
                { Save-WimImageUpdate -Update $null } |
                    Should -Throw
            }
        }

        Context "Download functionality" {
            It "Should download single update" {
                $result = Save-WimImageUpdate -Update $testUpdates[0] -Path $testPath
                $result.Count | Should -Be 1
                $result.KB | Should -Be "123456"
            }

            It "Should download multiple updates" {
                $result = Save-WimImageUpdate -Update $testUpdates -Path $testPath
                $result.Count | Should -Be 2
            }

            It "Should skip existing files without Force" {
                Mock Test-Path { $true } -ParameterFilter { $Path -like "*.msu" }
                $result = Save-WimImageUpdate -Update $testUpdates[0] -Path $testPath
                Should -Not -Invoke Remove-Item
            }

            It "Should overwrite existing files with Force" {
                Mock Test-Path { $true } -ParameterFilter { $Path -like "*.msu" }
                $result = Save-WimImageUpdate -Update $testUpdates[0] -Path $testPath -Force
                Should -Invoke Remove-Item
            }
        }

        Context "File validation" {
            It "Should verify downloaded file size" {
                Mock Get-Item {
                    @{
                        Length = 1024  # Wrong size
                    }
                }
                $result = Save-WimImageUpdate -Update $testUpdates[0] -Path $testPath
                Should -Invoke Remove-Item
                $result | Should -BeNullOrEmpty
            }

            It "Should cleanup failed downloads" {
                Mock New-Object { throw "Download failed" }
                Save-WimImageUpdate -Update $testUpdates[0] -Path $testPath
                Should -Invoke Remove-Item
            }
        }

        Context "Error handling" {
            It "Should handle WebClient errors" {
                Mock New-Object { throw "Network error" }
                $result = Save-WimImageUpdate -Update $testUpdates -Path $testPath
                $result | Should -BeNullOrEmpty
            }

            It "Should continue on single update failure" {
                $updates = @(
                    $testUpdates[0],
                    @{
                        KB = "ERROR"
                        Title = "Error Update"
                        DownloadUrl = "invalid://url"
                        Size = 1024
                    },
                    $testUpdates[1]
                )

                Mock New-Object -ParameterFilter { $TypeName -eq "System.Net.WebClient" } {
                    if ($updates[$script:currentUpdate].KB -eq "ERROR") {
                        throw "Download failed"
                    }
                    $mockWebClient
                }

                $result = Save-WimImageUpdate -Update $updates -Path $testPath
                $result.Count | Should -Be 2
            }
        }
    }
}
