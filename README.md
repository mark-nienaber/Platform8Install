# Platform 8 Installation Suite

**Author:** Mark Nienaber  
**Version:** 8.0.x  
**Last Updated:** August 2025

## Overview

This repository contains a comprehensive installation suite for ForgeRock's Platform 8, providing automated deployment and configuration scripts for the complete identity and access management stack. The suite orchestrates the installation of Directory Services (DS), Access Management (AM), Identity Management (IDM), Identity Gateway (IG), and Platform UI components.

## Architecture Components

The Platform 8 installation suite manages the following core components:

### 🗂️ Directory Services (DS)
- **Version:** 8.0.0
- **Purpose:** LDAP directory server for identity data storage
- **Instances:** 
  - Identity Repository (idrepo)
  - Configuration Store (config) 
  - Core Token Service (cts)

### 🔐 Access Management (AM)
- **Version:** 8.0.1
- **Purpose:** Authentication and authorization server
- **Deployment Options:**
  - File-Based Configuration (FBC) mode
  - DS-based configuration mode
- **Features:** Authentication trees, OAuth2/OIDC, SAML

### 👥 Identity Management (IDM)
- **Version:** 8.0.0
- **Purpose:** Identity lifecycle management and user self-service
- **Capabilities:** User provisioning, workflow, compliance

### 🚪 Identity Gateway (IG)
- **Version:** 2025.3.0
- **Purpose:** Reverse proxy and API gateway
- **Functions:** Authentication enforcement, request/response transformation

### 🖥️ Platform UI
- **Version:** 8.0.1.0523
- **Purpose:** Web-based user interfaces
- **Components:** Admin console, End-user portal, Login pages

## Project Structure

```
Platform8Install/
├── install_platform8.sh          # Main orchestration script
├── platformconfig.env            # Central configuration file
├── am/                           # Access Management components
│   ├── am8.sh                   # AM DS-based deployment
│   ├── am8fbc.sh               # AM FBC deployment
│   ├── configure_am.sh         # REST-based configuration
│   ├── setenv.sh               # Environment setup
│   └── root/                   # Authentication trees and nodes
├── ds/                          # Directory Services
│   └── ds8.sh                  # DS installation script
├── idm/                         # Identity Management
│   ├── idm8.sh                 # IDM deployment script
│   ├── *.json                  # Configuration files
│   └── resolver/               # Boot properties
├── ig/                          # Identity Gateway
│   ├── ig8.sh                  # IG deployment script
│   ├── *.json                  # Gateway configuration
│   └── routes/                 # Route definitions
├── ui/                          # Platform UI
│   └── platformui.sh           # UI deployment script
├── misc/                        # Utilities and tools
│   ├── keys/                   # SSH keys and certificates
│   ├── manage-ds.sh           # DS management utilities
│   ├── updatejava21.sh        # Java update script
│   └── updatetomcat10.sh      # Tomcat update script
└── software/                    # Installation binaries
    ├── am/                     # AM software files
    ├── ds/                     # DS software files
    ├── idm/                    # IDM software files
    ├── ig/                     # IG software files
    └── ui/                     # UI software files
```

## Prerequisites

### System Requirements
- **Operating System:** Linux/macOS
- **Java:** OpenJDK 21 or higher
- **Apache Tomcat:** 10.x
- **Memory:** Minimum 16GB RAM recommended
- **Storage:** 20GB free space

### Required Software Binaries
Place the following ForgeRock software in the `software/` directories:

```bash
software/
├── am/
│   ├── AM-8.0.1.war
│   └── Amster-8.0.1.zip
├── ds/
│   └── DS-8.0.0.zip
├── idm/
│   └── IDM-8.0.0.zip
├── ig/
│   └── PingGateway-2025.3.0.zip
└── ui/
    └── PlatformUI-8.0.1.0523.zip
```

### Network Configuration
Ensure the following hostnames are resolvable (add to `/etc/hosts` if needed):

```
127.0.0.1   am.example.com
127.0.0.1   openidm.example.com
127.0.0.1   platform.example.com
127.0.0.1   login.example.com
127.0.0.1   admin.example.com
127.0.0.1   enduser.example.com
127.0.0.1   cts1.example.com
127.0.0.1   amconfig1.example.com
127.0.0.1   idrepo1.example.com
```

