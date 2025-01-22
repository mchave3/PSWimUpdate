$here = (Split-Path -Parent $MyInvocation.MyCommand.Path).Replace((Join-Path "Tests" Private), (Join-Path PSWimUpdate Private))
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

. (Join-Path $here $sut)

InModuleScope "PSWimUpdate" {
    Describe "Test-AdminPrivilege" {
        Context "When running as admin" {
            Mock Get-CurrentIdentity {
                $identity = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::Empty)
                $identity.IsInRole = { $true }
                return $identity
            }

            It "Should return true" {
                Test-AdminPrivilege | Should -BeTrue
            }
        }

        Context "When not running as admin" {
            Mock Get-CurrentIdentity {
                $identity = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::Empty)
                $identity.IsInRole = { $false }
                return $identity
            }

            It "Should throw" {
                { Test-AdminPrivilege } | Should -Throw "requires administrator privileges"
            }
        }
    }
}
