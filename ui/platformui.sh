#!/bin/bash

# Script Name : platformui.sh
#
# Purpose     : Installs the Platform UI bundle into the PingAM Tomcat container.
#               • Unzips the PlatformUI ZIP to a temp working directory
#               • Rewrites all internal URLs to point at your deployment
#               • Copies the platform, end-user, and login UIs into Tomcat
#               • Cleans up after itself
#
# Location    : /home/fradmin/Downloads/AM8Install/platformui.sh
# Tested with : PlatformUI-8.0.1.x, Ping Identity Platform 8.0.x

set -euo pipefail

# ==========================
# Load environment variables
# ==========================
source ./platformconfig.env

# -----------------------------------------------------------------------------
# Simple coloured-log functions
# -----------------------------------------------------------------------------
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }

# ========================================
# Function: Cleanup temp workspace
# ========================================
function cleanup() {
  info "Cleaning up temp workspace…"
  rm -rf "${TMP_UI}"
  success "Workspace ${TMP_UI} removed"
}
trap cleanup EXIT

# ========================================
# Function: Prepare temp workspace
# ========================================
function prepare_workspace() {
  info "Preparing temp workspace at ${TMP_UI}"
  mkdir -p "${TMP_UI}"
  success "Temp workspace prepared"

  if [[ ! -f "${UI_ZIP}" ]]; then
    warning "UI ZIP not found: ${UI_ZIP}"
    warning "Download it from the Ping downloads site and place it here."
    exit 1
  fi

  info "Copying UI ZIP into workspace"
  cp "${UI_ZIP}" "${TMP_UI}/"
  success "UI ZIP copied"
}

# ========================================
# Function: Unzip bundle
# ========================================
function unzip_bundle() {
  cd "${TMP_UI}"
  info "Unzipping Platform UI bundle…"
  unzip -q "$(basename "${UI_ZIP}")"
  success "Bundle unzipped"
}

# ========================================
# Function: Set replacement environment variables
# ========================================
function set_env_variables() {
  info "Setting URL environment variables (port 7443, using /secure)"
  export AM_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/${AM_CONTEXT}"
  export AM_ADMIN_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/${AM_CONTEXT}/ui-admin"
  export IDM_REST_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/openidm"
  export IDM_ADMIN_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/admin"
  export IDM_UPLOAD_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/upload"
  export IDM_EXPORT_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/export"
  export ENDUSER_UI_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/enduser-ui/"
  export PLATFORM_ADMIN_URL="https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/platform-ui/"
  export ENDUSER_CLIENT_ID="end-user-ui"
  export ADMIN_CLIENT_ID="idm-admin-ui"
  export THEME="default"
  export PLATFORM_UI_LOCALE="en"
  success "Environment variables set"
}

# ========================================
# Function: Run variable replacement script
# ========================================
function run_variable_replacement() {
  cd "${TMP_UI}/PlatformUI"
  info "Running variable_replacement.sh…"
  ./variable_replacement.sh \
      www/platform/js/*.js \
      www/enduser/js/*.js \
      www/login/js/*.js
  success "JavaScript URLs updated"
}

# ========================================
# Function: Install UI static resources
# ========================================
function install_ui_resources() {
  info "Copying UI artefacts into Tomcat webapps…"
  cp -r "${TMP_UI}/PlatformUI/www/platform" "${WEBAPPS_DIR}/"
  cp -r "${TMP_UI}/PlatformUI/www/enduser" "${WEBAPPS_DIR}/"
  success "Platform & End-user UIs installed to ${WEBAPPS_DIR}"

  info "Replacing Login UI under am/XUI…"
  cp -r "${TMP_UI}/PlatformUI/www/login/"* "${SECURE_XUI_DIR}/"
  success "Login UI updated in am/XUI"
}

# ========================================
# Function: Restart Tomcat
# ========================================
function restart_tomcat() {
  info "Restarting Tomcat..."
  stop_tomcat
  start_tomcat
}

# ========================================
# Function: Stop Tomcat
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
# Function: Start Tomcat
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
  sleep 20

  local retries=12
  for i in $(seq 1 $retries); do
    if netstat -tuln | grep -q "${TOMCAT_HTTP_PORT}.*LISTEN"; then
      success "Tomcat is listening on port ${TOMCAT_HTTP_PORT}."
      return 0
    else
      warning "Tomcat not started yet, waiting 10 more seconds (attempt ${i}/${retries})..."
      sleep 10
    fi
  done

  error "Tomcat failed to start after $((20 + retries*10)) seconds."
  return 1
}

# ==========================
# Main execution sequence
# ==========================
prepare_workspace
unzip_bundle
set_env_variables
run_variable_replacement
install_ui_resources
restart_tomcat

info "Platform UI installation complete."
echo ""
info "Access URLs:"
echo ""
info "  • Platform admin UI : https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/platform-ui/"
echo ""
info "  • End-user UI       : https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/enduser-ui/"
echo ""
info "  • Login UI          : https://${PLATFORM_HOSTNAME}:${IG_HTTPS_PORT}/am/XUI/"
echo ""