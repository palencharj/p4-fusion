#!/bin/bash

# ==============================================================================
#  CONFIGURATION SECTION (Mess with this stuff!)
# ==============================================================================

# -- Perforce Settings --
P4USER="jpalenchar"
P4PORT="10.2.2.71:61234"
DEPOT_PATH="//Components/FSSDK/..."    # The full path to migrate
TEMP_CLIENT_NAME="p4fusion-debug-${USER}"

# -- Git Settings --
# Note: eval is used here to safely handle the '~' character
GIT_REPO_PATH=$(eval echo ~/FSSDK-Debug)

# -- Tool Path --
P4_FUSION_BIN="./build/p4-fusion/p4-fusion"

# -- Performance & Stability Settings --
# Since you have "unlimited" group rights, we can go faster.
# If you get "Connection Reset" errors, LOWER these numbers.
NETWORK_THREADS=8        # How many parallel downloads (Default: 4. Try 8 if fast, 1 if unstable)
PRINT_BATCH=100          # How many files to ask for at once (Default: 100. Try 10 if crashing)
LOOK_AHEAD=2000          # How many changes to buffer (Default: 2000)
RETRIES=20               # How many times to retry network errors
REFRESH_RATE=1000         # How often to re-login/refresh connection (Prevent timeouts)

# ==============================================================================
#  HELPER FUNCTIONS (Don't touch unless you are debugging)
# ==============================================================================

log() {
    echo -e "\n[$(date +'%H:%M:%S')] \033[1;32m$1\033[0m"
}

error() {
    echo -e "\n[$(date +'%H:%M:%S')] \033[1;31mERROR: $1\033[0m"
    exit 1
}

check_login() {
    log "Checking Perforce Login..."
    export P4USER=$P4USER
    export P4PORT=$P4PORT
    
    p4 login -s > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\033[1;33mSession expired. Please enter your password:\033[0m"
        p4 login
        if [ $? -ne 0 ]; then error "Login failed."; fi
    else
        echo "Logged in as $P4USER."
    fi
}

cleanup_workspace() {
    log "Cleaning up old workspace data..."
    
    # 1. Delete the Client Spec if it exists
    p4 client -d "$TEMP_CLIENT_NAME" > /dev/null 2>&1
    
    # 2. Delete the Git Directory to force a clean start
    if [ -d "$GIT_REPO_PATH" ]; then
        echo "Removing existing directory: $GIT_REPO_PATH"
        rm -rf "$GIT_REPO_PATH"
    fi
    
    mkdir -p "$GIT_REPO_PATH"
}

create_client() {
    log "Creating temporary client: $TEMP_CLIENT_NAME"
    
    # Create the client spec dynamically
    cat <<EOF | p4 client -i
Client: $TEMP_CLIENT_NAME
Owner:  $P4USER
Root:   $(realpath "$GIT_REPO_PATH")
Options: noallwrite noclobber nocompress unlocked nomodtime normdir
SubmitOptions: submitunchanged
LineEnd: local
View:
    $DEPOT_PATH //$TEMP_CLIENT_NAME/...
EOF

    if [ $? -ne 0 ]; then error "Failed to create client spec."; fi
}

run_migration() {
    log "Starting Migration..."
    log "Target: $DEPOT_PATH -> $GIT_REPO_PATH"
    log "Settings: Threads=$NETWORK_THREADS | Batch=$PRINT_BATCH"

    "$P4_FUSION_BIN" \
        --path "$DEPOT_PATH" \
        --user "$P4USER" \
        --port "$P4PORT" \
        --client "$TEMP_CLIENT_NAME" \
        --src "$GIT_REPO_PATH" \
        --networkThreads $NETWORK_THREADS \
        --printBatch $PRINT_BATCH \
        --lookAhead $LOOK_AHEAD \
        --retries $RETRIES \
        --refresh $REFRESH_RATE

    if [ $? -eq 0 ]; then
        log "SUCCESS! Migration complete."
        log "Run 'cd $GIT_REPO_PATH' to see your files."
    else
        error "p4-fusion failed. Check the output above."
    fi
}

# ==============================================================================
#  MAIN EXECUTION
# ==============================================================================

check_login
cleanup_workspace
create_client
run_migration