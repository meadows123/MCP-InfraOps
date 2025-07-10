#!/bin/bash

# WireGuard Client Setup Script for Linux VM
# This script sets up a WireGuard client to connect to the Azure VPN server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== WireGuard Client Setup for Azure MCP VPN ===${NC}"
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${RED}This script should not be run as root${NC}"
   exit 1
fi

# Check if WireGuard is installed
if ! command -v wg &> /dev/null; then
    echo -e "${YELLOW}WireGuard not found. Installing...${NC}"
    
    # Detect OS and install WireGuard
    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo apt update
        sudo apt install -y wireguard wireguard-tools
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/Fedora
        if command -v dnf &> /dev/null; then
            sudo dnf install -y wireguard-tools
        else
            sudo yum install -y wireguard-tools
        fi
    else
        echo -e "${RED}Unsupported OS. Please install WireGuard manually.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}WireGuard is installed${NC}"

# Create WireGuard configuration directory
WIREGUARD_DIR="$HOME/.wireguard"
mkdir -p "$WIREGUARD_DIR"

# Generate client private key
if [[ ! -f "$WIREGUARD_DIR/private.key" ]]; then
    echo -e "${YELLOW}Generating client private key...${NC}"
    wg genkey | tee "$WIREGUARD_DIR/private.key" | wg pubkey > "$WIREGUARD_DIR/public.key"
    chmod 600 "$WIREGUARD_DIR/private.key"
    chmod 600 "$WIREGUARD_DIR/public.key"
fi

# Get client public key
CLIENT_PUBLIC_KEY=$(cat "$WIREGUARD_DIR/public.key")
echo -e "${GREEN}Client public key: ${CLIENT_PUBLIC_KEY}${NC}"

# Get Azure VPN server details
echo -e "${YELLOW}Please provide the following information:${NC}"
read -p "Azure VPN Server FQDN: " VPN_SERVER_FQDN
read -p "Azure VPN Server Port (default: 51820): " VPN_SERVER_PORT
VPN_SERVER_PORT=${VPN_SERVER_PORT:-51820}

# Create WireGuard configuration
echo -e "${YELLOW}Creating WireGuard configuration...${NC}"

cat > "$WIREGUARD_DIR/wg0.conf" << EOF
[Interface]
PrivateKey = $(cat "$WIREGUARD_DIR/private.key")
Address = 10.0.0.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = SERVER_PUBLIC_KEY_PLACEHOLDER
Endpoint = ${VPN_SERVER_FQDN}:${VPN_SERVER_PORT}
AllowedIPs = 10.0.0.0/24, 10.0.1.0/24
PersistentKeepalive = 25
EOF

echo -e "${GREEN}WireGuard configuration created at: $WIREGUARD_DIR/wg0.conf${NC}"

# Create systemd service for auto-start
echo -e "${YELLOW}Creating systemd service...${NC}"

sudo tee /etc/systemd/system/wg-azure-mcp.service > /dev/null << EOF
[Unit]
Description=WireGuard VPN for Azure MCP
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/wg-quick up $WIREGUARD_DIR/wg0.conf
ExecStop=/usr/bin/wg-quick down $WIREGUARD_DIR/wg0.conf
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable wg-azure-mcp.service

echo -e "${GREEN}Systemd service created and enabled${NC}"

# Create connection script
cat > "$WIREGUARD_DIR/connect.sh" << 'EOF'
#!/bin/bash
# WireGuard connection script

WIREGUARD_DIR="$HOME/.wireguard"

echo "Connecting to Azure MCP VPN..."
sudo wg-quick up "$WIREGUARD_DIR/wg0.conf"

if [[ $? -eq 0 ]]; then
    echo "✅ Connected to Azure MCP VPN"
    echo "Your IP: $(ip route get 1.1.1.1 | grep -oP 'src \K\S+')"
    echo "VPN IP: $(ip addr show wg0 2>/dev/null | grep -oP 'inet \K\S+')"
else
    echo "❌ Failed to connect to VPN"
    exit 1
fi
EOF

chmod +x "$WIREGUARD_DIR/connect.sh"

# Create disconnection script
cat > "$WIREGUARD_DIR/disconnect.sh" << 'EOF'
#!/bin/bash
# WireGuard disconnection script

WIREGUARD_DIR="$HOME/.wireguard"

echo "Disconnecting from Azure MCP VPN..."
sudo wg-quick down "$WIREGUARD_DIR/wg0.conf"

if [[ $? -eq 0 ]]; then
    echo "✅ Disconnected from Azure MCP VPN"
else
    echo "❌ Failed to disconnect from VPN"
    exit 1
fi
EOF

chmod +x "$WIREGUARD_DIR/disconnect.sh"

# Create status script
cat > "$WIREGUARD_DIR/status.sh" << 'EOF'
#!/bin/bash
# WireGuard status script

WIREGUARD_DIR="$HOME/.wireguard"

echo "=== WireGuard VPN Status ==="
echo

if sudo wg show wg0 >/dev/null 2>&1; then
    echo "✅ VPN is connected"
    echo
    echo "Interface details:"
    sudo wg show wg0
    echo
    echo "Routing table:"
    ip route show table all | grep wg0 || echo "No VPN routes found"
else
    echo "❌ VPN is not connected"
fi

echo
echo "Configuration file: $WIREGUARD_DIR/wg0.conf"
echo "Service status: $(systemctl is-active wg-azure-mcp.service)"
EOF

chmod +x "$WIREGUARD_DIR/status.sh"

echo -e "${GREEN}Setup complete!${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. Copy your client public key: ${CLIENT_PUBLIC_KEY}"
echo "2. Add this public key to the Azure WireGuard server configuration"
echo "3. Get the server's public key and update the configuration file"
echo "4. Test the connection: $WIREGUARD_DIR/connect.sh"
echo
echo -e "${BLUE}Useful commands:${NC}"
echo "  Connect:    $WIREGUARD_DIR/connect.sh"
echo "  Disconnect: $WIREGUARD_DIR/disconnect.sh"
echo "  Status:     $WIREGUARD_DIR/status.sh"
echo "  Auto-start: sudo systemctl start wg-azure-mcp.service"
echo
echo -e "${YELLOW}Note: You'll need to update the server public key in the configuration file${NC}"
echo "Edit: $WIREGUARD_DIR/wg0.conf"
echo "Replace: SERVER_PUBLIC_KEY_PLACEHOLDER with the actual server public key" 