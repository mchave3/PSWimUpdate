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
    Describe "Backup-WimImage" {
        BeforeAll {
            # Mock Test-Path for various scenarios
            Mock Test-Path { $true } -ParameterFilter { $Path -eq "TestDrive:\source\install.wim" }
            Mock Test-Path { $false } -ParameterFilter { $Path -eq "TestDrive:\backup" }
            
            # Mock Get-Item for source image
            Mock Get-Item -ParameterFilter { $Path -eq "TestDrive:\source\install.wim" } {
                @{
                    Directory = @{ FullName = "TestDrive:\source" }
                    BaseName = "install"
                    Length = 1GB
                    FullName = "TestDrive:\source\install.wim"
                }
            }

            # Mock New-Item for creating backup directory
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }

            # Mock Copy-Item for backup creation
            Mock Copy-Item { }

            # Mock Get-ChildItem for backup history
            Mock Get-ChildItem {
                @(
                    @{
                        Name = "install_20250101_120000.wim"
                        FullName = "TestDrive:\backup\install_20250101_120000.wim"
                        CreationTime = (Get-Date).AddDays(-2)
                    },
                    @{
                        Name = "install_20250102_120000.wim"
                        FullName = "TestDrive:\backup\install_20250102_120000.wim"
                        CreationTime = (Get-Date).AddDays(-1)
                    }
                )
            }

            # Mock Remove-Item for cleanup
            Mock Remove-Item { }
        }

        Context "Parameter validation" {
            It "Should throw when image path doesn't exist" {
                Mock Test-Path { $false }
                { Backup-WimImage -ImagePath "NonExistent.wim" } |
                    Should -Throw "Image file not found"
            }

            It "Should throw when file is not a .wim" {
                Mock Test-Path { $true }
                { Backup-WimImage -ImagePath "test.txt" } |
                    Should -Throw "must be a .wim file"
            }

            It "Should throw when MaxBackupCount is out of range" {
                { Backup-WimImage -ImagePath "TestDrive:\source\install.wim" -MaxBackupCount 0 } |
                    Should -Throw
                { Backup-WimImage -ImagePath "TestDrive:\source\install.wim" -MaxBackupCount 101 } |
                    Should -Throw
            }
        }

        Context "Backup creation" {
            It "Should create backup directory if it doesn't exist" {
                Backup-WimImage -ImagePath "TestDrive:\source\install.wim" -BackupDirectory "TestDrive:\backup"
                Should -Invoke New-Item -ParameterFilter {
                    $Path -eq "TestDrive:\backup" -and $ItemType -eq "Directory"
                }
            }

            It "Should create backup with timestamp" {
                $result = Backup-WimImage -ImagePath "TestDrive:\source\install.wim"
                Should -Invoke Copy-Item
                $result.SourcePath | Should -Be "TestDrive:\source\install.wim"
                $result.BackupPath | Should -Match "_\d{8}_\d{6}\.wim$"
            }

            It "Should use specified backup directory" {
                $result = Backup-WimImage -ImagePath "TestDrive:\source\install.wim" -BackupDirectory "TestDrive:\backup"
                $result.BackupPath | Should -Match "^TestDrive:\\backup\\"
            }
        }

        Context "Backup management" {
            It "Should remove old backups when exceeding MaxBackupCount" {
                Mock Get-ChildItem {
                    1..12 | ForEach-Object {
                        @{
                            Name = "install_2025010${_}_120000.wim"
                            FullName = "TestDrive:\backup\install_2025010${_}_120000.wim"
                            CreationTime = (Get-Date).AddDays(-$_)
                        }
                    }
                }

                $result = Backup-WimImage -ImagePath "TestDrive:\source\install.wim" -MaxBackupCount 5
                Should -Invoke Remove-Item -Times 7  # 12 backups - 5 to keep = 7 to remove
                $result.RemainingBackups | Should -Be 5
            }
        }

        Context "Error handling" {
            It "Should throw when backup creation fails" {
                Mock Copy-Item { throw "Access denied" }
                { Backup-WimImage -ImagePath "TestDrive:\source\install.wim" } |
                    Should -Throw "Failed to create backup"
            }

            It "Should verify backup file size" {
                Mock Get-Item -ParameterFilter { $Path -like "*backup*" } {
                    @{ Length = 2GB }  # Different from source size
                }
                { Backup-WimImage -ImagePath "TestDrive:\source\install.wim" } |
                    Should -Throw "Backup file size mismatch"
            }
        }
    }
}
