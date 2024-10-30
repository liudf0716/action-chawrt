#!/bin/bash

# Set variables
REPO_URL="https://github.com/liudf0716/openwrt.git"
REPO_DIR="openwrt"
DL_DIR="$(pwd)/dl"
BRANCH="chawrt/main"

# Handle interruptions gracefully
trap 'echo "Script interrupted."; exit 1' SIGINT

# Prompt the user for the configuration file input
read -p "Enter the configuration file prefix (e.g., x86): " CONFIG_PREFIX
if [ -z "$CONFIG_PREFIX" ]; then
    echo "Error: Configuration prefix cannot be empty."
    exit 1
fi
CONFIG_FILE="${CONFIG_PREFIX}.config"

# Clone the OpenWrt repository or pull latest changes if it already exists
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning repository from $REPO_URL..."
    git clone "$REPO_URL" "$REPO_DIR" || { echo "Failed to clone repository."; exit 1; }
    cd "$REPO_DIR"
    git checkout "$BRANCH" || { echo "Failed to switch to branch $BRANCH."; exit 1; }
    git submodule update --init --recursive
else
    echo "Repository already exists. Pulling latest changes from branch $BRANCH."
    cd "$REPO_DIR"
    git fetch origin || { echo "Failed to fetch latest changes."; exit 1; }
    git checkout "$BRANCH" || { echo "Failed to switch to branch $BRANCH."; exit 1; }
    git pull origin "$BRANCH" || { echo "Failed to pull updates from branch $BRANCH."; exit 1; }
	git submodule update --init --recursive
fi


# Update and install feeds
./scripts/feeds update -a || { echo "Failed to update feeds."; exit 1; }
./scripts/feeds install -a || { echo "Failed to install feeds."; exit 1; }

# Copy the predefined configuration file to .config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found. Please check the path."
    exit 1
fi
cp "$CONFIG_FILE" .config

# Run make oldconfig to update the configuration
make oldconfig || { echo "Failed to update configuration."; exit 1; }

# Link the existing dl directory to avoid downloading packages from scratch
if [  -d "$DL_DIR" ]; then
    ln -sfn "$DL_DIR" dl
fi

# Prompt the user for the number of parallel jobs for compilation
JOBS=$(nproc)
read -p "Enter the number of parallel jobs (default: $JOBS): " USER_JOBS
JOBS=${USER_JOBS:-$JOBS}

# Compile the firmware
echo "Starting download of packages..."
make download -j"$JOBS" || { echo "Failed to download packages."; exit 1; }
echo "Starting compilation with $JOBS parallel jobs..."
make -j"$JOBS" || { echo "Compilation failed."; exit 1; }

echo "OpenWrt compilation completed successfully. The firmware can be found in the 'bin/' directory."
