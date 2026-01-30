#!/bin/bash

# Usage: ./import_branch.sh <Target_Repo_Path> <Source_Repo_Path> <New_Branch_Name>
# Example: ./import_branch.sh ~/Repos/ProjectA ~/Repos/ProjectB "legacy_branch"

TARGET_INPUT=$1
SOURCE_INPUT=$2
NEW_BRANCH_NAME=$3

# --- 1. Validation & Setup ---

if [ -z "$TARGET_INPUT" ] || [ -z "$SOURCE_INPUT" ] || [ -z "$NEW_BRANCH_NAME" ]; then
    echo "Usage: $0 <Target_Repo_Path> <Source_Repo_Path> <New_Branch_Name>"
    exit 1
fi

# Helper to fix the "Parent Folder" mistake
# If user passes ".../Foundation" but repo is ".../Foundation/FSSDKFoundation", we fix it.
fix_path() {
    local path=$1
    if [ -d "$path" ]; then
        # If the path itself is not a repo (no objects folder), check inside
        if [ ! -d "$path/objects" ] && [ ! -d "$path/.git" ]; then
            # Look for a subdirectory that looks like a repo
            local sub=$(find "$path" -maxdepth 2 -type d -name "objects" | head -n 1)
            if [ ! -z "$sub" ]; then
                echo "$(dirname "$sub")"
                return
            fi
        fi
    fi
    echo "$path"
}

TARGET_REPO=$(fix_path "$TARGET_INPUT")
SOURCE_REPO=$(fix_path "$SOURCE_INPUT")

echo "--------------------------------------------------------"
echo "Target:     $TARGET_REPO"
echo "Source:     $SOURCE_REPO"
echo "New Branch: $NEW_BRANCH_NAME"
echo "--------------------------------------------------------"

# Create a temporary workspace
TEMP_DIR=$(mktemp -d)
echo "[INFO] Created temp workspace: $TEMP_DIR"

# --- 2. Clone Target Repo ---

echo "[INFO] Cloning Target Repo to temp..."
git clone "$TARGET_REPO" "$TEMP_DIR/work_repo" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to clone Target. Is the path correct?"
    rm -rf "$TEMP_DIR"
    exit 1
fi

cd "$TEMP_DIR/work_repo" || exit 1

# --- 3. Pull in Source History ---

echo "[INFO] Adding Source Repo as remote..."
git remote add source_temp "$SOURCE_REPO"

echo "[INFO] Fetching source history..."
git fetch source_temp > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to fetch from Source. Is the path correct?"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- 4. Create the New Branch ---

echo "[INFO] Creating new branch '$NEW_BRANCH_NAME'..."
# Try to find 'master' or 'main' in the source
if git rev-parse --verify source_temp/master > /dev/null 2>&1; then
    git checkout -b "$NEW_BRANCH_NAME" source_temp/master
elif git rev-parse --verify source_temp/main > /dev/null 2>&1; then
    git checkout -b "$NEW_BRANCH_NAME" source_temp/main
else
    echo "[ERROR] Could not find 'master' or 'main' branch in Source repo."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- 5. Push Back to Original Target ---

echo "[INFO] Pushing new branch back to Target Repo..."
git push origin "$NEW_BRANCH_NAME"

if [ $? -eq 0 ]; then
    echo "--------------------------------------------------------"
    echo "[SUCCESS] Done! Branch '$NEW_BRANCH_NAME' is now in:"
    echo "$TARGET_REPO"
else
    echo "[ERROR] Failed to push to target."
fi

# --- 6. Cleanup ---
rm -rf "$TEMP_DIR"