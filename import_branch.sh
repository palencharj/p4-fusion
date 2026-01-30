#!/bin/bash

# Usage: ./import_branch.sh <Target_Repo_Path> <Source_Repo_Path> <New_Branch_Name>
# Example: ./import_branch.sh ~/FSSDK_Repos/Main ~/FSSDK_Repos/Old "legacy-v1"

TARGET_REPO=$1
SOURCE_REPO=$2
NEW_BRANCH_NAME=$3

# 1. Validation
if [ -z "$TARGET_REPO" ] || [ -z "$SOURCE_REPO" ] || [ -z "$NEW_BRANCH_NAME" ]; then
    echo "Usage: ./import_branch.sh <Target_Repo_Path> <Source_Repo_Path> <New_Branch_Name>"
    exit 1
fi

TARGET_REPO=$(realpath "$TARGET_REPO")
SOURCE_REPO=$(realpath "$SOURCE_REPO")

echo "--------------------------------------------------------"
echo "Target Repo: $TARGET_REPO"
echo "Source Repo: $SOURCE_REPO"
echo "New Branch:  $NEW_BRANCH_NAME"
echo "--------------------------------------------------------"

# 2. Navigate to Target
cd "$TARGET_REPO" || { echo "Target repo not found"; exit 1; }

# 3. Add Source as a temporary remote
#    We use a random string for remote name to avoid conflicts
TEMP_REMOTE="temp-import-$(date +%s)"

echo "[INFO] Adding local remote..."
git remote add "$TEMP_REMOTE" "$SOURCE_REPO"

# 4. Fetch the objects
echo "[INFO] Fetching history from source..."
git fetch "$TEMP_REMOTE"

# 5. Create the branch
#    We assume the source repo uses 'master'. If it uses 'main', change 'master' below.
echo "[INFO] Creating branch '$NEW_BRANCH_NAME'..."
if git show-ref --quiet "refs/remotes/$TEMP_REMOTE/master"; then
    git checkout -b "$NEW_BRANCH_NAME" "$TEMP_REMOTE/master"
elif git show-ref --quiet "refs/remotes/$TEMP_REMOTE/main"; then
    git checkout -b "$NEW_BRANCH_NAME" "$TEMP_REMOTE/main"
else
    echo "[ERROR] Could not find 'master' or 'main' in source repo."
    git remote remove "$TEMP_REMOTE"
    exit 1
fi

# 6. Cleanup
echo "[INFO] Cleaning up remote..."
git remote remove "$TEMP_REMOTE"

# 7. Switch back to original main branch (optional, but polite)
git checkout master 2>/dev/null || git checkout main 2>/dev/null

echo "--------------------------------------------------------"
echo "[SUCCESS] Branch '$NEW_BRANCH_NAME' created in $TARGET_REPO"
echo "Run 'git checkout $NEW_BRANCH_NAME' to see the files."