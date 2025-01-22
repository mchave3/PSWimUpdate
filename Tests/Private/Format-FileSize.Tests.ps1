$here = (Split-Path -Parent $MyInvocation.MyCommand.Path).Replace((Join-Path "Tests" Private), (Join-Path PSWimUpdate Private))
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace(".Tests.", ".")

. (Join-Path $here $sut)

InModuleScope "PSWimUpdate" {
    Describe "Format-FileSize" {
        Context "Size formatting" {
            It "Should format bytes" {
                Format-FileSize -Size 512 | Should -Be "512 B"
            }

            It "Should format kilobytes" {
                Format-FileSize -Size 1536 | Should -Be "1.50 KB"
            }

            It "Should format megabytes" {
                Format-FileSize -Size (1.5 * 1MB) | Should -Be "1.50 MB"
            }

            It "Should format gigabytes" {
                Format-FileSize -Size (2.5 * 1GB) | Should -Be "2.50 GB"
            }
        }

        Context "Parameter validation" {
            It "Should require Size parameter" {
                { Format-FileSize } | Should -Throw
            }

            It "Should accept long values" {
                { Format-FileSize -Size ([long]::MaxValue) } | Should -Not -Throw
            }
        }
    }
}
