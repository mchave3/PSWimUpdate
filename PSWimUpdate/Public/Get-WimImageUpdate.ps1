<#
.SYNOPSIS
    Gets the list of updates installed in a Windows Image.
.DESCRIPTION
    This function retrieves information about updates installed in a Windows Image,
    either mounted or directly from the .wim file. It can filter updates by type
    and provides detailed information about each update.
.PARAMETER ImagePath
    The path to the .wim file to query.
.PARAMETER MountPath
    The path where the image is mounted. If specified, takes precedence over ImagePath.
.PARAMETER Index
    The index of the image to query. Required when using ImagePath.
.PARAMETER UpdateType
    Optional. Filter updates by type: Security, Critical, General, Language, or All.
.PARAMETER Detailed
    If specified, returns detailed information about each update.
.EXAMPLE
    Get-WimImageUpdate -MountPath "C:\mount"
.EXAMPLE
    Get-WimImageUpdate -ImagePath "C:\images\install.wim" -Index 1 -UpdateType Security -Detailed
.NOTES
    Returns both Windows Updates and Servicing Stack Updates (SSU).
#>
function Get-WimImageUpdate {
    [CmdletBinding(DefaultParameterSetName = 'Mounted')]
    param(
        [Parameter(ParameterSetName = 'WIM',
                   Mandatory = $true)]
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

        [Parameter(ParameterSetName = 'Mounted',
                   Mandatory = $true)]
        [ValidateScript({
            if (-Not (Test-Path $_)) {
                throw "Mount path not found at $_"
            }
            return $true
        })]
        [string]$MountPath,

        [Parameter(ParameterSetName = 'WIM',
                   Mandatory = $true)]
        [ValidateRange(1, 99)]
        [int]$Index,

        [Parameter()]
        [ValidateSet('Security', 'Critical', 'General', 'Language', 'All')]
        [string]$UpdateType = 'All',

        [Parameter()]
        [switch]$Detailed
    )

    process {
        try {
            # If using WIM file directly, mount it temporarily
            $tempMount = $false
            $targetPath = $MountPath

            if ($PSCmdlet.ParameterSetName -eq 'WIM') {
                $tempMount = $true
                $targetPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                
                Write-Verbose "Temporarily mounting image for update inspection"
                Mount-WindowsImage -ImagePath $ImagePath -Path $targetPath -Index $Index -ErrorAction Stop
            }

            try {
                # Get all updates
                Write-Verbose "Retrieving installed updates"
                $updates = Get-WindowsPackage -Path $targetPath |
                          Where-Object { $_.PackageState -eq "Installed" }

                # Filter by type if specified
                if ($UpdateType -ne 'All') {
                    $updates = $updates | Where-Object {
                        switch ($UpdateType) {
                            'Security' { $_.ReleaseType -eq "Security Update" }
                            'Critical' { $_.ReleaseType -eq "Critical Update" }
                            'General' { $_.ReleaseType -eq "Update" }
                            'Language' { $_.ReleaseType -eq "Language Pack" }
                        }
                    }
                }

                # Process each update
                $results = foreach ($update in $updates) {
                    if ($Detailed) {
                        [PSCustomObject]@{
                            Name = $update.PackageName
                            Description = $update.Description
                            Version = $update.Version
                            InstallTime = $update.InstallTime
                            ReleaseType = $update.ReleaseType
                            ProductName = $update.ProductName
                            ProductVersion = $update.ProductVersion
                            Company = $update.Company
                            InstallPackageName = $update.InstallPackageName
                            Support = $update.SupportInformation
                        }
                    }
                    else {
                        [PSCustomObject]@{
                            Name = $update.PackageName
                            Version = $update.Version
                            ReleaseType = $update.ReleaseType
                            InstallTime = $update.InstallTime
                        }
                    }
                }

                # Return results
                $results
            }
            finally {
                # Cleanup temporary mount if necessary
                if ($tempMount) {
                    Write-Verbose "Cleaning up temporary mount"
                    Dismount-WindowsImage -Path $targetPath -Discard -ErrorAction Stop
                    Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Error "Failed to get update information: $_"
            throw
        }
    }
}
