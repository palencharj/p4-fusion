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

# Enable debug printing so you can see the exact command running
set -x

# 1. Login Check
export P4USER=$P4USER
export P4PORT=$P4PORT
p4 login -s > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "[ERROR] Session expired. Please run 'p4 login' and try again."
    exit 1
fi

# Turn off debug for the discovery phase to reduce noise
set +x

# 2. Discovery Phase
echo "[INFO] Mapping all streams under $SEARCH_ROOT..."
RAW_OUTPUT=$(p4 streams "$SEARCH_ROOT/..." | tr -d '\r')

if [ -z "$RAW_OUTPUT" ]; then
    echo "[ERROR] No streams found under $SEARCH_ROOT."
    exit 1
fi

# Filter for relevant streams
RELEVANT_STREAMS=$(echo "$RAW_OUTPUT" | awk '$3 ~ /^(mainline|development|release)$/ {print $2, $3}')

# Extract Mainlines
MAINLINES=$(echo "$RELEVANT_STREAMS" | awk '$2 == "mainline" {print $1}')
COUNT=$(echo "$MAINLINES" | wc -w)

if [ "$COUNT" -eq 0 ]; then
    echo "[ERROR] No mainline streams found."
    exit 1
fi

echo "[INFO] Found $COUNT Mainline streams."

# 3. Processing Loop
for MAIN_STREAM in $MAINLINES; do
    echo "----------------------------------------------------------------"
    echo "[INFO] Processing Family for: $MAIN_STREAM"

    COMMON_ROOT=$(dirname "$MAIN_STREAM")
    FAMILY_STREAMS=$(echo "$RELEVANT_STREAMS" | grep "^$COMMON_ROOT/" | awk '{print $1}')

    REL_PATH=${COMMON_ROOT#//}
    SAFE_NAME=${REL_PATH//\//-}
    CLIENT_NAME="p4fusion-${SAFE_NAME}-${USER}"
    REPO_PATH="${GIT_OUTPUT_ROOT}/${REL_PATH}"

    echo "[INFO] Git Repo:    $REPO_PATH"

    # Cleanup Old Repo
    p4 client -d "$CLIENT_NAME" > /dev/null 2>&1
    if [ -d "$REPO_PATH" ]; then
        rm -rf "$REPO_PATH"
    fi
    mkdir -p "$REPO_PATH"

    # Construct Branch Arguments
    BRANCH_ARGS=()
    
    echo "[INFO] Branches found:"
    for STREAM in $FAMILY_STREAMS; do
        REL_NAME=${STREAM#$COMMON_ROOT/}
        
        if [ "$STREAM" == "$MAIN_STREAM" ]; then
            ALIAS="main"
        else
            ALIAS=${REL_NAME//\//-}
        fi
        
        echo "       - $REL_NAME  ->  $ALIAS"
        
        # Standard space-separated format: --branch value
        BRANCH_ARGS+=( "--branch" "$REL_NAME:$ALIAS" )
    done

    # Create Client Spec
    cat <<EOF | p4 client -i > /dev/null
Client: $CLIENT_NAME
Owner:  $P4USER
Root:   $REPO_PATH
Options: noallwrite noclobber nocompress unlocked nomodtime normdir
SubmitOptions: submitunchanged
View:
    $COMMON_ROOT/... //$CLIENT_NAME/...
EOF

    # Turn debug back on for the critical p4-fusion command
    set -x

    # Run p4-fusion
    # We place BRANCH_ARGS immediately after PATH to ensure context is clear
    "$P4_FUSION_BIN" \
        --path "$COMMON_ROOT/..." \
        "${BRANCH_ARGS[@]}" \
        --user "$P4USER" \
        --port "$P4PORT" \
        --client "$CLIENT_NAME" \
        --src "$REPO_PATH" \
        --networkThreads 8 \
        --printBatch 100 \
        --lookAhead 2000 \
        --retries 20 \
        --refresh 1000 \
        --noColor

    # Turn off debug
    set +x

    # Cleanup
    p4 client -d "$CLIENT_NAME" > /dev/null 2>&1

done

echo "----------------------------------------------------------------"
echo "[SUCCESS] All migrations complete."