#!/bin/bash
# ==========================================
# RANGE TEST SCRIPT
# ==========================================
P4USER="jpalenchar"
P4PORT="perforce.fsi.local:61234"
GIT_REPO_PATH=$(eval echo ~/FSSDK-Debug)
TEMP_CLIENT_NAME="p4fusion-debug-${USER}"
P4_FUSION_BIN="./build/p4-fusion/p4-fusion"

# === MAGIC TRICK: We limit the query to the first ~1000 changes ===
# This bypasses the server's "MaxResults" limit because the answer is small.
DEPOT_PATH="//Components/FSSDK/...@470075,472000"

# ==========================================

mkdir -p "$GIT_REPO_PATH"

# Create Client
cat <<EOF | p4 client -i
Client: $TEMP_CLIENT_NAME
Owner:  $P4USER
Root:   $(realpath "$GIT_REPO_PATH")
Options: noallwrite noclobber nocompress unlocked nomodtime normdir
SubmitOptions: submitunchanged
LineEnd: local
View:
    //Components/FSSDK/... //$TEMP_CLIENT_NAME/...
EOF

echo "Running p4-fusion on range: $DEPOT_PATH"

"$P4_FUSION_BIN" \
    --path "$DEPOT_PATH" \
    --user "$P4USER" \
    --port "$P4PORT" \
    --client "$TEMP_CLIENT_NAME" \
    --src "$GIT_REPO_PATH" \
    --networkThreads 1 \
    --printBatch 10 \
    --lookAhead 2000 \
    --retries 10

echo "Check the logs above. Did it find CL 470075?"