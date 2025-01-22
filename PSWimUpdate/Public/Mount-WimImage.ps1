<#
.SYNOPSIS
    Mounts a Windows Image (.wim) file to a specified directory.
.DESCRIPTION
    This function mounts a Windows Image (.wim) file to a specified directory using the DISM PowerShell module.
    It includes validation of the image path, mount path, and index number. It also creates the mount directory
    if it doesn't exist and handles errors appropriately.
.PARAMETER ImagePath
    The path to the .wim file to be mounted.
.PARAMETER MountPath
    The directory where the image will be mounted.
.PARAMETER Index
    The index number of the image to mount from the .wim file. Defaults to 1.
.PARAMETER ReadOnly
    Mount the image in read-only mode.
.EXAMPLE
    Mount-WimImage -ImagePath "C:\images\install.wim" -MountPath "C:\mount" -Index 1
.NOTES
    Requires elevation (must be run as Administrator)
#>
function Mount-WimImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-Not (Test-Path $_)) {
                throw "Image file not found at $_"
            }
            if (-Not ($_ -match "\.wim$")) {
                throw "The file specified must be a .wim file"
            }
            return $true
        })]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [ValidateScript({
            if (-Not (Test-Path $_)) {
                New-Item -Path $_ -ItemType Directory -Force | Out-Null
            }
            return $true
        })]
        [string]$MountPath,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 99)]
        [int]$Index,

        [Parameter()]
        [switch]$ReadOnly
    )

    try {
        # Vérifier les privilèges administrateur
        Test-AdminPrivilege

        # Monter l'image
        $mountParams = @{
            ImagePath = $ImagePath
            Path = $MountPath
            Index = $Index
            ErrorAction = 'Stop'
        }

        if ($ReadOnly) {
            $mountParams['ReadOnly'] = $true
        }

        Mount-WindowsImage @mountParams

        # Retourner les informations de montage
        Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $MountPath }
    }
    catch {
        Write-Error "Failed to mount image: $_"
        throw
    }
}