## Installation

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd Platform8Install
   ```

2. **Place software binaries** in appropriate `software/` subdirectories

3. **Review configuration:**
   ```bash
   vim platformconfig.env
   ```

4. **Run installation:**
   ```bash
   chmod +x install_platform8.sh
   sudo ./install_platform8.sh
   ```

5. **Select configuration mode:**
   - Enter `1` for File-Based Configuration (FBC) mode
   - Enter `2` for DS-based configuration mode

### Installation Process

The installation proceeds through these automated steps:

1. **Stop IDM** - Gracefully stops any running IDM processes
2. **Cleanup AM** - Removes previous AM installation artifacts
3. **Configure DS** - Sets up directory service instances
4. **Deploy AM** - Installs AM with chosen configuration mode
5. **Deploy IDM** - Configures identity management services
6. **Deploy IG** - Sets up identity gateway with routes
7. **Configure AM** - Applies REST-based AM configuration
8. **Deploy UI** - Installs platform user interfaces

## Configuration

### Core Configuration File

The `platformconfig.env` file contains all deployment parameters:

```bash
# Key configuration sections:
INSTALL_USER="fradmin"                    # Installation user
DEFAULT_PASSWORD="password"              # Default passwords
AM_HOSTNAME="am.example.com"            # AM server hostname
IDM_HOSTNAME="openidm.example.com"      # IDM server hostname
IG_HOSTNAME="platform.example.com"      # IG hostname
COOKIE_DOMAIN="example.com"             # Session cookie domain
```

### Port Configuration

| Component | HTTP Port | HTTPS Port | Admin Port |
|-----------|-----------|------------|------------|
| AM        | 8081      | -          | -          |
| IDM       | 8080      | 8553       | 9444       |
| IG        | 7080      | 9443       | -          |
| DS IdRepo | 28081     | 28443      | 24444      |
| DS Config | 38081     | 38443      | 34444      |
| DS CTS    | 18081     | 18443      | 14444      |
| UI Admin  | 8082      | -          | -          |
| UI Login  | 8083      | -          | -          |
| UI EndUser| 8888      | -          | -          |

## Usage

### Access URLs

After successful installation, access the platform components:


- **Platform Gateway:** https://platform.example.com:9443

### Default Credentials

- **Username:** `amadmin` (AM), `openidm-admin` (IDM)
- **Password:** `password` (configurable in `platformconfig.env`)

### Management Scripts

#### Directory Services Management
```bash
# Start/stop DS instances
./misc/manage-ds.sh start
./misc/manage-ds.sh stop
./misc/manage-ds.sh status
```

#### Component Scripts
```bash
# Individual component deployment
./ds/ds8.sh              # Deploy DS
./am/am8.sh              # Deploy AM (DS mode)
./am/am8fbc.sh           # Deploy AM (FBC mode)
./idm/idm8.sh            # Deploy IDM
./ig/ig8.sh              # Deploy IG
./ui/platformui.sh       # Deploy UI
```

## Authentication Trees

The installation includes pre-configured authentication trees:

- **PlatformLogin** - Standard username/password authentication
- **PlatformRegistration** - User self-registration
- **PlatformResetPassword** - Password reset flow
- **PlatformProgressiveProfile** - Progressive profiling
- **Google-DynamicAccountCreation** - Social login with account creation
- **Facebook-ProvisionIDMAccount** - Facebook social authentication

## Troubleshooting

### Common Issues

1. **Port Conflicts**
   - Check if required ports are available: `netstat -tulpn | grep :8081`
   - Modify port configurations in `platformconfig.env`

2. **Hostname Resolution**
   - Verify `/etc/hosts` entries
   - Test with `ping am.example.com`

3. **Permission Issues**
   - Ensure script executable permissions: `chmod +x *.sh`
   - Run with appropriate user privileges

4. **Software Binary Issues**
   - Verify all required software files are present
   - Check file integrity and versions

### Log Locations

- **AM Logs:** `${TOMCAT_DIR}/logs/catalina.out`
- **IDM Logs:** `${IDM_EXTRACT_DIR}/logs/openidm*.log`
- **DS Logs:** `${DS_DIR}/*/logs/errors`
- **IG Logs:** `${IG_DIR}/logs/`

### Cleanup and Reinstall

To perform a clean reinstall:

```bash
# Stop all services
sudo systemctl stop tomcat
./misc/manage-ds.sh stop

# Clean installation directories
sudo rm -rf /opt/ping/
sudo rm -rf ~/.openamcfg/
sudo rm -rf ~/.openig/
sudo rm -rf ${HOME}/openam/

# Restart installation
./install_platform8.sh
```

## License

This project is provided as-is for ForgeRock platform deployment automation. Refer to ForgeRock licensing for individual component usage rights.

---

**Note:** This installation suite is designed for development and testing environments. Additional hardening and configuration is required for production deployments.