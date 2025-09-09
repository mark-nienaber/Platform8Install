#!/bin/bash
set -euo pipefail

################################################################################
# Script Name: ds8.sh
# Description: Sets up Ping Directory Server (DS) instances for AM config, CTS, 
#              and IDRepo with improved, coloured logging and centralized 
#              configuration.
################################################################################

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

# ========================================
# Function: Kill all DS processes
# ========================================
function kill_ds_processes() {
    info "Searching for running DS processes..."
    local ds_pids
    ds_pids=$(ps -ef | grep 'org.opends.server.core.DirectoryServer' | grep -v grep | awk '{print $2}') || ds_pids=""
    if [ -z "$ds_pids" ]; then
        info "No running DS processes found."
    else
        info "Killing DS processes: $ds_pids"
        if kill -9 $ds_pids; then
            success "DS processes terminated."
        else
            error "Failed to kill some DS processes"
        fi
    fi
}

# ========================================
# Function: Create AM truststore
# ========================================
function prepare_am_truststore() {
    info "Creating AM truststore..."
    sudo rm -rf "${AM_TRUSTSTORE_FOLDER}"
    mkdir -p "${AM_TRUSTSTORE_FOLDER}"
    sudo cp "${jvm_cacerts:-$(dirname $(dirname $(readlink $(readlink $(which javac)))))/lib/security/cacerts}" "${AM_TRUSTSTORE}"
    sudo chown "${INSTALL_USER}:${INSTALL_USER}" "${AM_TRUSTSTORE}"
    sudo chmod 644 "${AM_TRUSTSTORE}"
    success "AM truststore created at ${AM_TRUSTSTORE}"
}

# ========================================
# Function: Import DS certs into AM truststore
# ========================================
function prepare_ds_certs() {
    info "Importing DS certificates into AM truststore..."
    for cert in ds-repo-ca-cert ds-config-ca-cert ds-cts-ca-cert; do
        keytool -importcert -file "${AM_TRUSTSTORE_FOLDER}/${cert}.pem" \
            -keystore "${AM_TRUSTSTORE}" -storepass "${TRUSTSTORE_PASSWORD}" \
            -alias "${cert}" -noprompt && info "Imported ${cert}" || error "Failed to import ${cert}"
    done
    success "DS certificates imported"
}

# ========================================
# Function: Install Config Store
# ========================================
function install_config() {
    info "Installing Config Store at ${DS_CONFIG}..."
    rm -rf "${DS_CONFIG}" && mkdir -p "${DS_CONFIG}"
    unzip -q "${DS_ZIP_FILE}" -d "${DS_CONFIG}"
    cd "${DS_CONFIG}/opendj"
    ./setup \
        --rootUserDN "${DS_ADMIN_DN}" \
        --rootUserPassword "${DS_ADMIN_PASSWORD}" \
        --monitorUserPassword "${DS_ADMIN_PASSWORD}" \
        --hostname "${DS_AMCONFIG_SERVER}" \
        --ldapPort "${DS_AMCONFIG_SERVER_LDAP_PORT}" \
        --ldapsPort "${DS_AMCONFIG_SERVER_LDAPS_PORT}" \
        --httpPort "${DS_AMCONFIG_SERVER_HTTP_PORT}" \
        --httpsPort "${DS_AMCONFIG_SERVER_HTTPS_PORT}" \
        --adminConnectorPort "${DS_AMCONFIG_SERVER_ADMIN_CONNECTOR_PORT}" \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --profile am-config \
        --set am-config/amConfigAdminPassword:"${DEFAULT_PASSWORD}" \
        --start \
        --quiet \
        --acceptLicense
    ./bin/dskeymgr export-ca-cert \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --outputFile "${AM_TRUSTSTORE_FOLDER}/ds-config-ca-cert.pem"
    success "Config Store installed"
}

# ========================================
# Function: Install CTS Store
# ========================================
function install_cts() {
    info "Installing CTS Store at ${DS_CTS}..."
    rm -rf "${DS_CTS}" && mkdir -p "${DS_CTS}"
    unzip -q "${DS_ZIP_FILE}" -d "${DS_CTS}"
    cd "${DS_CTS}/opendj"
    ./setup \
        --rootUserDN "${DS_ADMIN_DN}" \
        --rootUserPassword "${DS_ADMIN_PASSWORD}" \
        --monitorUserPassword "${DS_ADMIN_PASSWORD}" \
        --hostname "${DS_CTS_SERVER}" \
        --ldapPort "${DS_CTS_SERVER_LDAP_PORT}" \
        --ldapsPort "${DS_CTS_SERVER_LDAPS_PORT}" \
        --httpPort "${DS_CTS_SERVER_HTTP_PORT}" \
        --httpsPort "${DS_CTS_SERVER_HTTPS_PORT}" \
        --adminConnectorPort "${DS_CTS_SERVER_ADMIN_CONNECTOR_PORT}" \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --profile am-cts \
        --set am-cts/amCtsAdminPassword:"${DEFAULT_PASSWORD}" \
        --set am-cts/tokenExpirationPolicy:am-sessions-only \
        --start \
        --quiet \
        --acceptLicense
    ./bin/dskeymgr export-ca-cert \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --outputFile "${AM_TRUSTSTORE_FOLDER}/ds-cts-ca-cert.pem"
    success "CTS Store installed"
}

