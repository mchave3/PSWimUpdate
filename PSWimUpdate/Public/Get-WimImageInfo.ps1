<#
.SYNOPSIS
    Gets information about Windows Image (.wim) files.
.DESCRIPTION
    This function retrieves detailed information about Windows Image (.wim) files.
.PARAMETER ImagePath
    The path to the .wim file to get information about.
.PARAMETER Index
    Optional. The specific index number to get information about.
    If not specified, information about all indexes will be returned.
.EXAMPLE
    Get-WimImageInfo -ImagePath "C:\images\install.wim"
.EXAMPLE
    Get-WimImageInfo -ImagePath "C:\images\install.wim" -Index 1
#>
function Get-WimImageInfo {
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

        [Parameter()]
        [ValidateRange(1, 99)]
        [int]$Index
    )

    try {
        # Get image information
        $images = Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop

        # Filter by index if specified
        if ($PSBoundParameters.ContainsKey('Index')) {
            $images = $images | Where-Object { $_.ImageIndex -eq $Index }
            if (-not $images) {
                throw "No image found with index $Index"
            }
        }

        # Format and return results
        $images | ForEach-Object {
            [PSCustomObject]@{
                Index = $_.ImageIndex
                Name = $_.ImageName
                Description = $_.ImageDescription
                Size = Format-FileSize -Size $_.ImageSize
                WIMBoot = $_.WIMBoot
                Architecture = $_.Architecture
                Version = $_.Version
                SPBuild = $_.SPBuild
                Languages = $_.Languages
                EditionId = $_.EditionId
                InstallationType = $_.InstallationType
                CreatedTime = $_.CreatedTime
                ModifiedTime = $_.ModifiedTime
            }
        }
    }
    catch {
        Write-Error "Failed to get image information: $_"
        throw
    }
}
