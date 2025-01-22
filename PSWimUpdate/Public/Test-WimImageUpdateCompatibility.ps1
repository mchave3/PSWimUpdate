<#
.SYNOPSIS
    Tests compatibility of Windows updates with a Windows Image.
.DESCRIPTION
    This function analyzes Windows updates to determine their compatibility with
    a specified Windows Image. It checks prerequisites, dependencies, and potential
    conflicts with installed updates.
.PARAMETER ImagePath
    The path to the .wim file to test updates against.
.PARAMETER MountPath
    The path where the image is mounted. If specified, takes precedence over ImagePath.
.PARAMETER Index
    The index of the image to test. Required when using ImagePath.
.PARAMETER Update
    One or more update objects from Find-WimImageUpdate or paths to .msu files to test.
.PARAMETER Detailed
    If specified, returns detailed compatibility information.
.EXAMPLE
    Find-WimImageUpdate -MountPath "C:\mount" | Test-WimImageUpdateCompatibility
.EXAMPLE
    Test-WimImageUpdateCompatibility -ImagePath "C:\images\install.wim" -Index 1 -Update "C:\Updates\KB123456.msu" -Detailed
.NOTES
    This function performs offline compatibility checking and may not catch all potential issues.
#>
function Test-WimImageUpdateCompatibility {
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

        [Parameter(Mandatory = $true,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNull()]
        [object[]]$Update,

        [Parameter()]
        [switch]$Detailed
    )

    begin {
        # Vérifier les privilèges administrateur
        Test-AdminPrivilege

        # Helper function to get update info from .msu file
        function Get-MsuInfo {
            param([string]$Path)
            
            try {
                $info = Get-WindowsPackage -Path $Path -ErrorAction Stop
                return @{
                    KB = ($info.PackageName -replace '^.*_(KB\d+)_.*$', '$1')
                    Name = $info.PackageName
                    Applicable = $info.Applicable
                    Dependencies = $info.Dependencies
                    ReleaseType = $info.ReleaseType
                }
            }
            catch {
                Write-Warning "Failed to get information from MSU file: $_"
                return $null
            }
        }

        # Helper function to check update dependencies
        function Test-UpdateDependencies {
            param(
                $UpdateInfo,
                $InstalledUpdates
            )

            $results = @{
                MissingDependencies = @()
                Conflicts = @()
            }

            foreach ($dep in $UpdateInfo.Dependencies) {
                $isInstalled = $InstalledUpdates | Where-Object {
                    $_.PackageName -match $dep.Name
                }

                if (-not $isInstalled) {
                    $results.MissingDependencies += $dep.Name
                }
            }

            # Check for superseded updates
            $supersededBy = $InstalledUpdates | Where-Object {
                $_.SupersededPackages -contains $UpdateInfo.Name
            }

            if ($supersededBy) {
                $results.Conflicts += "Update is superseded by: $($supersededBy.PackageName)"
            }

            return $results
        }
    }

    process {
        try {
            # If using WIM file directly, mount it temporarily
            $tempMount = $false
            $targetPath = $MountPath

            if ($PSCmdlet.ParameterSetName -eq 'WIM') {
                $tempMount = $true
                $targetPath = New-TemporaryMount -ImagePath $ImagePath -Index $Index
            }

            try {
                # Get installed updates
                $installedUpdates = Get-WindowsPackage -Path $targetPath |
                                  Where-Object { $_.PackageState -eq "Installed" }

                # Process each update
                $results = foreach ($updateItem in $Update) {
                    $updateInfo = $null

                    # Handle different input types
                    if ($updateItem -is [string] -and (Test-Path $updateItem)) {
                        # Input is path to .msu file
                        $updateInfo = Get-MsuInfo -Path $updateItem
                        if (-not $updateInfo) { continue }
                    }
                    else {
                        # Input is update object from Find-WimImageUpdate
                        $updateInfo = @{
                            KB = $updateItem.KB
                            Name = $updateItem.Title
                            ReleaseType = $updateItem.Classification
                            Dependencies = @()
                        }
                    }

                    # Check dependencies and conflicts
                    $depCheck = Test-UpdateDependencies -UpdateInfo $updateInfo -InstalledUpdates $installedUpdates

                    if ($Detailed) {
                        [PSCustomObject]@{
                            KB = $updateInfo.KB
                            Name = $updateInfo.Name
                            IsCompatible = ($depCheck.MissingDependencies.Count -eq 0 -and $depCheck.Conflicts.Count -eq 0)
                            MissingDependencies = $depCheck.MissingDependencies
                            Conflicts = $depCheck.Conflicts
                            ReleaseType = $updateInfo.ReleaseType
                            AlreadyInstalled = ($installedUpdates | Where-Object { $_.PackageName -match $updateInfo.KB }) -ne $null
                        }
                    }
                    else {
                        [PSCustomObject]@{
                            KB = $updateInfo.KB
                            IsCompatible = ($depCheck.MissingDependencies.Count -eq 0 -and $depCheck.Conflicts.Count -eq 0)
                            HasIssues = ($depCheck.MissingDependencies.Count -gt 0 -or $depCheck.Conflicts.Count -gt 0)
                        }
                    }
                }

                # Return results
                $results
            }
            finally {
                # Cleanup temporary mount if necessary
                if ($tempMount) {
                    Remove-TemporaryMount -MountPath $targetPath
                }
            }
        }
        catch {
            Write-Error "Failed to test update compatibility: $_"
            throw
        }
    }
}
