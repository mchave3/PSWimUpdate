<#
.SYNOPSIS
    Validates the integrity of a Windows Image (.wim) file.
.DESCRIPTION
    This function performs various integrity checks on a Windows Image file:
    - Verifies the WIM file structure
    - Checks for corruption in the image data
    - Validates metadata consistency
    - For mounted images, verifies mount state integrity
.PARAMETER ImagePath
    The path to the .wim file to validate.
.PARAMETER Index
    Optional. The specific index to validate. If not specified, all indexes are validated.
.PARAMETER CheckMountState
    If specified, also checks the integrity of any mounted instances of the image.
.PARAMETER Detailed
    If specified, returns detailed information about any issues found.
.EXAMPLE
    Test-WimImage -ImagePath "C:\images\install.wim"
.EXAMPLE
    Test-WimImage -ImagePath "C:\images\install.wim" -Index 1 -Detailed
.NOTES
    This function uses DISM API calls to perform integrity checks.
#>
function Test-WimImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
                   Position = 0,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true)]
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
        [int]$Index,

        [Parameter()]
        [switch]$CheckMountState,

        [Parameter()]
        [switch]$Detailed
    )

    process {
        try {
            $results = @{
                ImagePath = $ImagePath
                IsValid = $true
                Issues = @()
                Details = @{}
            }

            # Get basic image information
            try {
                $imageInfo = Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop
                if ($Index) {
                    $imageInfo = $imageInfo | Where-Object { $_.ImageIndex -eq $Index }
                    if (-not $imageInfo) {
                        throw "Index $Index not found in image"
                    }
                }
            }
            catch {
                $results.IsValid = $false
                $results.Issues += "Failed to read image information: $_"
                return [PSCustomObject]$results
            }

            # Check WIM file structure
            Write-Verbose "Checking WIM file structure"
            try {
                $null = Get-WindowsImage -ImagePath $ImagePath -Verify -ErrorAction Stop
            }
            catch {
                $results.IsValid = $false
                $results.Issues += "WIM file structure validation failed: $_"
            }

            # Check each index
            foreach ($image in $imageInfo) {
                $indexResults = @{
                    Index = $image.ImageIndex
                    Name = $image.ImageName
                    Issues = @()
                }

                # Check image data integrity
                Write-Verbose "Checking integrity of index $($image.ImageIndex)"
                try {
                    $null = Get-WindowsImage -ImagePath $ImagePath -Index $image.ImageIndex -Verify -ErrorAction Stop
                }
                catch {
                    $results.IsValid = $false
                    $indexResults.Issues += "Image data corruption detected: $_"
                }

                # Check mount state if requested
                if ($CheckMountState) {
                    Write-Verbose "Checking mount state of index $($image.ImageIndex)"
                    $mountInfo = Get-WindowsImage -Mounted |
                                Where-Object { $_.ImagePath -eq $ImagePath -and $_.ImageIndex -eq $image.ImageIndex }
                    
                    if ($mountInfo) {
                        # Verify mount path exists and is accessible
                        if (-not (Test-Path $mountInfo.Path)) {
                            $results.IsValid = $false
                            $indexResults.Issues += "Mount path not found: $($mountInfo.Path)"
                        }
                        
                        # Check for mount state corruption
                        try {
                            $null = Get-WindowsImage -Mounted |
                                   Where-Object { $_.Path -eq $mountInfo.Path } |
                                   Get-WindowsImage -Verify -ErrorAction Stop
                        }
                        catch {
                            $results.IsValid = $false
                            $indexResults.Issues += "Mounted image corruption detected: $_"
                        }
                    }
                }

                if ($indexResults.Issues.Count -gt 0) {
                    $results.Details[$image.ImageIndex] = $indexResults
                }
            }

            # Return results
            if ($Detailed) {
                [PSCustomObject]$results
            }
            else {
                [PSCustomObject]@{
                    ImagePath = $ImagePath
                    IsValid = $results.IsValid
                    IssueCount = $results.Issues.Count + `
                                ($results.Details.Values | ForEach-Object { $_.Issues.Count } | Measure-Object -Sum).Sum
                }
            }
        }
        catch {
            Write-Error "Failed to validate image: $_"
            throw
        }
    }
}
