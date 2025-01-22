function Test-AdminPrivilege {
    [CmdletBinding()]
    param()

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This function requires administrator privileges"
    }
    return $true
}
