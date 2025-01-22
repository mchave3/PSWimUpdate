$here = (Split-Path -Parent $MyInvocation.MyCommand.Path).Replace((Join-Path "Tests" Private), (Join-Path PSWimUpdate Private))
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

. (Join-Path $here $sut)

InModuleScope "PSWimUpdate" {
    Describe "Remove-TemporaryMount" {
        BeforeAll {
            Mock Dismount-WindowsImage { }
            Mock Remove-Item { }
        }

        Context "Successful cleanup" {
            It "Should dismount the image" {
                Remove-TemporaryMount -MountPath "TestDrive:\mount"
                Should -Invoke Dismount-WindowsImage -ParameterFilter {
                    $Path -eq "TestDrive:\mount" -and
                    $Discard -eq $true
                }
            }

            It "Should remove the mount directory" {
                Remove-TemporaryMount -MountPath "TestDrive:\mount"
                Should -Invoke Remove-Item -ParameterFilter {
                    $Path -eq "TestDrive:\mount"
                }
            }
        }

        Context "Error handling" {
            It "Should throw on dismount failure" {
                Mock Dismount-WindowsImage { throw "Dismount failed" }
                { Remove-TemporaryMount -MountPath "TestDrive:\mount" } |
                    Should -Throw
            }

            It "Should attempt directory removal even if dismount fails" {
                Mock Dismount-WindowsImage { throw "Dismount failed" }
                { Remove-TemporaryMount -MountPath "TestDrive:\mount" } |
                    Should -Throw
                Should -Invoke Remove-Item
            }
        }
    }
}
