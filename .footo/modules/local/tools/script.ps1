# ==========================================================
# Development Tools Information
# ==========================================================
function tools {
    <#
    .SYNOPSIS
    Comprehensive development and system tools checker
    .DESCRIPTION
    Shows installed tools, aliases, functions, versions, and available updates
    .PARAMETER Install
    Install a tool via Scoop
    .PARAMETER Check
    Specify a subset of tools to check
    .PARAMETER Export
    Export the report to a file
    .PARAMETER Updates
    Check if updates are available for installed tools
    .PARAMETER NoVersion
    Skip version checking for faster execution
    #>
    param(
        [string]$Install,
        [string[]]$Check,
        [string]$Export,
        [switch]$Updates,
        [switch]$NoVersion
    )

    # Start timing
    $script:toolsStartTime = Get-Date

    # ----------------------------
    # Tool list
    # ----------------------------
    $commonTools = @(
        "bat", "btop", "broot", "dog", "dust", "eza", "fclones", "fzf", "gdu", "gping",
        "hyperfine", "jq", "lazygit", "oh-my-posh", "procs", "rg", "ffmpeg", "tig", "tree",
        "tldr", "yq", "delta", "yt-dlp", "zoxide", "fx", "mods",
        "git", "python", "node", "npm", "flutter", "gemini", "go", "rustc", "cargo", "java", "javac",
        "dotnet", "kubectl", "helm", "docker", "docker-compose", "vscode", "code", "psql", "mysql",
        "wget", "curl", "aria2", "gh", "aws", "az", "gcloud", "neofetch", "htop", "tmux", "screen", "bandwhich", "7zip", "onefetch", "starship",
        "nmap", "ping", "tracert", "ipconfig", "dig", "nslookup"
    )

    $toolsToCheck = if ($Check) { $commonTools | Where-Object { $_ -in $Check } } else { $commonTools }

    # ----------------------------
    # Handle installation
    # ----------------------------
    if ($Install) {
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            Write-Color "📦 Installing $Install via Scoop..." Cyan
            try { scoop install $Install } catch { Write-Color "❌ Failed: $($_.Exception.Message)" Red }
        }
        else {
            Write-Color "Scoop not found. Install first: https://scoop.sh" Red
        }
        return
    }

    # ----------------------------
    # Pre-cache all commands, aliases, and functions for speed
    # ----------------------------
    Write-Color "`n🔧 Development & System Tools Status" Yellow
    Write-Color "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" DarkGray
    Write-Color "⏱️ Scanning tools..." DarkGray

    # More reliable command detection - check each tool individually
    $allCommands = @{}
    $allAliases = @{}
    $allFunctions = @{}

    # Quick pre-check for each tool
    foreach ($tool in $toolsToCheck) {
        try {
            # Try Get-Command first (most reliable)
            $cmd = Get-Command $tool -ErrorAction SilentlyContinue
            if ($cmd) {
                $allCommands[$tool] = $cmd
                continue
            }
            
            # Check aliases
            $alias = Get-Alias $tool -ErrorAction SilentlyContinue  
            if ($alias) {
                $allAliases[$tool] = $alias
                continue
            }
            
            # Check functions
            $func = Get-Command $tool -CommandType Function -ErrorAction SilentlyContinue
            if ($func) {
                $allFunctions[$tool] = $func
            }
        }
        catch {
            # Tool not found, continue to next
            continue
        }
    }

    # ----------------------------
    # Process tools in parallel (PS 7+) or optimized sequential (PS 5.1)
    # ----------------------------
    $report = @()

    if ($PSVersionTable.PSVersion.Major -ge 7 -and -not $NoVersion) {
        # PowerShell 7+ parallel processing
        $report = $toolsToCheck | ForEach-Object -Parallel {
            $tool = $_
            $allCommands = $using:allCommands
            $allAliases = $using:allAliases  
            $allFunctions = $using:allFunctions
            $NoVersion = $using:NoVersion
            
            $status = ""
            $version = ""
            
            if ($allCommands.ContainsKey($tool)) {
                $status = "✅ Installed"
                if (-not $NoVersion) {
                    try {
                        $versionOutput = $null
                        $job = Start-Job -ScriptBlock {
                            param($t)
                            try {
                                $v = & $t --version 2>$null
                                if (-not $v) { $v = & $t -v 2>$null }
                                if (-not $v -and $t -eq "code") { $v = & $t --version 2>$null }
                                return $v
                            }
                            catch { return $null }
                        } -ArgumentList $tool
                        
                        $job | Wait-Job -Timeout 2 | Out-Null
                        $versionOutput = Receive-Job $job -ErrorAction SilentlyContinue
                        Remove-Job $job -Force -ErrorAction SilentlyContinue
                        
                        if ($versionOutput) {
                            $version = ($versionOutput | Select-Object -First 1).ToString().Trim()
                            # Clean up version string
                            if ($version.Length -gt 50) { $version = $version.Substring(0, 50) + "..." }
                        }
                        else { $version = "✓" }
                    }
                    catch { $version = "✓" }
                }
                else { $version = "✓" }
            }
            elseif ($allAliases.ContainsKey($tool)) {
                $status = "🔗 Alias"
                $version = $allAliases[$tool].Definition
                if ($version.Length -gt 30) { $version = $version.Substring(0, 30) + "..." }
            }
            elseif ($allFunctions.ContainsKey($tool)) {
                $status = "🔧 Function"
                $version = "Available"
            }
            else {
                $status = "❌ Missing"
                $version = ""
            }

            [PSCustomObject] @{
                Tool        = $tool
                Status      = $status
                Version     = $version
                IsInstalled = $status -ne "❌ Missing"
            }
        } -ThrottleLimit 10
    }
    else {
        # Sequential processing (PS 5.1 or when NoVersion specified)
        $report = foreach ($tool in $toolsToCheck) {
            $status = ""
            $version = ""
            $isInstalled = $false
            
            if ($allCommands.ContainsKey($tool)) {
                $isInstalled = $true
                $status = "✅ Installed"
                if (-not $NoVersion) {
                    # Fast version check with timeout
                    try {
                        $job = Start-Job -ScriptBlock {
                            param($t)
                            try {
                                $v = & $t --version 2>$null
                                if (-not $v) { $v = & $t -v 2>$null }
                                return $v
                            }
                            catch { return $null }
                        } -ArgumentList $tool
                        
                        if (Wait-Job $job -Timeout 1) {
                            $versionOutput = Receive-Job $job -ErrorAction SilentlyContinue
                            if ($versionOutput) {
                                $version = ($versionOutput | Select-Object -First 1).ToString().Trim()
                                if ($version.Length -gt 50) { $version = $version.Substring(0, 50) + "..." }
                            }
                            else { $version = "✓" }
                        }
                        else { $version = "✓" }
                        Remove-Job $job -Force -ErrorAction SilentlyContinue
                    }
                    catch { $version = "✓" }
                }
                else { $version = "✓" }
            }
            elseif ($allAliases.ContainsKey($tool)) {
                $isInstalled = $true
                $status = "🔗 Alias"
                $version = $allAliases[$tool].Definition
                if ($version.Length -gt 30) { $version = $version.Substring(0, 30) + "..." }
            }
            elseif ($allFunctions.ContainsKey($tool)) {
                $isInstalled = $true
                $status = "🔧 Function"
                $version = "Available"
            }
            else {
                $status = "❌ Missing"
                $version = ""
            }

            [PSCustomObject] @{
                Tool        = $tool
                Status      = $status
                Version     = $version
                IsInstalled = $isInstalled
            }
        }
    }

    # Separate installed and missing
    $installed = $report | Where-Object { $_.IsInstalled } | ForEach-Object { $_.Tool }
    $missing = $report | Where-Object { -not $_.IsInstalled } | ForEach-Object { $_.Tool }

    # ----------------------------
    # Display optimized table
    # ----------------------------
    $report | Select-Object Tool, Status, Version | Format-Table -AutoSize

    Write-Color "`n📊 Summary: $($installed.Count) present, $($missing.Count) missing" Cyan

    # ----------------------------
    # Fast Updates check (parallel where possible)
    # ----------------------------
    if ($Updates -and $installed.Count -gt 0) {
        Write-Color "`n⬆️ Checking updates..." Yellow
        
        # Check package managers availability once
        $hasScoop = $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
        $hasChoco = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)  
        $hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

        if ($hasScoop) {
            try {
                Write-Color "🔍 Checking Scoop updates..." DarkGray
                $scoopStatus = scoop status 2>$null
                if ($scoopStatus) {
                    $scoopOutdated = $scoopStatus | Where-Object { $_ -match "^\s*\S+\s+" } | ForEach-Object {
                        ($_ -split '\s+')[0]
                    }
                    foreach ($tool in $scoopOutdated) {
                        if ($tool -in $installed) {
                            Write-Color "⬆️ $tool (Scoop) has updates available" Yellow
                        }
                    }
                }
            }
            catch { }
        }

        if ($hasChoco) {
            try {
                Write-Color "🔍 Checking Chocolatey updates..." DarkGray
                $chocoOutdated = choco outdated --limit-output 2>$null | ForEach-Object {
                    if ($_ -match '^([^|]+)') { $matches[1] }
                }
                foreach ($tool in $chocoOutdated) {
                    if ($tool -in $installed) {
                        Write-Color "⬆️ $tool (Choco) has updates available" Yellow
                    }
                }
            }
            catch { }
        }

        if ($hasWinget) {
            try {
                Write-Color "🔍 Checking Winget updates..." DarkGray
                $wingetCheck = winget upgrade --accept-source-agreements 2>$null
                if ($wingetCheck) {
                    $wingetOutdated = $wingetCheck | Where-Object { $_ -match '^\S+\s+\S+\s+\S+\s+\S+' } | ForEach-Object {
                        ($_ -split '\s+')[0]
                    }
                    foreach ($tool in $wingetOutdated) {
                        if ($tool -in $installed) {
                            Write-Color "⬆️ $tool (Winget) has updates available" Yellow
                        }
                    }
                }
            }
            catch { }
        }
    }

    # ----------------------------
    # Export report
    # ----------------------------
    if ($Export) {
        $report | Select-Object Tool, Status, Version | Export-Csv $Export -NoTypeInformation -Encoding UTF8
        Write-Color "`n📄 Report exported to $Export" Green
    }

    if ($NoVersion) {
        Write-Color "`n💡 Tip: Run without -NoVersion to see detailed version info (slower)" DarkGray
    }

    # ----------------------------
    # Display missing tools suggestions
    # ----------------------------
    if ($missing.Count -gt 0 -and $missing.Count -le 10) {
        Write-Color "`n💡 Quick install suggestions:" DarkGray
        foreach ($tool in $missing[0..9]) {
            # Limit to first 10
            if (Get-Command scoop -ErrorAction SilentlyContinue) {
                Write-Color "   scoop install $tool" DarkGray
            }
            elseif (Get-Command winget -ErrorAction SilentlyContinue) {
                Write-Color "   winget install $tool" DarkGray  
            }
            elseif (Get-Command choco -ErrorAction SilentlyContinue) {
                Write-Color "   choco install $tool" DarkGray
            }
        }
        if ($missing.Count -gt 10) {
            Write-Color "   ... and $($missing.Count - 10) more" DarkGray
        }
    }

    # ----------------------------
    # Performance timing
    # ----------------------------
    if ($script:toolsStartTime) {
        $elapsed = (Get-Date) - $script:toolsStartTime
        Write-Color "`n⚡ Completed in $([math]::Round($elapsed.TotalSeconds, 1))s" DarkGray
        Remove-Variable -Name toolsStartTime -Scope Script -ErrorAction SilentlyContinue
    }
}