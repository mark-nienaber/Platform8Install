#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: ig8.sh
# Description: Automates deployment and configuration of ForgeRock Identity 
#              Gateway (IG) with UI routes. Cleans previous installations, 
#              generates TLS keystore, installs IG, and starts with health checks.
################################################################################

# Load environment variables
source ./platformconfig.env

# -----------------------------------------------------------------------------
# Logging utility functions (consistent with other scripts)
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }

# -----------------------------------------------------------------------------
# Function: clear_ig
# Description: Remove old IG security, installation, and config directories
# -----------------------------------------------------------------------------
function clear_ig() {
    info "Removing previous IG security, installation, and config directories..."
    rm -rf "${IG_KEY_DIR}" "${IG_DIR}" "${IG_CFG_DIR}"
    success "Removed IG directories: ${IG_KEY_DIR}, ${IG_DIR}, ${IG_CFG_DIR}"
}

# -----------------------------------------------------------------------------
# Function: prepare_keys
# Description: Generate TLS key pair and export CA certificate
# -----------------------------------------------------------------------------
function prepare_keys() {
    info "Creating keystore directory and PIN file"
    mkdir -p "${IG_KEY_DIR}"
    echo -n "${DEFAULT_PASSWORD}" > "${IG_KEYSTORE_PIN_FILE}"
    chmod 600 "${IG_KEYSTORE_PIN_FILE}"
    success "Keystore PIN file created at ${IG_KEYSTORE_PIN_FILE}"

    info "Generating TLS key pair"
    "${DSKEYMGR}" create-tls-key-pair \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DEFAULT_PASSWORD}" \
        --keyStoreFile "${IG_KEYSTORE_FILE}" \
        --keyStorePassword:file "${IG_KEYSTORE_PIN_FILE}" \
        --hostname "${IG_HOSTNAME}" \
        --subjectDn "CN=${IG_HOSTNAME},O=ForgeRock"
    success "Keystore created at ${IG_KEYSTORE_FILE}"

    info "Verifying keystore contents"
    keytool -list -keystore "${IG_KEYSTORE_FILE}" -storepass:file "${IG_KEYSTORE_PIN_FILE}"

    info "Exporting CA certificate"
    "${DSKEYMGR}" export-ca-cert \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DEFAULT_PASSWORD}" \
        --outputFile "${IG_CA_CERT_FILE}"
    success "CA certificate exported to ${IG_CA_CERT_FILE}"
}

# -----------------------------------------------------------------------------
# Function: replace_placeholders
# Description: Replace placeholders in configuration files with actual values
# -----------------------------------------------------------------------------
function replace_placeholders() {
    local file="$1"
    info "Replacing placeholders in $(basename "$file")"
    
    # Check if file exists and is writable
    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi
    
    if [[ ! -w "$file" ]]; then
        error "File not writable: $file"
        return 1
    fi
    
    # Replace IG-specific placeholders
    sed -i "s|{{IG_KEY_DIR}}|${IG_KEY_DIR:-}|g" "$file" || { error "Failed to replace IG_KEY_DIR in $file"; return 1; }
    sed -i "s|{{IG_KEYSTORE_FILE}}|${IG_KEYSTORE_FILE:-}|g" "$file" || { error "Failed to replace IG_KEYSTORE_FILE in $file"; return 1; }
    sed -i "s|\"{{IG_HTTP_PORT}}\"|${IG_HTTP_PORT:-7080}|g" "$file" || { error "Failed to replace quoted IG_HTTP_PORT in $file"; return 1; }
    sed -i "s|\"{{IG_HTTPS_PORT}}\"|${IG_HTTPS_PORT:-9443}|g" "$file" || { error "Failed to replace quoted IG_HTTPS_PORT in $file"; return 1; }
    sed -i "s|{{IG_HTTP_PORT}}|${IG_HTTP_PORT:-7080}|g" "$file" || { error "Failed to replace IG_HTTP_PORT in $file"; return 1; }
    sed -i "s|{{IG_HTTPS_PORT}}|${IG_HTTPS_PORT:-9443}|g" "$file" || { error "Failed to replace IG_HTTPS_PORT in $file"; return 1; }
    
    # Replace hostname placeholders
    sed -i "s|{{AM_HOSTNAME}}|${AM_HOSTNAME:-am.example.com}|g" "$file" || { error "Failed to replace AM_HOSTNAME in $file"; return 1; }
    sed -i "s|{{IDM_HOSTNAME}}|${IDM_HOSTNAME:-openidm.example.com}|g" "$file" || { error "Failed to replace IDM_HOSTNAME in $file"; return 1; }
    sed -i "s|{{PLATFORM_HOSTNAME}}|${PLATFORM_HOSTNAME:-platform.example.com}|g" "$file" || { error "Failed to replace PLATFORM_HOSTNAME in $file"; return 1; }
    
    # Replace port placeholders
    sed -i "s|{{TOMCAT_HTTP_PORT}}|${TOMCAT_HTTP_PORT:-8081}|g" "$file" || { error "Failed to replace TOMCAT_HTTP_PORT in $file"; return 1; }
    sed -i "s|{{IDM_HTTP_PORT}}|${BOOT_PORT_HTTP:-8080}|g" "$file" || { error "Failed to replace IDM_HTTP_PORT in $file"; return 1; }
    
    success "Placeholders replaced in $(basename "$file")"
}

