#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: idm8.sh
# Description: Sets up Ping Identity IDM 8 using common environment variables.
################################################################################

# ==========================
# Load environment variables
# ==========================
source ./platformconfig.env  # load SOFTWARE_DIR, IDM_ZIP, IDM_DIR, etc.

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }

# ========================================
# Function: Stop IDM if running
# ========================================
function stop_idm_if_running() {
    info "Checking for running IDM process..."
    local pid
    pid=$(pgrep -f 'openidm' || true)
    if [ -n "$pid" ]; then
        info "Found IDM running (PID $pid). Attempting graceful shutdown..."
        if [ -x "${IDM_EXTRACT_DIR}/shutdown.sh" ]; then
            "${IDM_EXTRACT_DIR}/shutdown.sh" && success "IDM stopped gracefully" || error "Graceful shutdown failed"
        else
            info "Shutdown script not found, using kill"
            kill "$pid" && success "IDM killed (PID $pid)" || error "Failed to kill IDM (PID $pid)"
        fi
    else
        info "No running IDM process found"
    fi
    sleep 10
}

# ========================================
# Function: Clean up previous installation
# ========================================
function clear_old_idm() {
    info "Cleaning up previous IDM installation..."
    rm -rf "${IDM_EXTRACT_DIR}" && success "Old IDM files removed" || error "Failed to remove old IDM files"
}

# ========================================
# Function: Extract IDM ZIP
# ========================================
function extract_idm() {
    info "Extracting IDM from ZIP..."
    if [ ! -f "${IDM_ZIP}" ]; then
        error "IDM ZIP not found: ${IDM_ZIP}"
        exit 1
    fi
    unzip -q "${IDM_ZIP}" -d "${IDM_DIR}" && success "IDM extracted to ${IDM_EXTRACT_DIR}" || { error "Extraction failed"; exit 1; }
}

# ========================================
# Function: Configure IDM
# ========================================
function configure_idm() {
    info "Configuring IDM..."

    # Remove default repo.ds.json
    if [ -f "${IDM_CONFIG_DIR}/repo.ds.json" ]; then
        info "Removing default repo.ds.json"
        rm -f "${IDM_CONFIG_DIR}/repo.ds.json" && success "Removed default repo.ds.json" || error "Failed to remove repo.ds.json"
    fi

    # Import DS cert into IDM truststore
    info "Importing DS certificate into IDM truststore... from ${IDM_CERT_FILE}"
    
    if [ -f "${IDM_CERT_FILE}" ]; then
        keytool -importcert -noprompt \
            -alias ds-repo-ca-cert \
            -keystore "${IDM_TRUSTSTORE}" \
            -storepass:file "${IDM_STOREPASS_FILE}" \
            -file "${IDM_CERT_FILE}" && success "Certificate imported into truststore" || error "Certificate import failed"
    else
        error "Certificate file not found: ${IDM_CERT_FILE}"
    fi

    # Update boot.properties
    info "Updating boot.properties"
    tmp_boot="${BOOT_FILE}.tmp"
    cp "${BOOT_FILE}" "$tmp_boot"
    declare -A props=(
        ["openidm.port.http"]="${BOOT_PORT_HTTP}"
        ["openidm.port.https"]="${BOOT_PORT_HTTPS}"
        ["openidm.port.mutualauth"]="${BOOT_PORT_MUTUALAUTH}"
        ["openidm.host"]="${BOOT_HOST}"
    )
    for key in "${!props[@]}"; do
        val="${props[$key]}"
        if grep -q "^${key}=" "$tmp_boot"; then
            sed -i "s|^${key}=.*|${key}=${val}|" "$tmp_boot"
        else
            echo "${key}=${val}" >> "$tmp_boot"
        fi
    done
    mv "$tmp_boot" "${BOOT_FILE}" && success "boot.properties updated" || error "Failed to update boot.properties"
}

# ========================================
# Function: Copy IDM configuration files
# ========================================
function copy_idm_config_files() {
    info "Copying IDM configuration files..."
    local src_dir="${SCRIPT_DIR}/idm"
    if [ ! -d "$src_dir" ]; then
        error "Config source directory not found: $src_dir"
        return 1
    fi
    for file in "$src_dir"/*.json; do
        [ -f "$file" ] || continue
        cp "$file" "${IDM_CONFIG_DIR}/" && info "Copied $(basename "$file")" || error "Failed to copy $(basename "$file")"
    done
    success "All IDM config files copied"
}

# ========================================
# Function: Start IDM
# ========================================
function start_idm() {
    info "Starting IDM..."
    cd "${IDM_EXTRACT_DIR}"
    info "Running startup.sh &"
    ./startup.sh &
    sleep 20
    local logf="${IDM_LOGS_DIR}/openidm0.log"
    if [ -f "$logf" ]; then
        info "Displaying last 50 lines of IDM log"
        tail -n 50 "$logf"
    else
        error "IDM log not found: $logf"
    fi
    success "IDM startup initiated"
}

# ========================
# Main Execution
# ========================
stop_idm_if_running
clear_old_idm
extract_idm
configure_idm
copy_idm_config_files
start_idm