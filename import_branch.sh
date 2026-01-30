#!/bin/bash

# ==============================================================================
#  Import Full Repo (Main + All Branches)
# ==============================================================================
# Usage: ./import_repo_full.sh <Target_Repo> <Source_Repo> <New_Name_For_Main>
# Example: ./import_repo_full.sh ~/Foundation ~/FSSDK27 FSSDK27

TARGET_INPUT=$1
SOURCE_INPUT=$2
NEW_MAIN_NAME=$3

# --- 1. Validation & Setup ---

if [ -z "$TARGET_INPUT" ] || [ -z "$SOURCE_INPUT" ] || [ -z "$NEW_MAIN_NAME" ]; then
    echo "Usage: $0 <Target_Repo> <Source_Repo> <New_Name_For_Main>"
    exit 1
fi

fix_path() {
    local path=$1
    path=$(realpath -m "$path")
    if [ -d "$path" ]; then
        if [ -d "$path/objects" ] && [ -d "$path/refs" ]; then echo "$path"; return; fi
        if [ -d "$path/.git" ]; then echo "$path"; return; fi
        local sub=$(find "$path" -maxdepth 2 -type d -name "objects" 2>/dev/null | head -n 1)
        if [ ! -z "$sub" ]; then dirname "$sub"; return; fi
    fi
    echo "$path"
}

TARGET_REPO=$(fix_path "$TARGET_INPUT")
SOURCE_REPO=$(fix_path "$SOURCE_INPUT")

# --- SMART NAMING LOGIC ---

# 1. We start by wanting the prefix to look like the new main name (e.g. "FSSDK27")
PREFIX_BASE="$NEW_MAIN_NAME"

# 2. Check for Git Directory/File Collision
#    Git prevents having a branch "FSSDK27" and a folder "FSSDK27/" simultaneously.
#    Since you explicitly requested the main branch be "FSSDK27", we must 
#    adjust the sub-branches to avoid the folder conflict.

# We default to using a slash (folder) separator: FSSDK27/branch
SEPARATOR="/"

# But if the Main Name is exactly the Prefix Base, we switch to a hyphen separator
# to avoid the Git error.
# Result: Main -> "FSSDK27", Sub -> "FSSDK27-27.0.0"
if [ "$NEW_MAIN_NAME" == "$PREFIX_BASE" ]; then
    SEPARATOR="-"
fi

# 3. Construct the final Prefix
REPO_PREFIX="${PREFIX_BASE}${SEPARATOR}"

echo "--------------------------------------------------------"
echo "Target Repo:     $TARGET_REPO"
echo "Source Repo:     $SOURCE_REPO"
echo "Target Main:     $NEW_MAIN_NAME (Preserved as requested)"
echo "Sub-Branch fmt:  ${REPO_PREFIX}BranchName"
echo "--------------------------------------------------------"

# Create a temporary workspace
TEMP_DIR=$(mktemp -d)
echo "[INFO] Created temp workspace: $TEMP_DIR"

# --- 2. Clone Target Repo ---

echo "[INFO] Cloning Target Repo..."
git clone "$TARGET_REPO" "$TEMP_DIR/work_repo" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to clone Target."
    rm -rf "$TEMP_DIR"
    exit 1
fi

cd "$TEMP_DIR/work_repo" || exit 1

# --- 3. Connect Source Repo ---

echo "[INFO] Adding Source Remote..."
git remote add source_temp "$SOURCE_REPO"
git fetch source_temp > /dev/null 2>&1

# --- 4. Handle The Main Branch ---

echo "[INFO] Processing Main Branch..."
SOURCE_MAIN=""
# Detect source main/master
if git rev-parse --verify source_temp/main > /dev/null 2>&1; then SOURCE_MAIN="main";
elif git rev-parse --verify source_temp/master > /dev/null 2>&1; then SOURCE_MAIN="master"; fi

if [ -n "$SOURCE_MAIN" ]; then
    echo "       Source ($SOURCE_MAIN) -> Target ($NEW_MAIN_NAME)"
    
    # SAFETY: Ensure we aren't accidentally trying to overwrite the Target's existing HEAD 
    # if the user passed "main" or "master" as the New Name.
    EXISTING_HEAD=$(git symbolic-ref --short HEAD)
    if [ "$NEW_MAIN_NAME" == "$EXISTING_HEAD" ]; then
        echo "       [WARN] You are overwriting the Target's existing '$EXISTING_HEAD' branch."
        echo "              This will merge histories."
    fi

    # Checkout source main as the new name
    git checkout -b "$NEW_MAIN_NAME" "source_temp/$SOURCE_MAIN" > /dev/null 2>&1
    
    # Push to origin
    git push origin "$NEW_MAIN_NAME" > /dev/null 2>&1
    echo "       [OK] Pushed $NEW_MAIN_NAME"
else
    echo "       [WARN] Could not find main/master in source."
fi

# --- 5. Handle All Other Branches ---

echo "[INFO] Processing Sub-Branches..."

# List remote branches, excluding HEAD and the main branch we just imported
BRANCHES=$(git branch -r | grep "source_temp/" | grep -v "HEAD" | grep -v "source_temp/$SOURCE_MAIN$")

for REMOTE_REF in $BRANCHES; do
    # Raw name: "27.0.0"
    RAW_NAME=${REMOTE_REF#source_temp/}
    RAW_NAME=$(echo "$RAW_NAME" | xargs)

    # Skip if it's 'master' but we already handled 'main' (or vice versa) to avoid dupes
    if [[ "$SOURCE_MAIN" == "main" && "$RAW_NAME" == "master" ]]; then continue; fi
    if [[ "$SOURCE_MAIN" == "master" && "$RAW_NAME" == "main" ]]; then continue; fi

    # Apply Prefix: "FSSDK27-27.0.0" (using hyphen to allow main branch "FSSDK27")
    TARGET_NAME="${REPO_PREFIX}${RAW_NAME}"

    echo "       Importing: $RAW_NAME -> $TARGET_NAME"
    
    # Check if exists
    if git ls-remote --heads origin "$TARGET_NAME" | grep -q "$TARGET_NAME"; then
        echo "       [SKIP] Branch '$TARGET_NAME' already exists."
        continue
    fi

    # Checkout and Push
    git checkout -b "$TARGET_NAME" "$REMOTE_REF" > /dev/null 2>&1
    git push origin "$TARGET_NAME" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "       [OK] Pushed $TARGET_NAME"
    else
        echo "       [FAIL] Error pushing $TARGET_NAME"
    fi
done

# --- 6. Cleanup ---
echo "--------------------------------------------------------"
echo "[SUCCESS] Import complete."
rm -rf "$TEMP_DIR"