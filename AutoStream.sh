#!/bin/bash

# ==============================================================================
#  CONFIGURATION
# ==============================================================================
P4USER="jpalenchar"
P4PORT="10.2.2.71:61234"
SEARCH_ROOT="//Components/FSSDK"
GIT_OUTPUT_ROOT=$(eval echo ~/FSSDK_Repos)
P4_FUSION_BIN="./build/p4-fusion/p4-fusion"

# ==============================================================================
#  EXECUTION
# ==============================================================================

# 1. Login Check
export P4USER=$P4USER
export P4PORT=$P4PORT
p4 login -s > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Session expired. Please run 'p4 login' and try again."
    exit 1
fi

# 2. Discovery
echo "[INFO] Scanning for mainline streams under $SEARCH_ROOT..."
STREAMS_LIST=$(p4 streams "$SEARCH_ROOT/..." | grep " mainline " | awk '{print $2}')

if [ -z "$STREAMS_LIST" ]; then
    echo "[ERROR] No mainline streams found."
    exit 1
fi

echo "[INFO] Found the following streams:"
echo "$STREAMS_LIST"

# 3. Processing Loop
for STREAM_PATH in $STREAMS_LIST; do
    echo "----------------------------------------------------------------"
    echo "[INFO] Processing: $STREAM_PATH"

    # Generate names
    REL_PATH=${STREAM_PATH#//}
    SAFE_NAME=${REL_PATH//\//-}
    
    CLIENT_NAME="p4fusion-${SAFE_NAME}-${USER}"
    REPO_PATH="${GIT_OUTPUT_ROOT}/${REL_PATH}"

    echo "[INFO] Git Repo:   $REPO_PATH"
    echo "[INFO] Temp Client: $CLIENT_NAME"

    # Cleanup previous run artifacts
    p4 client -d "$CLIENT_NAME" > /dev/null 2>&1
    if [ -d "$REPO_PATH" ]; then
        echo "[WARN] Wiping existing directory: $REPO_PATH"
        rm -rf "$REPO_PATH"
    fi
    mkdir -p "$REPO_PATH"

    # Create P4 Client
    cat <<EOF | p4 client -i > /dev/null
Client: $CLIENT_NAME
Owner:  $P4USER
Root:   $REPO_PATH
Options: noallwrite noclobber nocompress unlocked nomodtime normdir
SubmitOptions: submitunchanged
Stream: $STREAM_PATH
EOF

    # Run p4-fusion (Added missing --user and --port)
    "$P4_FUSION_BIN" \
        --path "$STREAM_PATH/..." \
        --user "$P4USER" \
        --port "$P4PORT" \
        --client "$CLIENT_NAME" \
        --src "$REPO_PATH" \
        --networkThreads 8 \
        --printBatch 100 \
        --lookAhead 2000 \
        --retries 20 \
        --refresh 1000

    # Cleanup
    p4 client -d "$CLIENT_NAME" > /dev/null 2>&1
done

echo "----------------------------------------------------------------"
echo "[SUCCESS] All migrations complete."