# -----------------------------------------------------------------------------
# Function: copy_ig_files
# Description: Copy config, admin, logback, and all route files from script dir
# -----------------------------------------------------------------------------
function copy_ig_files() {
    local src_dir="${SCRIPT_DIR}/ig"

    info "Copying main config.json"
    cp "${src_dir}/config-ui.json" "${IG_CONFIG}/config.json" && success "config.json copied" || error "Failed to copy config.json"

    info "Copying admin.json"
    cp "${src_dir}/admin.json" "${IG_CONFIG}/" && success "admin.json copied" || warning "admin.json not found or failed"
    
    # Replace placeholders in admin.json
    if [[ -f "${IG_CONFIG}/admin.json" ]]; then
        replace_placeholders "${IG_CONFIG}/admin.json"
    fi

    info "Copying logback.xml"
    cp "${src_dir}/logback.xml" "${IG_CONFIG}/" && success "logback.xml copied" || warning "logback.xml not found or failed"

    info "Copying all route definitions"
    local route_src="${src_dir}/routes"
    shopt -s nullglob
    for file in "${route_src}"/*; do
        if [[ -f "$file" ]]; then
            local name=$(basename "$file")
            cp "$file" "${IG_ROUTES}/" && success "${name} copied" || warning "Failed to copy ${name}"
            
            # Replace placeholders in route files
            if [[ -f "${IG_ROUTES}/${name}" ]]; then
                replace_placeholders "${IG_ROUTES}/${name}"
            fi
        fi
    done
    shopt -u nullglob
}

# -----------------------------------------------------------------------------
# Function: install_ig
# Description: Unzip IG distribution and set up config dirs
# -----------------------------------------------------------------------------
function install_ig() {
    info "Unzipping IG from ${IG_ZIP} to ${BASE_INSTALL_DIR}"
    mkdir -p "${BASE_INSTALL_DIR}"
    unzip -q -o "${IG_ZIP}" -d "${BASE_INSTALL_DIR}"
    success "Unzipped to ${IG_DIR}"

    info "Ensuring configuration and routes directories exist"
    mkdir -p "${IG_CONFIG}" "${IG_ROUTES}"

    copy_ig_files
}

# -----------------------------------------------------------------------------
# Function: show_ready
# Description: Display IG readiness URLs
# -----------------------------------------------------------------------------
function show_ready() {
    info "🏁 Identity Gateway is now ready and listening on the following URLs:"
    info "  • HTTP  : http://${IG_HOSTNAME}:${IG_HTTP_PORT}"
    info "  • HTTPS : https://${IG_HOSTNAME}:${IG_HTTPS_PORT}"
}

# -----------------------------------------------------------------------------
# Function: start_ig
# Description: Start PingGateway and perform health checks
# -----------------------------------------------------------------------------
function start_ig() {
    info "Starting PingGateway"
    nohup "${IG_DIR}/bin/start.sh" >/dev/null 2>&1 &
    IG_PID=$!
    success "PingGateway started (PID: ${IG_PID})"

    sleep 3
    info "Health check HTTP on port ${IG_HTTP_PORT}"
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" http://${IG_HOSTNAME}:${IG_HTTP_PORT}/openig/ping)
    echo "→ HTTP status: ${http_status}"

    info "Health check HTTPS on port ${IG_HTTPS_PORT}"
    local https_status
    https_status=$(curl -s -o /dev/null -w "%{http_code}" --cacert "${IG_CA_CERT_FILE}" https://${IG_HOSTNAME}:${IG_HTTPS_PORT}/openig/ping)
    echo "→ HTTPS status: ${https_status}"

    # Notify readiness
    show_ready
}

# -----------------------------------------------------------------------------
# Function: shutdown_ig
# Description: Forcefully stops all OpenIG processes regardless of PID tracking
# -----------------------------------------------------------------------------
function shutdown_ig() {
    info "Stopping PingGateway"

    # Attempt graceful shutdown if possible
    if [[ -x "${IG_DIR}/bin/stop.sh" ]]; then
        "${IG_DIR}/bin/stop.sh" && success "stop.sh invoked" || warning "stop.sh failed"
    fi

    # Kill known IG processes based on command patterns
    local ig_pids
    ig_pids=$(ps -ef | grep '[o]penig' | awk '{print $2}' || true)

    if [[ -n "$ig_pids" ]]; then
        info "Found running IG processes: $ig_pids"
        kill -9 $ig_pids && success "Forcefully killed IG processes" || error "Failed to kill IG processes"
    else
        info "No OpenIG processes found"
    fi
}


# ==============================================================================
# Main Script Execution
# ==============================================================================
shutdown_ig
clear_ig
prepare_keys
install_ig
start_ig
#shutdown_ig