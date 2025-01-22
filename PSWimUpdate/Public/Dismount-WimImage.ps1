<#
.SYNOPSIS
    Dismounts a previously mounted Windows Image (.wim).
.DESCRIPTION
    This function dismounts a Windows Image that was previously mounted using Mount-WimImage.
    It provides options to save or discard changes made to the mounted image.
.PARAMETER MountPath
    The path where the image is currently mounted.
.PARAMETER Save
    If specified, changes made to the mounted image will be saved back to the .wim file.
    If not specified, changes will be discarded.
.PARAMETER Force
    If specified, forces the dismount operation.
.EXAMPLE
    Dismount-WimImage -MountPath "C:\mount" -Save
.EXAMPLE
    Dismount-WimImage -MountPath "C:\mount"
.EXAMPLE
    Dismount-WimImage -MountPath "C:\mount" -Force
.NOTES
    Requires elevation (must be run as Administrator)
#>
function Dismount-WimImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
                   Position = 0,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({
            if (-Not (Test-Path $_)) {
                throw "Mount path not found at $_"
            }
            return $true
        })]
        [string]$MountPath,

        [Parameter()]
        [switch]$Save,

        [Parameter()]
        [switch]$Force
    )

    try {
        # Verify running as administrator
        Test-AdminPrivilege

        # Verify the path is actually a mounted image
        $mountedImages = Get-WindowsImage -Mounted
        $mountedImage = $mountedImages | Where-Object { $_.Path -eq $MountPath }
        
        if (-not $mountedImage) {
            throw "No mounted image found at path: $MountPath"
        }

        Write-Verbose "Dismounting image from $MountPath (Save: $Save)"

        # Prepare dismount parameters
        $dismountParams = @{
            Path = $MountPath
            ErrorAction = 'Stop'
        }

        if ($Save) {
            $dismountParams['Save'] = $true
        } else {
            $dismountParams['Discard'] = $true
        }

        if ($Force) {
            $dismountParams['Force'] = $true
        }

        # Dismount the image
        Dismount-WindowsImage @dismountParams

        # Verify dismount was successful
        $stillMounted = Get-WindowsImage -Mounted | Where-Object { $_.Path -eq $MountPath }
        if ($stillMounted) {
            throw "Failed to dismount image from $MountPath"
        }

        Write-Verbose "Image successfully dismounted from $MountPath"

        # Clean up mount directory if it's empty
        if ((Get-ChildItem -Path $MountPath -Force | Measure-Object).Count -eq 0) {
            Remove-Item -Path $MountPath -Force
            Write-Verbose "Removed empty mount directory: $MountPath"
        }
    }
    catch {
        Write-Error "Failed to dismount image: $_"
        throw
    }
}
