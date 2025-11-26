#!/bin/bash

# Check Ubuntu version and exit if 24.04
UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null)
if [ "$UBUNTU_VERSION" = "24.04" ]; then
    echo "-------------------------------------"
    echo "==============================="
    echo "❌ This script is for Ubuntu 22.04 only."
    echo "==============================="    
    echo "You are running Ubuntu 24.04."
    echo "This script is for Ubuntu 22.04 only."
    echo "Please use the installer for Ubuntu 24.04:"
    echo "https://joplinapp.org/#download"
    echo "-------------------------------------"
    exit 1
fi

# --- Global Variables ---
JOPLIN_INSTALL_DIR="/opt/Joplin"
APPIMAGE_FILENAME="Joplin.AppImage"
ICON_FILENAME_ON_DISK="joplin-icon.png"

APPIMAGE_PATH="${JOPLIN_INSTALL_DIR}/${APPIMAGE_FILENAME}"
ICON_PATH="${JOPLIN_INSTALL_DIR}/${ICON_FILENAME_ON_DISK}"
DESKTOP_ENTRY_PATH="/usr/share/applications/joplin.desktop"

# --- Utility Functions ---
print_error() {
    echo "==============================="
    echo "❌ $1"
    echo "==============================="
}

print_success() {
    echo "==============================="
    echo "✅ $1"
    echo "==============================="
}

print_info() {
    echo "==============================="
    echo "ℹ️ $1"
    echo "==============================="
}

ask_for_restart() {
    echo ""
    echo "🔄 For the best experience, we recommend refreshing your desktop:"
    echo "   1. Log out and log back in (recommended)"
    echo "   2. Restart your computer (best option): sudo reboot"
    echo "   3. Continue without restart (icons may not update immediately)"
    echo "⚠️ Make sure to save your work before restarting!"
}

# --- Dependency Management ---
install_dependencies() {
    local deps=("curl" "jq" "wget" "figlet")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "📦 $dep is not installed. Installing..."
            sudo apt-get update
            sudo apt-get install -y "$dep"
        fi
    done
    
    if ! dpkg -s libfuse2 &> /dev/null; then
        echo "📦 libfuse2 is not installed. Installing..."
        sudo apt-get update
        sudo apt-get install -y libfuse2
    fi
}

# --- Download Latest Joplin AppImage Function ---
download_latest_joplin_appimage() {
    API_URL="https://api.github.com/repos/laurent22/joplin/releases/latest"
    DOWNLOAD_PATH="/tmp/latest-Joplin.AppImage"
    
    FINAL_URL=$(curl -s "$API_URL" | jq -r '.assets[] | select(.name | test("AppImage$")) | .browser_download_url' | head -n 1)

    if [ -z "$FINAL_URL" ] || [ "$FINAL_URL" = "null" ]; then
        print_error "Could not get the AppImage URL from Joplin API."
        return 1
    fi

    echo "⬇️ Downloading latest Joplin AppImage from: $FINAL_URL"
    wget -q -O "$DOWNLOAD_PATH" "$FINAL_URL"

    if [ $? -eq 0 ] && [ -s "$DOWNLOAD_PATH" ]; then
        echo "✅ Downloaded latest Joplin AppImage successfully!"
        echo "$DOWNLOAD_PATH"
        return 0
    else
        print_error "Failed to download the AppImage."
        return 1
    fi
}

