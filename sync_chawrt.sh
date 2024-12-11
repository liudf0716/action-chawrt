#!/bin/bash

# Define variables for repositories and their corresponding branches
REPOS=(
    "https://github.com/openwrt/openwrt.git https://github.com/liudf0716/chawrt.git chawrt main"
    "https://github.com/openwrt/packages.git https://github.com/liudf0716/packages.git packages master"
    "https://github.com/openwrt/luci.git https://github.com/liudf0716/luci.git luci master"
)

CHAWRT_BRANCH=(
    "chawrt main main"
    "luci chawrt/master master"
    "packages chawrt/master master"
)

CHAWRT_24_10_BRANCH=(
    "chawrt 24.10 openwrt-24.10"
    "luci chawrt/24.10 openwrt-24.10"
    "packages chawrt/24.10 openwrt-24.10"
)

# Handle interruptions gracefully
trap 'echo "Script interrupted."; exit 1' SIGINT

# Function to sync a repository
sync_repo() {
    local UPSTREAM_REPO="$1"
    local FORK_REPO="$2"
    local REPO_DIR="$3"
    local BRANCH="$4"

    echo "Syncing repository: $REPO_DIR (branch: $BRANCH)"

    # Clone the forked repository if it doesn't exist locally
    if [ ! -d "$REPO_DIR" ]; then
        echo "Cloning your forked repository from $FORK_REPO..."
        git clone "$FORK_REPO" "$REPO_DIR" || { echo "Failed to clone $REPO_DIR."; exit 1; }
    fi

    cd "$REPO_DIR" || { echo "Failed to change directory to $REPO_DIR."; exit 1; }

    # Check if the upstream remote already exists
    if git remote | grep -q upstream; then
        echo "Upstream remote already exists."
    else
        # Add upstream repository as a remote
        echo "Adding upstream repository as a remote..."
        git remote add upstream "$UPSTREAM_REPO" || { echo "Failed to add upstream remote."; exit 1; }
    fi

    # Fetch changes from both origin and upstream
    echo "Fetching latest changes from origin and upstream..."
    git fetch origin || { echo "Failed to fetch from origin."; exit 1; }
    git fetch upstream || { echo "Failed to fetch from upstream."; exit 1; }

    # Return to the previous directory
    cd ..
    echo "Successfully fetch $REPO_DIR."
}

# Function to sync a chawrt branch
sync_chawrt_branch() {
    local REPO_DIR="$1"
    local CHAWRT_BRANCH="$2"
    local MAIN_BRANCH="$3"

    if [ ! -d "$REPO_DIR" ]; then
        echo "Repository $REPO_DIR does not exist locally. Skipping..."
        return
    fi

    cd "$REPO_DIR" || { echo "Failed to change directory to $REPO_DIR."; exit 1; }

    # Checkout to CHAWRT_BRANCH
    echo "Switching to branch $CHAWRT_BRANCH..."
    git checkout -b "$CHAWRT_BRANCH" "origin/$CHAWRT_BRANCH" || { echo "Failed to checkout to $CHAWRT_BRANCH."; exit 1; }

    # Rebase to MAIN_BRANCH
    echo "Rebasing your fork's $CHAWRT_BRANCH branch onto upstream's $MAIN_BRANCH branch..."
    git rebase "upstream/$MAIN_BRANCH" || { 
        echo "Rebase failed. Resolve conflicts and run 'git rebase --continue'."; 
        git status
        exit 1; 
    }

    # Push to remote
    echo "Pushing rebased changes to your fork's repository..."
    REPO_PATH="liudf0716/$REPO_DIR"
    echo "REPO_PATH: $REPO_PATH"
    git push -f "https://${GH_TOKEN}@github.com/${REPO_PATH}" "$CHAWRT_BRANCH" || { 
        echo "Failed to push changes to $REPO_DIR."; 
        exit 1; 
    }

    cd ..
}

# Ensure GH_TOKEN is set
if [ -z "$GH_TOKEN" ]; then
    echo "GH_TOKEN is not set. Please set the GitHub token and try again."
    exit 1
fi

# Iterate over all repositories and sync them
for REPO_INFO in "${REPOS[@]}"; do
    sync_repo $REPO_INFO
done
echo "All repositories have been successfully synced."

# Sync chawrt branches
echo "Rebasing chawrt branches..."
for CHARWRT_BRANCH_INFO in "${CHAWRT_BRANCH[@]}"; do
    sync_chawrt_branch $CHARWRT_BRANCH_INFO
done

# Sync chawrt 24.10 branches
echo "Rebasing chawrt 24.10 branches..."
for CHAWRT_24_10_BRANCH_INFO in "${CHAWRT_24_10_BRANCH[@]}"; do
    sync_chawrt_branch $CHAWRT_24_10_BRANCH_INFO
done