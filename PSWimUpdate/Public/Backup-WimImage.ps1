<#
.SYNOPSIS
    Creates a backup copy of a Windows Image (.wim) file.
.DESCRIPTION
    This function creates a backup of a Windows Image file before making modifications.
    It includes a timestamp in the backup filename and maintains a history of backups.
    Optionally, it can maintain a specific number of backup versions.
.PARAMETER ImagePath
    The path to the .wim file to backup.
.PARAMETER BackupDirectory
    The directory where backups will be stored. If not specified, creates a 'Backup'
    directory in the same location as the source image.
.PARAMETER MaxBackupCount
    Optional. Maximum number of backup versions to keep. Oldest backups will be removed
    when this limit is exceeded.
.EXAMPLE
    Backup-WimImage -ImagePath "C:\images\install.wim"
.EXAMPLE
    Backup-WimImage -ImagePath "C:\images\install.wim" -BackupDirectory "D:\Backups" -MaxBackupCount 5
.NOTES
    Backup naming format: original_name_YYYYMMDD_HHMMSS.wim
#>
function Backup-WimImage {
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
        [string]$BackupDirectory,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MaxBackupCount = 10
    )

    process {
        try {
            # Get source image info
            $sourceImage = Get-Item $ImagePath
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            
            # Determine backup directory
            if (-not $BackupDirectory) {
                $BackupDirectory = Join-Path $sourceImage.Directory.FullName "Backup"
            }

            # Ensure backup directory exists
            if (-not (Test-Path $BackupDirectory)) {
                New-Item -Path $BackupDirectory -ItemType Directory -Force | Out-Null
                Write-Verbose "Created backup directory: $BackupDirectory"
            }

            # Generate backup filename
            $backupName = "{0}_{1}.wim" -f $sourceImage.BaseName, $timestamp
            $backupPath = Join-Path $BackupDirectory $backupName

            Write-Verbose "Creating backup of $ImagePath to $backupPath"

            # Create the backup
            Copy-Item -Path $ImagePath -Destination $backupPath -Force
            
            # Verify backup was created successfully
            if (-not (Test-Path $backupPath)) {
                throw "Failed to create backup at $backupPath"
            }

            # Verify backup file size matches source
            $backupSize = (Get-Item $backupPath).Length
            $sourceSize = $sourceImage.Length
            if ($backupSize -ne $sourceSize) {
                Remove-Item $backupPath -Force
                throw "Backup file size mismatch. Expected $sourceSize bytes, got $backupSize bytes"
            }

            # Cleanup old backups if necessary
            $backups = Get-ChildItem -Path $BackupDirectory -Filter "$($sourceImage.BaseName)_*.wim" |
                      Sort-Object CreationTime -Descending
            
            if ($backups.Count -gt $MaxBackupCount) {
                $backupsToRemove = $backups | Select-Object -Skip $MaxBackupCount
                foreach ($backup in $backupsToRemove) {
                    Remove-Item $backup.FullName -Force
                    Write-Verbose "Removed old backup: $($backup.Name)"
                }
            }

            # Return information about the created backup
            [PSCustomObject]@{
                SourcePath = $ImagePath
                BackupPath = $backupPath
                BackupTime = Get-Date
                Size = Format-FileSize -Size $backupSize
                RemainingBackups = [Math]::Min($backups.Count, $MaxBackupCount)
            }
        }
        catch {
            Write-Error "Failed to create backup: $_"
            throw
        }
    }
}
