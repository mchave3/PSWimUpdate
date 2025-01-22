<#
.SYNOPSIS
    Downloads and saves Windows updates for offline installation.
.DESCRIPTION
    This function downloads updates from the Microsoft Update Catalog and saves them
    for later installation. It supports batch downloading of multiple updates and
    includes validation of downloaded files.
.PARAMETER Update
    One or more update objects from Find-WimImageUpdate to download.
.PARAMETER Path
    The directory where updates should be saved. If not specified, uses the current directory.
.PARAMETER Force
    If specified, overwrites existing files.
.EXAMPLE
    Find-WimImageUpdate -MountPath "C:\mount" | Save-WimImageUpdate -Path "C:\Updates"
.EXAMPLE
    $update = Find-WimImageUpdate -ImagePath "C:\images\install.wim" -Index 1 | Select-Object -First 1
    Save-WimImageUpdate -Update $update -Path "C:\Updates" -Force
.NOTES
    Requires internet connectivity to download updates.
#>
function Save-WimImageUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
                   Position = 0,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNull()]
        [PSObject[]]$Update,

        [Parameter()]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [switch]$Force
    )

    begin {
        # Ensure target directory exists
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $Path"
        }

        # Initialize progress tracking
        $totalUpdates = 0
        $currentUpdate = 0
        $downloadedFiles = @()

        # Helper function to format file size
        function Format-FileSize {
            param([long]$Size)
            if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
            if ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
            if ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
            return "$Size B"
        }

        # Helper function to validate downloaded file
        function Test-DownloadedFile {
            param(
                [string]$FilePath,
                [long]$ExpectedSize
            )

            if (-not (Test-Path $FilePath)) {
                return $false
            }

            $actualSize = (Get-Item $FilePath).Length
            return $actualSize -eq $ExpectedSize
        }
    }

    process {
        try {
            # Count total updates for progress
            $totalUpdates = @($Update).Count

            foreach ($updateItem in $Update) {
                $currentUpdate++
                
                # Generate target filename
                $fileName = "Windows10-KB$($updateItem.KB)-x64.msu"
                if ($updateItem.Title -match "KB\d+") {
                    $fileName = "Windows10-$($matches[0])-x64.msu"
                }
                $targetPath = Join-Path $Path $fileName

                # Check if file already exists
                if (Test-Path $targetPath) {
                    if (-not $Force) {
                        Write-Warning "File already exists: $fileName. Use -Force to overwrite."
                        continue
                    }
                    Remove-Item $targetPath -Force
                }

                # Prepare progress bar
                $progressParams = @{
                    Activity = "Downloading Windows Updates"
                    Status = "Downloading $fileName"
                    PercentComplete = ($currentUpdate / $totalUpdates * 100)
                    CurrentOperation = "($currentUpdate of $totalUpdates) - $($updateItem.Title)"
                }
                Write-Progress @progressParams

                Write-Verbose "Downloading update KB$($updateItem.KB) to $targetPath"

                # Download the update
                try {
                    $webClient = New-Object System.Net.WebClient
                    $webClient.Headers.Add("User-Agent", "PowerShell Script")
                    $webClient.DownloadFile($updateItem.DownloadUrl, $targetPath)
                }
                catch {
                    Write-Error "Failed to download update KB$($updateItem.KB): $_"
                    continue
                }
                finally {
                    if ($webClient) {
                        $webClient.Dispose()
                    }
                }

                # Validate downloaded file
                if (Test-DownloadedFile -FilePath $targetPath -ExpectedSize $updateItem.Size) {
                    $downloadedFiles += [PSCustomObject]@{
                        KB = $updateItem.KB
                        Path = $targetPath
                        Size = Format-FileSize -Size $updateItem.Size
                        Title = $updateItem.Title
                    }
                    Write-Verbose "Successfully downloaded and verified: $fileName"
                }
                else {
                    Write-Error "Failed to verify downloaded file: $fileName"
                    if (Test-Path $targetPath) {
                        Remove-Item $targetPath -Force
                    }
                }
            }
        }
        catch {
            Write-Error "Failed to save updates: $_"
            throw
        }
    }

    end {
        Write-Progress -Activity "Downloading Windows Updates" -Completed

        if ($downloadedFiles.Count -gt 0) {
            Write-Verbose "Successfully downloaded $($downloadedFiles.Count) updates"
            $downloadedFiles
        }
    }
}
