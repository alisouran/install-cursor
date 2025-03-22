#!/bin/bash

# Exit on error
set -e

# Function to get latest version info
get_latest_version() {
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        echo "curl is required but not installed. Installing curl..."
        sudo apt-get update && sudo apt-get install -y curl
    fi

    # Get the latest version information
    local VERSION_INFO
    VERSION_INFO=$(curl -s "https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable")
    
    # Extract download URL and version using grep and cut
    # Note: Using grep/cut instead of jq to avoid additional dependencies
    local DOWNLOAD_URL
    DOWNLOAD_URL=$(echo "$VERSION_INFO" | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4)
    
    local VERSION
    VERSION=$(echo "$VERSION_INFO" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$DOWNLOAD_URL" ] || [ -z "$VERSION" ]; then
        echo "Error: Failed to get latest version information"
        exit 1
    fi
    
    echo "$DOWNLOAD_URL|$VERSION"
}

# Get latest version info
VERSION_INFO=$(get_latest_version)
DOWNLOAD_URL=$(echo "$VERSION_INFO" | cut -d'|' -f1)
VERSION=$(echo "$VERSION_INFO" | cut -d'|' -f2)

CURSOR_APPIMAGE="Cursor-${VERSION}-x86_64.AppImage"
CURSOR_NAME="Cursor"

echo "Cursor AppImage Installer for Ubuntu Linux"
echo "==========================================="
echo "Latest version: $VERSION"
echo "Downloading $CURSOR_APPIMAGE..."

# Download the AppImage
if ! curl -L "$DOWNLOAD_URL" -o "$CURSOR_APPIMAGE"; then
    echo "Error: Failed to download Cursor AppImage"
    exit 1
fi

# Make AppImage executable
echo "Making AppImage executable..."
chmod +x "./$CURSOR_APPIMAGE"

# Create applications directory if it doesn't exist
APPS_DIR="$HOME/Applications"
if [ ! -d "$APPS_DIR" ]; then
    echo "Creating Applications directory..."
    mkdir -p "$APPS_DIR"
fi

# Move AppImage to applications directory
echo "Moving $CURSOR_APPIMAGE to $APPS_DIR..."
cp "./$CURSOR_APPIMAGE" "$APPS_DIR/$CURSOR_APPIMAGE"
chmod +x "$APPS_DIR/$CURSOR_APPIMAGE"  # Ensure it's executable after copying

# Check for FUSE availability
echo "Checking FUSE availability..."
if ! grep -q "^fuse" /etc/mtab && ! grep -q "^fusectl" /proc/mounts; then
    echo "FUSE doesn't appear to be mounted. Trying to load the FUSE module..."
    sudo modprobe fuse
    # Check if FUSE is now available
    if ! grep -q "^fuse" /etc/mtab && ! grep -q "^fusectl" /proc/mounts; then
        echo "Warning: FUSE still doesn't appear to be available. Installing FUSE packages..."
        sudo apt-get update
        sudo apt-get install -y fuse libfuse2 fuse3 libfuse3-3
    fi
fi

# Extract the AppImage to fix the Chrome sandbox issue
echo "Extracting AppImage to fix Chrome sandbox permissions..."
EXTRACT_DIR="$APPS_DIR/cursor-extracted"

# Clean up previous extraction if it exists
if [ -d "$EXTRACT_DIR" ]; then
    echo "Removing previous extraction..."
    rm -rf "$EXTRACT_DIR"
fi

mkdir -p "$EXTRACT_DIR"
cd "$EXTRACT_DIR"

# Try extraction with better error handling
echo "Extracting AppImage..."
if ! "$APPS_DIR/$CURSOR_APPIMAGE" --appimage-extract; then
    echo "Error: Failed to extract AppImage with the --appimage-extract method."
    echo "Trying alternative extraction method..."
    
    # Alternative method: Run the AppImage in a temporary directory and extract manually
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    echo "Attempting to mount the AppImage..."
    if ! "$APPS_DIR/$CURSOR_APPIMAGE" --appimage-mount; then
        echo "Error: Unable to mount or extract the AppImage. This may be due to FUSE issues."
        echo "Trying to install additional FUSE dependencies..."
        sudo apt-get update
        sudo apt-get install -y fuse libfuse2 fuse3 libfuse3-3
        
        echo "Please run the script again after installation."
        exit 1
    fi
    
    # If we get here, we've successfully mounted the AppImage
    # Clean up and exit
    echo "Please run the script again after installation of FUSE."
    exit 1
fi

# We should be back in the extract directory now
cd "$EXTRACT_DIR"

# Fix sandbox permissions
echo "Fixing Chrome sandbox permissions (requires sudo)..."
SANDBOX_PATH="$EXTRACT_DIR/squashfs-root/usr/share/cursor/chrome-sandbox"
if [ -f "$SANDBOX_PATH" ]; then
    sudo chown root:root "$SANDBOX_PATH"
    sudo chmod 4755 "$SANDBOX_PATH"
    echo "Chrome sandbox permissions fixed."
else
    echo "Warning: Could not find chrome-sandbox at expected path."
    # Try to find it elsewhere
    SANDBOX_PATHS=$(find "$EXTRACT_DIR/squashfs-root" -name "chrome-sandbox" 2>/dev/null)
    if [ -n "$SANDBOX_PATHS" ]; then
        echo "Found alternative chrome-sandbox location(s):"
        echo "$SANDBOX_PATHS"
        for SANDBOX in $SANDBOX_PATHS; do
            echo "Fixing permissions for $SANDBOX"
            sudo chown root:root "$SANDBOX"
            sudo chmod 4755 "$SANDBOX"
        done
    fi
fi

# Create a script to launch the extracted version
LAUNCH_SCRIPT="$APPS_DIR/run-cursor.sh"
cat > "$LAUNCH_SCRIPT" << EOF
#!/bin/bash
"$EXTRACT_DIR/squashfs-root/AppRun" "\$@"
EOF
chmod +x "$LAUNCH_SCRIPT"

# Create desktop entry
echo "Creating desktop shortcut..."
DESKTOP_FILE="$HOME/.local/share/applications/cursor.desktop"
mkdir -p "$(dirname "$DESKTOP_FILE")"

# Find icon path - it might be in different locations
ICON_PATH=$(find "$EXTRACT_DIR/squashfs-root" -name "cursor.png" -path "*/icons/hicolor/256x256/apps/*" 2>/dev/null | head -n 1)
if [ -z "$ICON_PATH" ]; then
    # Fallback to any cursor icon we can find
    ICON_PATH=$(find "$EXTRACT_DIR/squashfs-root" -name "cursor.png" 2>/dev/null | head -n 1)
    if [ -z "$ICON_PATH" ]; then
        # Ultimate fallback
        ICON_PATH="$EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor/256x256/apps/cursor.png"
    fi
fi

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Cursor
Comment=AI-first code editor
Exec="$LAUNCH_SCRIPT" %U
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=Cursor
MimeType=text/plain;inode/directory;
EOF

# Update desktop database
echo "Updating desktop database..."
update-desktop-database "$HOME/.local/share/applications"

# Check for common AppImage dependencies on Ubuntu
echo "Checking for required dependencies..."
missing_deps=()

# Updated Ubuntu dependencies (fixed package names)
for dep in fuse libfuse libglx-mesa0 libegl1 libxcb-xinerama0 libxkbcommon-x11-0 libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libatspi2.0-0 libdrm2 libgbm1; do
    if ! dpkg -s $dep >/dev/null 2>&1; then
        missing_deps+=($dep)
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "Missing dependencies: ${missing_deps[*]}"
    echo "Installing missing dependencies (requires sudo)..."
    sudo apt-get update
    sudo apt-get install -y ${missing_deps[*]} || true
    
    # If any packages failed, try alternative names
    echo "Some packages may not have been installed. Trying alternative package names..."
    echo "Installing FUSE support..."
    sudo apt-get install -y fuse3 libfuse3-3 fuse libfuse2 || true
    
    echo "Installing OpenGL/Mesa libraries..."
    sudo apt-get install -y libgl1-mesa-dri mesa-utils libgl1 || true
    
    echo "Installing other required dependencies..."
    sudo apt-get install -y libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 xdg-utils libglib2.0-0 || true
fi

# Create a symlink in /usr/local/bin (requires sudo)
echo "Would you like to create a symlink in /usr/local/bin? (y/n)"
read -r create_symlink
if [[ "$create_symlink" =~ ^[Yy]$ ]]; then
    echo "Creating symlink in /usr/local/bin (requires sudo)..."
    sudo ln -sf "$LAUNCH_SCRIPT" /usr/local/bin/cursor
    echo "You can now run Cursor by typing 'cursor' in terminal."
fi

# Test running the extracted AppRun
echo "Testing Cursor execution..."
echo "The application will attempt to launch. Press Ctrl+C if it doesn't open within 10 seconds."
echo "-------- BEGIN APPLICATION OUTPUT --------"
"$LAUNCH_SCRIPT" 2>&1 &
APP_PID=$!
sleep 10
if kill -0 $APP_PID 2>/dev/null; then
    echo "Cursor is running successfully! Closing test instance..."
    kill $APP_PID 2>/dev/null || true
else
    echo "WARNING: The application appears to have exited early."
fi
echo "--------- END APPLICATION OUTPUT ---------"

echo "Installation complete!"
echo ""
echo "You can launch Cursor from your applications menu"
echo "or by running: $LAUNCH_SCRIPT"
echo ""
echo "If you're experiencing issues:"
echo "1. Try running manually: $EXTRACT_DIR/squashfs-root/AppRun"
echo "2. Check for further error messages by running $LAUNCH_SCRIPT in terminal"
echo "3. For FUSE issues run: sudo apt-get install fuse libfuse2 fuse3 libfuse3-3"
echo "4. If the AppImage won't extract, you might need to run it directly from $APPS_DIR/$CURSOR_APPIMAGE" 