get_appimage_path() {
    local operation="$1"  # "install" or "update"
    local action_text=""
    
    if [ "$operation" = "update" ]; then
        action_text="new Joplin AppImage"
    else
        action_text="Joplin AppImage"
    fi
    
    echo "⬇️ Automatically downloading the latest ${action_text}..." >&2
    local joplin_download_path=""
    
    joplin_download_path=$(download_latest_joplin_appimage 2>/dev/null | tail -n 1)
    
    if [ $? -eq 0 ] && [ -f "$joplin_download_path" ]; then
        echo "✅ Auto-download successful!" >&2
    else
        print_error "Auto-download failed!" >&2
        echo "" >&2
        echo "📋 Let's try manual download instead:" >&2
        echo "1. Visit: https://joplinapp.org/#download" >&2
        echo "2. Download the Joplin AppImage file for Linux" >&2
        echo "3. Provide the full path to the downloaded .AppImage file below" >&2
        echo "" >&2
        echo "⚠️ Please provide a .AppImage file, NOT an icon file (.png)" >&2
        echo "" >&2
        
        while true; do
            if [ "$operation" = "update" ]; then
                read -rp "📂 Enter the full path to your downloaded Joplin AppImage: " joplin_download_path >&2
            else
                read -rp "📂 Enter the full path to your downloaded Joplin AppImage: " joplin_download_path >&2
            fi
            
            if [ -f "$joplin_download_path" ] && [[ "$joplin_download_path" =~ \.AppImage$ ]]; then
                echo "✅ Valid AppImage file found!" >&2
                break
            elif [ ! -f "$joplin_download_path" ]; then
                echo "❌ File not found. Check path and try again." >&2
            elif [[ ! "$joplin_download_path" =~ \.AppImage$ ]]; then
                echo "❌ Invalid file type. Please provide a .AppImage file, not: $(basename "$joplin_download_path")" >&2
            else
                echo "❌ Unknown error. Try again." >&2
            fi
            
            echo "Try another path? (y/n)" >&2
            read -r retry_choice >&2
            if [[ ! "$retry_choice" =~ ^[Yy]$ ]]; then
                print_error "Installation cancelled by user." >&2
                exit 1
            fi
        done
    fi
    
    echo "$joplin_download_path"
}

process_appimage() {
    local source_path="$1"
    local operation="$2"
    
    if [ ! -f "$source_path" ]; then
        print_error "AppImage file not found: $source_path"
        exit 1
    fi
    
    if [[ ! "$source_path" =~ \.AppImage$ ]]; then
        print_error "Invalid file type. Expected .AppImage file, got: $(basename "$source_path")"
        exit 1
    fi
    
    if ! file "$source_path" | grep -q "executable"; then
        print_error "Provided file does not appear to be a valid executable AppImage."
        print_info "File info: $(file "$source_path")"
        exit 1
    fi
    
    echo "✅ AppImage validation passed: $(basename "$source_path")"
    
    if [ "$operation" = "update" ]; then
        echo "🗑️ Removing old Joplin AppImage at $APPIMAGE_PATH..."
        sudo rm -f "$APPIMAGE_PATH"
        if [ $? -ne 0 ]; then
            print_error "Failed to remove old AppImage. Check permissions."
            exit 1
        fi
        echo "✅ Old AppImage removed successfully."
    fi

    echo "📦 Moving Joplin AppImage to $APPIMAGE_PATH..."
    sudo mv "$source_path" "$APPIMAGE_PATH"
    if [ $? -ne 0 ]; then
        print_error "Failed to move AppImage. Check URL and permissions."
        exit 1
    fi
    echo "✅ Joplin AppImage moved successfully."

    echo "🔧 Setting permissions..."
    sudo chmod -R 755 "$JOPLIN_INSTALL_DIR"
    sudo chmod +x "$APPIMAGE_PATH"
    if [ $? -ne 0 ]; then
        print_error "Failed to set permissions. Check system configuration."
        exit 1
    fi
    echo "✅ Permissions set successfully."
}

