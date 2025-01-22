function Remove-TemporaryMount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountPath
    )

    try {
        Write-Verbose "Cleaning up temporary mount at $MountPath"
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop
        Remove-Item -Path $MountPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to cleanup temporary mount at $MountPath : $_"
        throw
    }
}
