function New-TemporaryMount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    $targetPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                
    Write-Verbose "Creating temporary mount at $targetPath"
    try {
        Mount-WindowsImage -ImagePath $ImagePath -Path $targetPath -Index $Index -ErrorAction Stop
        return $targetPath
    }
    catch {
        Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
        throw
    }
}