installJoplin() {
    if ! [ -f "$APPIMAGE_PATH" ]; then
        figlet -f slant "Install Joplin"
        echo "💿 Installing Joplin AppImage on Ubuntu 22.04..."
        
        install_dependencies
        
        local joplin_download_path=$(get_appimage_path "install")
        
        local icon_url="https://raw.githubusercontent.com/hieutt192/Joplin-ubuntu/main/images/joplin-icon.png"
        
        echo "📁 Creating installation directory ${JOPLIN_INSTALL_DIR}..."
        sudo mkdir -p "$JOPLIN_INSTALL_DIR"
        if [ $? -ne 0 ]; then
            print_error "Failed to create installation directory. Check permissions."
            exit 1
        fi
        echo "✅ Installation directory created."

        process_appimage "$joplin_download_path" "install"

        echo "🎨 Downloading Joplin icon to $ICON_PATH..."
        sudo curl -L "$icon_url" -o "$ICON_PATH"

        echo "🖥️ Creating .desktop entry for Joplin..."
        sudo tee "$DESKTOP_ENTRY_PATH" >/dev/null <<EOL
[Desktop Entry]
Name=Joplin
Exec=$APPIMAGE_PATH --no-sandbox
Icon=$ICON_PATH
Type=Application
Categories=Utility;TextEditor;
MimeType=text/markdown;
EOL

        echo "🔧 Setting desktop entry permissions..."
        sudo chmod 644 "$DESKTOP_ENTRY_PATH"
        if [ $? -ne 0 ]; then
            print_error "Failed to set desktop entry permissions."
            exit 1
        fi
        echo "✅ Desktop entry permissions set."

        print_success "Joplin installation complete. Find it in your application menu."
        echo ""
        echo "📝 Notes:"
        echo "   • Launch Joplin via application menu or run:"
        echo "     $APPIMAGE_PATH --no-sandbox"

        ask_for_restart
    else
        print_info "Joplin is already installed at $APPIMAGE_PATH. To update, please choose the update option."
    fi
}

updateJoplin() {
    if [ -f "$APPIMAGE_PATH" ]; then
        figlet -f slant "Update Joplin"
        echo "🆙 Updating Joplin AppImage..."
        
        install_dependencies
        
        local joplin_download_path=$(get_appimage_path "update")
        
        process_appimage "$joplin_download_path" "update"

        print_success "Joplin update complete. Restart Joplin to apply changes."
        echo ""
        echo "📝 Notes:"
        echo "   • Your notes and settings will be preserved."
    else
        print_error "Joplin is not installed. Please run the installer first."
    fi
}

uninstallJoplin() {
    figlet -f slant "Uninstall Joplin"
    echo "🗑️ Uninstalling Joplin AppImage from Ubuntu..."
    
    if [ ! -f "$APPIMAGE_PATH" ] && [ ! -f "$DESKTOP_ENTRY_PATH" ]; then
        print_info "Joplin does not appear to be installed."
        echo "Files checked:"
        echo "  - $APPIMAGE_PATH"
        echo "  - $DESKTOP_ENTRY_PATH"
        return 0
    fi
    
    echo "⚠️ This will remove Joplin AppImage and desktop entry."
    echo "⚠️ Your notes stored elsewhere will NOT be deleted."
    
    read -rp "Are you sure you want to uninstall Joplin? (y/N): " confirm_uninstall
    
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled."
        return 0
    fi
    
    if [ -d "$JOPLIN_INSTALL_DIR" ]; then
        echo "📁 Removing installation directory..."
        sudo rm -rf "$JOPLIN_INSTALL_DIR"
        if [ $? -eq 0 ]; then
            echo "✅ Installed files removed."
        else
            print_error "Failed to remove installation directory. Check permissions."
            return 1
        fi
    fi
    
    if [ -f "$DESKTOP_ENTRY_PATH" ]; then
        echo "🖥️ Removing desktop entry..."
        sudo rm -f "$DESKTOP_ENTRY_PATH"
        if [ $? -eq 0 ]; then
            echo "✅ Desktop entry removed."
        else
            print_error "Failed to remove desktop entry. Check permissions."
            return 1
        fi
    fi
    
    echo "🗑️ Refreshing desktop entries..."
    echo "💡 You may need to log out and log back in, or reboot for changes to take effect."
    
    print_success "Joplin has been uninstalled."
}

# --- Main Program ---
install_dependencies

figlet -f slant "Joplin AppImage"
echo "For Ubuntu 22.04"
echo "-------------------------"
echo "1. 💿 Install Joplin"
echo "2. 🆙 Update Joplin"
echo "3. 🗑️  Uninstall Joplin"
echo "-------------------------"

read -rp "Choose an option (1, 2, or 3): " choice

case $choice in
    1)
        installJoplin
        ;;
    2)
        updateJoplin
        ;;
    3)
        uninstallJoplin
        ;;
    *)
        print_error "Invalid option. Please choose 1, 2, or 3."
        exit 1
        ;;
esac

exit 0

