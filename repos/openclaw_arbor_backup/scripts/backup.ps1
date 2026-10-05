# GitClaw Windows Backup for openclaw_arbor_backup
# This is a PowerShell adaptation of the GitClaw backup script

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = "D:\AI_PROJECTS\openclaw_arbor_backup"
$LogFile = Join-Path $RootPath "logs\gitclaw_backup.log"
$LockFile = Join-Path $RootPath "tmp\backup.lock"

# Ensure logs and tmp exist
If (-not (Test-Path "$RootPath\logs")) { New-Item -ItemType Directory "$RootPath\logs" | Out-Null }
If (-not (Test-Path "$RootPath\tmp")) { New-Item -ItemType Directory "$RootPath\tmp" | Out-Null }

Function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    $line = "[$timestamp] $message"
    Write-Output $line
    Add-Content -Path $LogFile -Value $line
}

# Prevent overlapping runs
If (Test-Path $LockFile) {
    Write-Log "Error: Lock file exists. Backup already in progress or failed last time."
    # If the lock file is older than 30 mins, assume it's stale
    $lockAge = (Get-Date) - (Get-Item $LockFile).LastWriteTime
    If ($lockAge.TotalMinutes -gt 30) {
        Write-Log "Lock is stale. Removing..."
        Remove-Item $LockFile
    } Else {
        Exit 0
    }
}

New-Item -ItemType File $LockFile | Out-Null

Try {
    Set-Location $RootPath
    
    # 1. Back up openclaw/workspace first (if it's a separate repo or just a folder)
    # We commit in workspace if it's its own repo
    If (Test-Path "openclaw\workspace\.git") {
        Write-Log "Commiting changes in openclaw/workspace..."
        Set-Location "openclaw\workspace"
        git add -A
        $diff = git diff --cached
        If ($diff) {
            git commit -m "Auto-backup (workspace): $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        }
        Set-Location $RootPath
    }

    # 2. Commit and push in the root repo
    Write-Log "Commiting changes in root repository..."
    git add -A
    $diffRoot = git status --porcelain
    If ($diffRoot) {
        git commit -m "Auto-backup: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Log "Pushing to origin..."
        git push origin master
        Write-Log "Backup successful."
    } Else {
        Write-Log "No changes to commit."
    }
} Catch {
    Write-Log "FAILED: $_"
} Finally {
    If (Test-Path $LockFile) { Remove-Item $LockFile }
}
