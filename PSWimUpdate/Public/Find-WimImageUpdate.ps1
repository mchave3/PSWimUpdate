<#
.SYNOPSIS
    Searches for available updates for a Windows Image from the Microsoft Update Catalog.
.DESCRIPTION
    This function queries the Microsoft Update Catalog for available updates that are
    applicable to the specified Windows Image. It can filter updates by type and
    supports both mounted and unmounted images.
.PARAMETER ImagePath
    The path to the .wim file to find updates for.
.PARAMETER MountPath
    The path where the image is mounted. If specified, takes precedence over ImagePath.
.PARAMETER Index
    The index of the image to query. Required when using ImagePath.
.PARAMETER UpdateType
    Optional. Filter updates by type: Security, Critical, General, Language, or All.
.PARAMETER MaxResults
    Optional. Maximum number of updates to return. Default is 100.
.PARAMETER ExcludeInstalled
    If specified, excludes updates that are already installed in the image.
.EXAMPLE
    Find-WimImageUpdate -MountPath "C:\mount" -UpdateType Security
.EXAMPLE
    Find-WimImageUpdate -ImagePath "C:\images\install.wim" -Index 1 -ExcludeInstalled
.NOTES
    Requires internet connectivity to access the Microsoft Update Catalog.
#>
function Find-WimImageUpdate {
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
        [ValidateRange(1, 1000)]
        [int]$MaxResults = 100,

        [Parameter()]
        [switch]$ExcludeInstalled
    )

    begin {
        # Helper function to get image information
        function Get-ImageInfo {
            param($Path)
            
            try {
                $osInfo = Get-WindowsImage -ImagePath $Path -Index $Index | Select-Object -First 1
                return @{
                    Version = $osInfo.Version
                    Architecture = $osInfo.Architecture
                    EditionId = $osInfo.EditionId
                    InstallationType = $osInfo.InstallationType
                }
            }
            catch {
                throw "Failed to get image information: $_"
            }
        }

        # Helper function to query Microsoft Update Catalog
        function Query-UpdateCatalog {
            param(
                $ImageInfo,
                $UpdateType,
                $MaxResults
            )

            try {
                # Build search criteria
                $criteria = @{
                    VersionFilter = $ImageInfo.Version
                    ArchitectureFilter = $ImageInfo.Architecture
                    EditionFilter = $ImageInfo.EditionId
                }

                if ($UpdateType -ne 'All') {
                    $criteria.Add('UpdateType', $UpdateType)
                }

                # Query updates using PSWindowsUpdate module if available
                if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                    Import-Module PSWindowsUpdate
                    $updates = Get-WindowsUpdate -MicrosoftUpdate -Category $UpdateType `
                              -FilterResult $MaxResults @criteria
                }
                else {
                    # Fallback to manual web service query
                    $updates = Invoke-RestMethod -Uri "https://www.catalog.update.microsoft.com/Search.aspx" `
                              -Method Post -Body $criteria
                }

                return $updates
            }
            catch {
                Write-Warning "Failed to query update catalog: $_"
                return $null
            }
        }
    }

    process {
        try {
            # If using WIM file directly, mount it temporarily
            $tempMount = $false
            $targetPath = $MountPath

            if ($PSCmdlet.ParameterSetName -eq 'WIM') {
                $tempMount = $true
                $targetPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                
                Write-Verbose "Temporarily mounting image for update search"
                Mount-WindowsImage -ImagePath $ImagePath -Path $targetPath -Index $Index -ErrorAction Stop
            }

            try {
                # Get image information
                $imageInfo = Get-ImageInfo -Path $targetPath

                # Get installed updates if needed
                $installedUpdates = @()
                if ($ExcludeInstalled) {
                    Write-Verbose "Getting installed updates"
                    $installedUpdates = Get-WindowsPackage -Path $targetPath |
                                      Where-Object { $_.PackageState -eq "Installed" } |
                                      Select-Object -ExpandProperty PackageName
                }

                # Query update catalog
                Write-Verbose "Querying Microsoft Update Catalog"
                $availableUpdates = Query-UpdateCatalog -ImageInfo $imageInfo `
                                                      -UpdateType $UpdateType `
                                                      -MaxResults $MaxResults

                # Filter and format results
                $results = foreach ($update in $availableUpdates) {
                    # Skip if already installed
                    if ($ExcludeInstalled -and $installedUpdates -contains $update.KBNumber) {
                        continue
                    }

                    [PSCustomObject]@{
                        Id = $update.Identity
                        KB = $update.KBNumber
                        Title = $update.Title
                        Description = $update.Description
                        Classification = $update.Classification
                        ReleaseDate = $update.ReleaseDate
                        Size = $update.Size
                        DownloadUrl = $update.DownloadUrl
                        IsSuperseded = $update.IsSuperseded
                        RequiresReboot = $update.RequiresReboot
                    }
                }

                # Return results
                $results | Select-Object -First $MaxResults
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
            Write-Error "Failed to find updates: $_"
            throw
        }
    }
}
