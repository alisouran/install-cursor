# Cursor Installer for Linux 🐧

This script automatically downloads and installs the latest version of [Cursor](https://www.cursor.com), an AI-first code editor, on Linux systems.

## 🚀 Features

- Fetches the latest version directly from Cursor's official API
- Installs required dependencies (FUSE, libgtk, etc.)
- Extracts the AppImage to fix Chrome sandbox permissions
- Creates a desktop shortcut and optional terminal command (`cursor`)

## 📦 Quick Install

Run this one-liner in your terminal:

```bash
bash <(curl -s https://raw.githubusercontent.com/alisouran/install-cursor/main/install.sh)
```

> ⚠️ You might be prompted for your password during installation (used for `sudo`).

## 🛠 Requirements

- Ubuntu or Debian-based Linux distro
- Internet connection
- `curl` (automatically installed if missing)
- Various system libraries (automatically installed if missing):
  - FUSE and related packages (fuse, libfuse2, fuse3, libfuse3-3)
  - Graphics libraries (libglx-mesa0, libegl1, libgbm1, libdrm2)
  - X11 libraries (libxcb-xinerama0, libxkbcommon-x11-0, libxss1, libxtst6)
  - GTK and system libraries (libgtk-3-0, libnotify4, libnss3, libatspi2.0-0)
  - Other utilities (xdg-utils)

## 📁 What it does

- Downloads the latest `Cursor-x86_64.AppImage`
- Makes it executable and moves it to `~/Applications`
- Extracts it to fix sandbox permissions (required for Chrome-based apps)
- Creates a launcher script: `~/Applications/run-cursor.sh`
- Creates a `.desktop` file for launching from the app menu with:
  - File associations for text files and directories
  - Proper application categorization
  - High-resolution icon integration
- Optionally creates a symlink in `/usr/local/bin` so you can launch with `cursor`
- Performs a test run to verify the installation

## 🐛 Troubleshooting

If the app doesn't run properly:

1. Check and install FUSE:

   ```bash
   sudo apt-get install fuse libfuse2 fuse3 libfuse3-3
   ```

2. Try launching manually:

   ```bash
   ~/Applications/cursor-extracted/squashfs-root/AppRun
   ```

3. Check terminal output:
   ```bash
   ~/Applications/run-cursor.sh
   ```

## 🔍 Installation Verification

The installer includes an automatic test run that will:

1. Launch Cursor in the background
2. Monitor its execution for 10 seconds
3. Provide feedback if the application exits unexpectedly

If you encounter any issues during installation, the script will attempt alternative methods including:

- Trying different FUSE mounting approaches
- Searching for alternative chrome-sandbox locations
- Installing alternative package versions when needed
