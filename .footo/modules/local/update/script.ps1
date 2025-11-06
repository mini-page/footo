# ==========================================================
# Package Management
# ==========================================================

function Update {
    <#
    .SYNOPSIS
    Universal package manager updater with granular source control
    .DESCRIPTION
    Update packages from multiple sources with full user control over which managers to use
    .PARAMETER Sources
    Specify which package managers to update (Winget, Scoop, Choco, NPM, Go, Cargo, Pip, Gem)
    .PARAMETER All
    Update all detected package managers
    .PARAMETER AutoYes
    Skip confirmation prompts
    .PARAMETER Fast
    Use fast/silent modes where available
    .PARAMETER CheckOnly
    Only check for updates, don't install them
    .PARAMETER Comparison
    Show detailed comparison of available vs current versions
    .PARAMETER DebugLog
    Create detailed log file
    .PARAMETER Force
    Force updates even if no updates detected
    .EXAMPLE
    Update -Sources Winget,Scoop
    Update only Winget and Scoop packages
    .EXAMPLE
    Update -Sources NPM,Go -CheckOnly
    Check for NPM and Go updates without installing
    .EXAMPLE
    Update -All -Fast -AutoYes
    Fast update all detected package managers without prompts
    .EXAMPLE
    Update -Sources Choco -Comparison
    Update Chocolatey with detailed version comparison
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Winget', 'Scoop', 'Choco', 'NPM', 'Go', 'Cargo', 'Pip', 'Gem', 'Dotnet')]
        [string[]]$Sources = @(),
        
        [switch]$All,
        [switch]$AutoYes,
        [switch]$Fast,
        [switch]$CheckOnly,
        [switch]$Comparison,
        [switch]$DebugLog,
        [switch]$Force
    )

    $reportPath = Join-Path $env:TEMP "update-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    if ($DebugLog) { 
        "=== Update Run: $(Get-Date) ===`n" | Out-File $reportPath -Append 
    }

    # Define package manager configurations
    $packageManagers = @{
        'Winget' = @{
            Command      = 'winget'
            CheckCmd     = { winget upgrade --accept-source-agreements 2>&1 | Out-String }
            UpdateCmd    = { 
                $args = @("upgrade", "--all", "--accept-source-agreements", "--accept-package-agreements", "--include-unknown")
                if ($Fast) { $args += @("--silent", "--disable-interactivity") }
                winget @args 
            }
            ParseUpdates = { param($output) 
                $output -match '\d+\s+upgrades available' -or 
                ($output -split "`n" | Where-Object { $_ -match '^\S+\s+\S+\s+\S+\s+\S+' }).Count -gt 0
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -match '^\S+\s+\S+\s+\S+\s+\S+' } | ForEach-Object {
                    $parts = $_ -split '\s+'
                    if ($parts.Count -ge 4) {
                        [PSCustomObject] @{ Name = $parts[0]; Current = $parts[1]; Available = $parts[2]; Source = $parts[3] }
                    }
                }
            }
        }
        'Scoop'  = @{
            Command      = 'scoop'
            CheckCmd     = { scoop status 2>&1 | Out-String }
            UpdateCmd    = { 
                scoop update 2>&1 | Out-Null
                scoop update * 2>&1 
            }
            ParseUpdates = { param($output) 
                $output.Trim() -ne "" -and $output -notmatch "Everything is up to date"
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -match '^\s*\S+\s+' } | ForEach-Object {
                    $parts = $_ -split '\s+'
                    if ($parts.Count -ge 2) {
                        [PSCustomObject] @{ Name = $parts[0]; Current = $parts[1]; Available = $parts[2]; Source = "Scoop" }
                    }
                }
            }
        }
        'Choco'  = @{
            Command      = 'choco'
            CheckCmd     = { choco outdated --limit-output 2>&1 | Out-String }
            UpdateCmd    = { 
                $args = @("upgrade", "all", "-y")
                if ($Fast) { $args += "--limit-output" }
                choco @args 
            }
            ParseUpdates = { param($output) 
                $output.Trim() -ne "" -and $output -notmatch "has determined 0 package"
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -contains "|" } | ForEach-Object {
                    $parts = $_ -split '|'
                    if ($parts.Count -ge 3) {
                        [PSCustomObject] @{ Name = $parts[0]; Current = $parts[1]; Available = $parts[2]; Source = "Chocolatey" }
                    }
                }
            }
        }
        'NPM'    = @{
            Command      = 'npm'
            CheckCmd     = { npm outdated -g --json 2>$null | Out-String }
            UpdateCmd    = { npm update -g }
            ParseUpdates = { param($output) 
                try { $json = $output | ConvertFrom-Json; $json.PSObject.Properties.Count -gt 0 } catch { $false }
            }
            GetPackages  = { param($output)
                try {
                    $json = $output | ConvertFrom-Json
                    $json.PSObject.Properties | ForEach-Object {
                        [PSCustomObject] @{ 
                            Name      = $_.Name
                            Current   = $_.Value.current
                            Available = $_.Value.latest
                            Source    = "NPM Global"
                        }
                    }
                }
                catch { @() }
            }
        }
        'Go'     = @{
            Command      = 'go'
            CheckCmd     = { go list -u -m all 2>&1 | Out-String }
            UpdateCmd    = { go get -u all }
            ParseUpdates = { param($output) 
                $output -match '\[.*\]' # Go shows [latest] for updates available
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -match '\[.*\]' } | ForEach-Object {
                    if ($_ -match '^(\S+)\s+(\S+)\s+\[(\S+)\]') {
                        [PSCustomObject] @{ Name = $matches[1]; Current = $matches[2]; Available = $matches[3]; Source = "Go Modules" }
                    }
                }
            }
        }
        'Cargo'  = @{
            Command      = 'cargo'
            CheckCmd     = { cargo install-update --list 2>&1 | Out-String }
            UpdateCmd    = { cargo install-update --all }
            ParseUpdates = { param($output) 
                $output -match 'Updates available' -or $output -match 'Updating'
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -match '->' } | ForEach-Object {
                    if ($_ -match '^(\S+)\s+(\S+)\s+->\s+(\S+)') {
                        [PSCustomObject] @{ Name = $matches[1]; Current = $matches[2]; Available = $matches[3]; Source = "Cargo" }
                    }
                }
            }
        }
        'Pip'    = @{
            Command      = 'pip'
            CheckCmd     = { pip list --outdated --format=json 2>$null | Out-String }
            UpdateCmd    = { 
                $outdated = pip list --outdated --format=json 2>$null | ConvertFrom-Json
                $outdated | ForEach-Object { pip install --upgrade $_.name }
            }
            ParseUpdates = { param($output) 
                try { $json = $output | ConvertFrom-Json; $json.Count -gt 0 } catch { $false }
            }
            GetPackages  = { param($output) 
                try {
                    $json = $output | ConvertFrom-Json
                    $json | ForEach-Object {
                        [PSCustomObject] @{ 
                            Name      = $_.name
                            Current   = $_.version
                            Available = $_.latest_version
                            Source    = "Python Pip"
                        }
                    }
                }
                catch { @() }
            }
        }
        'Gem'    = @{
            Command      = 'gem'
            CheckCmd     = { gem outdated 2>&1 | Out-String }
            UpdateCmd    = { gem update }
            ParseUpdates = { param($output) 
                $output -match '\(.*current:.*\)'
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -match '\(.*current:.*\)' } | ForEach-Object {
                    if ($_ -match '^(\S+)\s+\((.*)\s+current:\s+(\S+)\)') {
                        [PSCustomObject] @{ Name = $matches[1]; Current = $matches[3]; Available = $matches[2]; Source = "Ruby Gem" }
                    }
                }
            }
        }
        'Dotnet' = @{
            Command      = 'dotnet'
            CheckCmd     = { dotnet tool list -g 2>&1 | Out-String }
            UpdateCmd    = { 
                $tools = dotnet tool list -g | Select-String -Pattern "^\S+\s+" | ForEach-Object { ($_ -split '\s+')[0] }
                $tools | ForEach-Object { dotnet tool update -g $_ }
            }
            ParseUpdates = { param($output) 
                # For .NET tools, we'll assume updates are available if tools are installed
                $output -match '^\S+\s+\S+\s+\S+'
            }
            GetPackages  = { param($output)
                $output -split "`n" | Where-Object { $_ -match '^\S+\s+\S+\s+\S+' } | ForEach-Object {
                    $parts = $_ -split '\s+'
                    if ($parts.Count -ge 2) {
                        [PSCustomObject] @{ Name = $parts[0]; Current = $parts[1]; Available = "Latest"; Source = ".NET Tools" }
                    }
                }
            }
        }
    }

    # Determine which package managers to use
    $managersToUse = @()
    
    if ($All) {
        # Use all detected package managers
        foreach ($mgr in $packageManagers.Keys) {
            if (Get-Command $packageManagers[$mgr].Command -ErrorAction SilentlyContinue) {
                $managersToUse += $mgr
            }
        }
    }
    elseif ($Sources.Count -gt 0) {
        # Use specified sources
        foreach ($source in $Sources) {
            if ($packageManagers.ContainsKey($source)) {
                if (Get-Command $packageManagers[$source].Command -ErrorAction SilentlyContinue) {
                    $managersToUse += $source
                }
                else {
                    Write-Color "⚠️ $source not found on system" Yellow
                }
            }
        }
    }
    else {
        # Default behavior - use common package managers
        $defaultSources = @('Winget', 'Scoop', 'Choco')
        foreach ($source in $defaultSources) {
            if ($packageManagers.ContainsKey($source) -and (Get-Command $packageManagers[$source].Command -ErrorAction SilentlyContinue)) {
                $managersToUse += $source
            }
        }
    }

    if ($managersToUse.Count -eq 0) {
        Write-Color "❌ No package managers found or specified!" Red
        Write-Color "Available sources: $($packageManagers.Keys -join ', ')" DarkGray
        return
    }

    Write-Color "`n🔍 Checking updates for: $($managersToUse -join ', ')" Cyan

    # Check for updates
    $results = @()
    foreach ($mgr in $managersToUse) {
        $config = $packageManagers[$mgr]
        Write-Color "Checking $mgr..." DarkGray
        
        try {
            $output = & $config.CheckCmd
            $hasUpdates = & $config.ParseUpdates -output $output
            $packages = if ($Comparison) { & $config.GetPackages -output $output } else { @() }
            
            $results += [PSCustomObject] @{
                Manager    = $mgr
                Output     = $output
                HasUpdates = $hasUpdates
                Packages   = $packages
            }
        }
        catch {
            Write-Color "⚠️ Error checking $mgr $($_.Exception.Message)" Yellow
            if ($DebugLog) {
                "ERROR checking $mgr`: $($_.Exception.Message)" | Out-File $reportPath -Append
            }
        }
    }

    # Display results
    Write-Color "`n📦 Update Summary:" Yellow
    $hasAnyUpdates = $false
    
    foreach ($result in $results) {
        if ($result.HasUpdates -or $Force) {
            Write-Color "📦 $($result.Manager): Updates available" Green
            $hasAnyUpdates = $true
            
            if ($Comparison -and $result.Packages.Count -gt 0) {
                Write-Color "   Packages to update:" DarkGray
                $result.Packages | ForEach-Object {
                    Write-Color "   • $($_.Name): $($_.Current) → $($_.Available)" Cyan
                }
            }
        }
        else {
            Write-Color "✅ $($result.Manager): Up to date" Green
        }
    }

    if (-not $hasAnyUpdates -and -not $Force) {
        Write-Color "`n✨ All specified sources are up to date!" Green
        return
    }

    if ($CheckOnly) {
        Write-Color "`n🔍 Check completed. Use without -CheckOnly to install updates." Yellow
        return
    }

    # Confirm updates
    if (-not $AutoYes -and -not $Fast) {
        $sourcesToUpdate = ($results | Where-Object { $_.HasUpdates -or $Force }).Manager -join ', '
        if (-not (Read-Host "`nProceed with updating $sourcesToUpdate? (y/N)") -eq 'y') {
            Write-Color "❌ Update cancelled by user." Red
            return
        }
    }

    # Perform updates
    Write-Color "`n🚀 Starting updates..." Green
    
    foreach ($result in $results) {
        if ($result.HasUpdates -or $Force) {
            $mgr = $result.Manager
            $config = $packageManagers[$mgr]
            
            Write-Color "📦 Updating $mgr packages..." Cyan
            try {
                & $config.UpdateCmd
                Write-Color "✅ $mgr updated successfully" Green
            }
            catch {
                Write-Color "❌ $mgr update failed: $($_.Exception.Message)" Red
                if ($DebugLog) {
                    "ERROR updating $mgr`: $($_.Exception.Message)" | Out-File $reportPath -Append
                }
            }
        }
    }

    Write-Color "`n🎉 Update process complete!" Green
    if ($DebugLog) {
        Write-Color "📑 Detailed log: $reportPath" DarkGray
    }
}
