#!/bin/bash

# Define variables for repositories and their corresponding branches
REPOS=(
    "https://github.com/openwrt/openwrt.git https://github.com/liudf0716/openwrt.git openwrt main"
    "https://github.com/openwrt/packages.git https://github.com/liudf0716/packages.git packages master"
    "https://github.com/openwrt/luci.git https://github.com/liudf0716/luci.git luci master"
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

    cd "$REPO_DIR"

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

    # Ensure we are on the correct branch
    echo "Switching to branch $BRANCH..."
    git checkout "$BRANCH" || { echo "Failed to switch to branch $BRANCH."; exit 1; }

    # Rebase the local branch onto the upstream branch
    echo "Rebasing your fork's $BRANCH branch onto upstream's $BRANCH branch..."
    git rebase upstream/"$BRANCH" || { 
        echo "Rebase failed. Resolve conflicts and run 'git rebase --continue'."; 
        exit 1; 
    }

    # Push the rebased changes to your fork
    echo "Pushing rebased changes to your fork's repository..."
    REPO_PATH="${FORK_REPO#https://github.com/}"
    echo "REPO_PATH: $REPO_PATH"
    git push --force-with-lease "https://${GH_TOKEN}@github.com/${REPO_PATH}" "$BRANCH" || { 
        echo "Failed to push changes to $FORK_REPO."; 
        exit 1; 
    }

    # Return to the previous directory
    cd ..
    echo "Successfully synced $REPO_DIR."
}

# Iterate over all repositories and sync them
for REPO_INFO in "${REPOS[@]}"; do
    sync_repo $REPO_INFO
done