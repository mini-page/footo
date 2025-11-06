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
    if (@($args).Count -gt 0) {
        if ($args[0] -eq 'run' -and $LASTEXITCODE -eq 0) {
            # If the command was 'run' and successful, execute the output
            Invoke-Expression $output
        } else {
            # Otherwise, just print the output
            Write-Output $output
        }
    } else {
        Write-Output $output
    }
}
"@
Set-Content -Path $ProfileScript -Value $FunctionContent
Write-Host "Created profile script at $ProfileScript" -ForegroundColor Green

# 6. Manual Instruction for PowerShell profile update
Write-Host "`nIMPORTANT: Automated PowerShell profile update failed." -ForegroundColor Red
Write-Host "Please manually add the following line to your PowerShell profile (usually at $PROFILE):" -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
Write-Host ". 'C:\Users\umang\.footo\footo-init.ps1'" -ForegroundColor Cyan
Write-Host "" -ForegroundColor Yellow
Write-Host "You can open your profile by typing 'notepad $PROFILE' in PowerShell." -ForegroundColor Yellow
Write-Host "After adding the line, save the file and restart your terminal." -ForegroundColor Yellow

Write-Host "`nInstallation complete!" -ForegroundColor Cyan
