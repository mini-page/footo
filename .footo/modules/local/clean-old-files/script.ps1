function Clean-Old {
    param (
        [string]$Path,
        [int]$Months,
        [string[]]$Extensions,
        [switch]$AutoDelete
    )

    # --- Colors ---
    $ColorHeader = "Cyan"
    $ColorWarn = "Yellow"
    $ColorInfo = "Green"
    $ColorError = "Red"

    # --- Interactive prompts ---
    if (-not $Path) {
        $inputPath = Read-Host "▸ Enter folder path (leave empty for current directory)"
        $Path = if ($inputPath) { $inputPath } else { Get-Location }
    }

    if (-not $Months) {
        $inputMonths = Read-Host "▸ Enter minimum file age in months (default 12)"
        $parsed = 0
        if ([int]::TryParse($inputMonths, [ref]$parsed)) { 
            $Months = $parsed 
        } else { 
            $Months = 12 
        }
    }

    if (-not $Extensions) {
        Write-Host "▸ Enter file extensions to clean (without dot(.)) Example: txt, log" -ForegroundColor $ColorHeader
        Write-Host "  Press Enter to use default: txt, log" -ForegroundColor $ColorInfo
        $inputExtensions = Read-Host "Enter extensions"
        if ([string]::IsNullOrEmpty($inputExtensions)) {
            $Extensions = @("txt","log")
        } else {
            $Extensions = $inputExtensions -split "," | ForEach-Object { $_.Trim() }
        }
    }

    $Extensions = $Extensions | ForEach-Object { "*.$_" }

    # --- Validate path ---
    if (-not (Test-Path $Path)) {
        Write-Host "✖ Path '$Path' does not exist." -ForegroundColor $ColorError
        return
    }

    # --- Show scanning spinner while collecting files ---
    Write-Host "`nScanning files..." -ForegroundColor $ColorInfo
    $spinner = @('|','/','-','\')
    $i = 0

    # Collect files first
    $allFiles = Get-ChildItem -Path $Path -Recurse -File -Include $Extensions -ErrorAction SilentlyContinue

    # Filter old files with spinner
    $oldFiles = @()
    foreach ($file in $allFiles) {
        if ($file.LastWriteTime -lt (Get-Date).AddMonths(-$Months)) {
            $oldFiles += $file
        }
        Write-Host -NoNewline ("`r" + $spinner[$i % $spinner.Length] + " scanning... $($oldFiles.Count) found")
        Start-Sleep -Milliseconds 50
        $i++
    }

    Write-Host "`r✓ Scan complete! Found $($oldFiles.Count) files." -ForegroundColor $ColorInfo

    if ($oldFiles.Count -eq 0) {
        Write-Host "No old files found." -ForegroundColor $ColorWarn
        return
    }

    # --- Display files in blocks ---
    Write-Host "`nFiles to delete:" -ForegroundColor $ColorHeader
    foreach ($file in $oldFiles) {
        Write-Host ("  ▸ " + $file.FullName + "  (Last Modified: " + $file.LastWriteTime + ")") -ForegroundColor $ColorInfo
    }

    # --- Delete files ---
    if ($AutoDelete) {
        Write-Host "`nDeleting files..." -ForegroundColor $ColorWarn
        $oldFiles | Remove-Item -Force -Verbose
        Write-Host "`n✓ Files deleted successfully." -ForegroundColor $ColorInfo
    } else {
        $confirm = Read-Host "`nDo you want to delete all these files? (Y/N)"
        if ($confirm -match "^[Yy]") {
            Write-Host "`nDeleting files..." -ForegroundColor $ColorWarn
            $oldFiles | Remove-Item -Force -Verbose
            Write-Host "`n✓ Files deleted successfully." -ForegroundColor $ColorInfo
        } else {
            Write-Host "`nNo files were deleted." -ForegroundColor $ColorWarn
        }
    }
}