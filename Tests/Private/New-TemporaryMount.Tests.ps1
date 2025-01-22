$here = (Split-Path -Parent $MyInvocation.MyCommand.Path).Replace((Join-Path "Tests" Private), (Join-Path PSWimUpdate Private))
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

. (Join-Path $here $sut)

InModuleScope "PSWimUpdate" {
    Describe "New-TemporaryMount" {
        BeforeAll {
            Mock New-Item { }
            Mock Mount-WindowsImage { }
            Mock Remove-Item { }
        }

        Context "Successful mount" {
            It "Should create temporary directory" {
                $result = New-TemporaryMount -ImagePath "TestDrive:\test.wim" -Index 1
                Should -Invoke New-Item -ParameterFilter {
                    $ItemType -eq "Directory"
                }
            }

            It "Should mount the image" {
                $result = New-TemporaryMount -ImagePath "TestDrive:\test.wim" -Index 1
                Should -Invoke Mount-WindowsImage -ParameterFilter {
                    $ImagePath -eq "TestDrive:\test.wim" -and
                    $Index -eq 1
                }
            }

            It "Should return mount path" {
                $result = New-TemporaryMount -ImagePath "TestDrive:\test.wim" -Index 1
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeOfType [string]
            }
        }

        Context "Error handling" {
            It "Should cleanup on mount failure" {
                Mock Mount-WindowsImage { throw "Mount failed" }
                { New-TemporaryMount -ImagePath "TestDrive:\test.wim" -Index 1 } |
                    Should -Throw
                Should -Invoke Remove-Item
            }
        }
    }
}