# ========================================
# Function: Install IDRepo Store
# ========================================
function install_idrepo() {
    info "Installing IDRepo Store at ${DS_IDREPO}..."
    rm -rf "${DS_IDREPO}" && mkdir -p "${DS_IDREPO}"
    unzip -q "${DS_ZIP_FILE}" -d "${DS_IDREPO}"
    cd "${DS_IDREPO}/opendj"
    ./setup \
        --rootUserDN "${DS_ADMIN_DN}" \
        --rootUserPassword "${DS_ADMIN_PASSWORD}" \
        --monitorUserPassword "${DS_ADMIN_PASSWORD}" \
        --hostname "${DS_IDREPO_SERVER}" \
        --ldapPort "${DS_IDREPO_SERVER_LDAP_PORT}" \
        --ldapsPort "${DS_IDREPO_SERVER_LDAPS_PORT}" \
        --httpPort "${DS_IDREPO_SERVER_HTTP_PORT}" \
        --httpsPort "${DS_IDREPO_SERVER_HTTPS_PORT}" \
        --adminConnectorPort "${DS_IDREPO_SERVER_ADMIN_CONNECTOR_PORT}" \
        --enableStartTLS \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --profile am-identity-store:8.0.0 \
        --set am-identity-store/amIdentityStoreAdminPassword:"${DEFAULT_PASSWORD}" \
        --profile idm-repo \
        --set idm-repo/domain:${DS_REPO_SUFFIX} \
        --start \
        --quiet \
        --acceptLicense
    ./bin/dskeymgr export-ca-cert \
        --deploymentId "${DS_DEPLOYMENT_ID}" \
        --deploymentIdPassword "${DS_ADMIN_PASSWORD}" \
        --outputFile "${AM_TRUSTSTORE_FOLDER}/ds-repo-ca-cert.pem"
    success "IDRepo Store installed"
}

# ========================================
# Function: Test secure LDAP connectivity
# ========================================
function test_ldap_secure_bind() {
    info "Testing secure LDAP connections..."
    local PASSWORD="${DS_ADMIN_PASSWORD}"
    for label in Config IDRepo CTS; do
        case $label in
            Config)
                host=${DS_AMCONFIG_SERVER}
                port=${DS_AMCONFIG_SERVER_LDAPS_PORT}
                bindDN="uid=am-config,ou=admins,ou=am-config"
                base="ou=am-config";;
            IDRepo)
                host=${DS_IDREPO_SERVER}
                port=${DS_IDREPO_SERVER_LDAPS_PORT}
                bindDN="uid=am-identity-bind-account,ou=admins,${DS_IDREPO_DN}"
                base="ou=identities";;
            CTS)
                host=${DS_CTS_SERVER}
                port=${DS_CTS_SERVER_LDAPS_PORT}
                bindDN="uid=openam_cts,ou=admins,ou=famrecords,ou=openam-session,ou=tokens"
                base="ou=famrecords,ou=openam-session,ou=tokens";;
        esac
        info "→ Testing ${label} Store"
        if "${DS_DIR}/${label,,}/opendj/bin/ldapsearch" -h "$host" -p "$port" -D "$bindDN" -w "$PASSWORD" -b "$base" -Z --trustStorePath "$AM_TRUSTSTORE" "objectclass=*" dn >/dev/null 2>&1; then
            success "${label} LDAP bind succeeded with: "
            success "${DS_DIR}/${label,,}/opendj/bin/ldapsearch -h $host -p $port -D $bindDN -w xxxx -b $base -Z --trustStorePath $AM_TRUSTSTORE objectclass=* dn"
        else
            error "${label} LDAP bind FAILED"
        fi
    done
}

# ==========================
# Main execution sequence
# ==========================
kill_ds_processes
prepare_am_truststore
install_config
install_cts
install_idrepo
prepare_ds_certs
test_ldap_secure_bind