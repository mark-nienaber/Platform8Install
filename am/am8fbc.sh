#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: am8fbc.sh
# Description: Automates the deployment and configuration of Ping Advanced 
#              Identity Cloud AM 8.0.1 in File-Based Config (FBC) mode with 
#              improved, coloured logging and centralized configuration.
################################################################################

# ==========================
# Load environment variables
# ==========================
source ./platformconfig.env  # load TOMCAT_DIR, TOMCAT_WEBAPPS_DIR, AM_WAR, AMSTER_DIR, INSTALL_AMSTER_SCRIPT, etc.

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }

# ========================================
# Function: Clear previous AM deploy
# ========================================
function clear_am() {
    info "Deleting old AM files from ${TOMCAT_WEBAPPS_DIR}..."
    rm -rf "${TOMCAT_WEBAPPS_DIR}/am*" ${AMSTER_DIR} ${AM_FBC} ${AM_CFG_DIR} ${AM_DIR} && success "Old AM files removed." || error "Failed to remove old AM files"
}

# -----------------------------------------------------------------------------
# Function: deploy_amfbc_envfile
# Description: Deploy the AM FBC setenv.sh environment file to Tomcat
# -----------------------------------------------------------------------------
function deploy_amfbc_envfile(){
    info "Deploying new AM setenv.sh..."
    cp "${AM_FBC_ENV_FILE}" "${AM_SETENV}"  && success "AM FBC sentenv.sh file is deployed to ${AM_SETENV}" || error "Failed to copy ${AM_FBC_ENV_FILE}"

    success "AM deployment delay complete."
}

# -----------------------------------------------------------------------------
# Function: deploy_amster_keys
# Description: Recursively copy the entire “keys” directory into ${AM_FBC}
# -----------------------------------------------------------------------------
function deploy_amster_keys() {
    info "Deploying Amster Keys – copying entire keys directory to ${AM_FBC}/"
    if cp -r "${SCRIPT_DIR}/misc/keys" "${AM_FBC}/security/"; then
        success "✔ Directory 'keys' copied to ${AM_FBC}/security/keys"
    else
        error "✖ Failed to copy 'keys' directory to ${AM_FBC}/"
        return 1
    fi
    success "Amster key deployment complete."
}

# -----------------------------------------------------------------------------
# Function: deploy_amfbc
# Description: Deploy the new AM WAR and display deployment status
# -----------------------------------------------------------------------------
function deploy_amfbc() {
    info "Deploying new AM WAR to ${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war"
    if cp "${AM_WAR}" "${TOMCAT_WEBAPPS_DIR}/${AM_CONTEXT}.war"; then
        success "✔ New AM WAR copied to webapps"
    else
        error "✖ Failed to copy AM WAR"
    fi

    info "Waiting for AM to start deploying (20 seconds)…"
    sleep 20
    success "AM deployment wait complete"

    info "Current WARs in Tomcat (${TOMCAT_WEBAPPS_DIR}):"
    ls -lart "${TOMCAT_WEBAPPS_DIR}/"

    info "FBC Config contents (${AM_FBC}):"
    ls -lart "${AM_FBC}/"
}

# ==================================================================================
# Function: setup_amster
# Purpose:  Unzip the Amster tooling from ${AMSTER_ZIP} into ${AMSTER_DIR}
# ==================================================================================
function setup_amster() {
    info "Preparing Amster directory at ${AMSTER_DIR}…"

    info "Unpacking Amster from ${AMSTER_ZIP} to ${AMSTER_SOFTWARE_DIR}…"
    unzip -q -o "${AMSTER_ZIP}" -d "${AMSTER_SOFTWARE_DIR}" \
        && success "Amster unpacked to ${AMSTER_DIR}" \
        || error "Failed to unzip Amster from ${AMSTER_ZIP}"

    info "Sleeping for 20 seconds to allow FBC to be be deployed before running amster..."
    sleep 20
}

# ========================================
# Function: Restart Tomcat
# ========================================
function restart_am() {
    info "Restarting Tomcat..."
    stop_tomcat
    start_tomcat
}

# ========================================
# Function: stop_tomcat
# Description: Stop Tomcat via systemd, then kill any stragglers
# ========================================
function stop_tomcat() {
    info "Stopping Tomcat via systemctl..."
    if sudo systemctl stop tomcat; then
        success "Tomcat stopped via systemctl."
    else
        warning "systemctl stop tomcat failed; will attempt to kill processes."
    fi
    sleep 5

    info "Checking for any remaining Tomcat processes..."
    local pids
    pids=$(ps -ef | grep '[t]omcat' | awk '{print $2}') || pids=""
    if [[ -n "$pids" ]]; then
        info "Killing stray Tomcat processes: $pids"
        if kill -9 $pids; then
            success "Straggler Tomcat processes terminated."
        else
            error "Failed to kill some Tomcat processes: $pids"
        fi
    else
        success "No leftover Tomcat processes found."
    fi

    info "Tomcat shutdown procedure complete."
}

# ========================================
# Function: start_tomcat
# Description: Start Tomcat via systemd and wait up to ~35 seconds for it to come online
# ========================================
function start_tomcat() {
    info "Starting Tomcat via systemctl..."
    if sudo systemctl start tomcat; then
        success "systemctl start tomcat invoked."
    else
        error "systemctl start tomcat failed."
        return 1
    fi

    # Initial wait before checking
    sleep 10

    local retries=5
    for i in $(seq 1 $retries); do
        if netstat -tuln | grep -q ":${TOMCAT_HTTP_PORT}"; then
            success "Tomcat is listening on port ${TOMCAT_HTTP_PORT}."
            return 0
        else
            warning "Tomcat not started yet, waiting 5 more seconds (attempt ${i}/${retries})..."
            sleep 5
        fi
    done

    error "Tomcat failed to start after $((10 + retries*5)) seconds."
    return 1
}

# ========================================
# Function: Create Alpha Realm
# ========================================
function create_alpha_realm() {
    info "Starting creation of Alpha realm..."

    "${AMSTER_DIR}/amster" <<EOF
connect -k ${AM_FBC}/security/keys/amster/amster_rsa ${AM_URL}
create Realms --global --body '{"_id": "L2FscGhh", "parentPath": "/", "active": true, "name": "alpha", "aliases": []}'
:exit
EOF

    if [ $? -eq 0 ]; then
        success "Alpha realm creation complete."
    else
        error "Alpha realm creation failed; check Amster output."
    fi
}

# ========================================
# Function: Import sample journeys
# ========================================
function import_journeys() {
    info "Starting Amster Import of Journeys located ${AM_JOURNEYS_DIR}"

    "${AMSTER_DIR}/amster" <<EOF
connect -k ${AM_FBC}/security/keys/amster/amster_rsa ${AM_URL}
import-config --path ${AM_JOURNEYS_DIR}
:exit
EOF

    if [ $? -eq 0 ]; then
        success "Journey Import complete."
    else
        error "Journey Import failed; check Amster output."
    fi
}

# ==========================
# Main execution sequence
# ==========================
stop_tomcat
clear_am
deploy_amfbc_envfile
start_tomcat
deploy_amfbc
deploy_amster_keys
restart_am
setup_amster
create_alpha_realm
import_journeys
restart_am