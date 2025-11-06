#!/bin/bash

# Footo Installer for Bash/Zsh

# 1. Define Paths
InstallDir="$HOME/.footo"
BinDir="$InstallDir/bin"
ProfileScript="$InstallDir/footo-init.sh"
SourceExe="./dist/footo" # Assumes a Linux/macOS executable

# 2. Create Directories
mkdir -p "$BinDir"

# 3. Copy footo executable
if [ ! -f "$SourceExe" ]; then
    echo "Error: 'footo' executable not found in ./dist directory." >&2
    echo "Please run 'pyinstaller --onefile footo.py' on a Linux or macOS machine first." >&2
    exit 1
fi
cp "$SourceExe" "$BinDir/footo"
chmod +x "$BinDir/footo"
echo "Copied 'footo' executable to $BinDir"

# 4. Add to PATH
# Detect shell profile
if [ -n "$BASH_VERSION" ]; then
    ProfileFile="$HOME/.bashrc"
elif [ -n "$ZSH_VERSION" ]; then
    ProfileFile="$HOME/.zshrc"
else
    ProfileFile="$HOME/.profile"
fi

PathLine="export PATH=\"$BinDir:\$PATH\""
if ! grep -q "$PathLine" "$ProfileFile"; then
    echo -e "\n# Add Footo to PATH\n$PathLine" >> "$ProfileFile"
    echo "Added $BinDir to your PATH in $ProfileFile."
    echo "Please restart your terminal for this to take effect."
else
    echo "$BinDir is already in your PATH."
fi

# 5. Create the profile script (footo-init.sh)
FunctionContent='''
footo() {
    # This function calls the footo executable and handles the 'run' command's output.
    if [[ "$1" == "run" ]]; then
        # If the command is 'run', evaluate the output to source the script
        eval "$(footo \"$@\")"
    else
        # Otherwise, just execute the script and print the output
        command footo "$@"
    fi
}
'''

echo "$FunctionContent" > "$ProfileScript"
echo "Created profile script at $ProfileScript"

# 6. Update shell profile
SourceLine="source \"$ProfileScript\""
if ! grep -q "$SourceLine" "$ProfileFile"; then
    echo -e "\n# Initialize Footo\n$SourceLine" >> "$ProfileFile"
    echo "Added Footo initialization to your shell profile."
    echo "Please restart your terminal to complete the installation."
else
    echo "Footo is already initialized in your shell profile."
fi

echo -e "\nInstallation complete!"
