#!/bin/bash

# Load environment variables
source ./platformconfig.env

# Logging functions
function info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
function success() { echo -e "\033[1;32m[✔]\033[0m     $*"; }
function error()   { echo -e "\033[1;31m[✖]\033[0m     $*"; }
function warning() { echo -e "\033[1;33m[⚠]\033[0m     $*"; }

# Configure DS disk thresholds
function configure_disk_thresholds() {
    info "Configuring disk thresholds for all DS backends..."
    
    # Configuration for each DS instance with correct hostnames and ports
    local instances=(
        "config:${DS_AMCONFIG_SERVER}:${DS_AMCONFIG_SERVER_ADMIN_CONNECTOR_PORT}:cfgStore"
        "cts:${DS_CTS_SERVER}:${DS_CTS_SERVER_ADMIN_CONNECTOR_PORT}:amCts" 
        "idrepo:${DS_IDREPO_SERVER}:${DS_IDREPO_SERVER_ADMIN_CONNECTOR_PORT}:amIdentityStore"
        "idrepo:${DS_IDREPO_SERVER}:${DS_IDREPO_SERVER_ADMIN_CONNECTOR_PORT}:idmRepo"
    )
    
    for instance_config in "${instances[@]}"; do
        IFS=':' read -r instance hostname port backend <<< "$instance_config"
        local ds_dir="${DS_DIR}/${instance}/opendj"
        
        info "Checking DS $instance directory: $ds_dir"
        
        if [[ -x "$ds_dir/bin/dsconfig" ]]; then
            info "Setting disk thresholds for DS $instance backend $backend..."
            info "  Hostname: $hostname"
            info "  Port: $port"
            info "  Backend: $backend"
            
            if "$ds_dir/bin/dsconfig" \
                set-backend-prop \
                --backend-name "$backend" \
                --set disk-low-threshold:2\ gb \
                --set disk-full-threshold:1\ gb \
                --hostname "$hostname" \
                --port "$port" \
                --bindDn "$DS_ADMIN_DN" \
                --bindPassword "$DS_ADMIN_PASSWORD" \
                --trustAll \
                --no-prompt; then
                
                success "Disk thresholds configured for DS $instance backend $backend"
            else
                error "Failed to configure disk thresholds for DS $instance backend $backend"
                warning "This might be expected if DS is not fully started yet"
            fi
        else
            error "dsconfig not found at $ds_dir/bin/dsconfig"
            warning "DS $instance may not be installed or accessible"
        fi
        echo
    done
    
    success "Disk threshold configuration completed for all DS backends"
}

# Main execution
warning "Standalone Disk Threshold Configuration for Low disk space environments"
configure_disk_thresholds