# Footo Installer for PowerShell

# 1. Define Paths
$InstallDir = "$env:USERPROFILE\.footo"
$BinDir = "$InstallDir\bin"
$ProfileScript = "$InstallDir\footo-init.ps1"
$SourceExe = ".\dist\footo.exe"

# 2. Create Directories
if (-not (Test-Path -Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir | Out-Null
}
if (-not (Test-Path -Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir | Out-Null
}

# 3. Copy footo.exe
if (-not (Test-Path -Path $SourceExe)) {
    Write-Host "Error: footo.exe not found in .\dist directory." -ForegroundColor Red
    exit 1
}
Copy-Item -Path $SourceExe -Destination $BinDir -Force
Write-Host "Copied footo.exe to $BinDir" -ForegroundColor Green

# 4. Add to PATH
$CurrentUserPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentUserPath -notlike "*$BinDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$BinDir;$CurrentUserPath", "User")
    Write-Host "Added $BinDir to your PATH. Please restart your terminal for this to take effect." -ForegroundColor Yellow
} else {
    Write-Host "$BinDir is already in your PATH." -ForegroundColor Green
}

# 5. Create the profile script (footo-init.ps1)
$FunctionContent = @"
function footo {
    # This function calls the footo.exe and handles the 'run' command's output.
    $output = & footo.exe $args
    if ($args[0] -eq 'run' -and $LASTEXITCODE -eq 0) {
        # If the command was 'run' and successful, execute the output
        Invoke-Expression $output
    } else {
        # Otherwise, just print the output
        Write-Output $output
    }
}
"@
Set-Content -Path $ProfileScript -Value $FunctionContent
Write-Host "Created profile script at $ProfileScript" -ForegroundColor Green

# 6. Update PowerShell profile
$PsProfile = $PROFILE
if (-not (Test-Path $PsProfile)) {
    New-Item -Path $PsProfile -ItemType File -Force | Out-Null
}
$ProfileContent = Get-Content $PsProfile
$SourceLine = ". \"$ProfileScript\""
if ($ProfileContent -notcontains $SourceLine) {
    Add-Content -Path $PsProfile -Value "`n# Initialize Footo`n$SourceLine"
    Write-Host "Added Footo initialization to your PowerShell profile." -ForegroundColor Yellow
    Write-Host "Please restart your terminal to complete the installation." -ForegroundColor Yellow
} else {
    Write-Host "Footo is already initialized in your PowerShell profile." -ForegroundColor Green
}

Write-Host "`nInstallation complete!" -ForegroundColor Cyan
