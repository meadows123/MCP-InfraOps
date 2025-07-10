#!/bin/bash

# WireGuard Server Setup Script for Linux VM
# This script sets up a WireGuard server on your Linux VM (10.0.0.1)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== WireGuard Server Setup for Linux VM ===${NC}"
echo -e "${YELLOW}Server IP: 10.0.0.1${NC}"
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

# Generate server private key
if [[ ! -f "$WIREGUARD_DIR/server_private.key" ]]; then
    echo -e "${YELLOW}Generating server private key...${NC}"
    wg genkey | tee "$WIREGUARD_DIR/server_private.key" | wg pubkey > "$WIREGUARD_DIR/server_public.key"
    chmod 600 "$WIREGUARD_DIR/server_private.key"
    chmod 600 "$WIREGUARD_DIR/server_public.key"
fi

# Get server public key
SERVER_PUBLIC_KEY=$(cat "$WIREGUARD_DIR/server_public.key")
echo -e "${GREEN}Server public key: ${SERVER_PUBLIC_KEY}${NC}"

# Get Azure client public key
echo -e "${YELLOW}Please provide the Azure client public key:${NC}"
read -p "Azure Client Public Key: " AZURE_CLIENT_PUBLIC_KEY

if [[ -z "$AZURE_CLIENT_PUBLIC_KEY" ]]; then
    echo -e "${RED}Azure client public key is required${NC}"
    exit 1
fi

# Get your public IP address
echo -e "${YELLOW}Detecting your public IP address...${NC}"
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "YOUR_PUBLIC_IP")

echo -e "${GREEN}Your public IP: ${PUBLIC_IP}${NC}"
echo -e "${YELLOW}If this is incorrect, please provide your actual public IP:${NC}"
read -p "Public IP (press Enter to use detected): " MANUAL_IP

if [[ -n "$MANUAL_IP" ]]; then
    PUBLIC_IP="$MANUAL_IP"
fi

# Create WireGuard server configuration
echo -e "${YELLOW}Creating WireGuard server configuration...${NC}"

cat > "$WIREGUARD_DIR/wg0.conf" << EOF
[Interface]
PrivateKey = $(cat "$WIREGUARD_DIR/server_private.key")
Address = 10.0.0.1/24
ListenPort = 51820
SaveConfig = true

# Enable IP forwarding
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT

[Peer]
# Azure Client
PublicKey = ${AZURE_CLIENT_PUBLIC_KEY}
AllowedIPs = 10.0.0.2/32, 10.0.1.0/24
PersistentKeepalive = 25
EOF

echo -e "${GREEN}WireGuard server configuration created at: $WIREGUARD_DIR/wg0.conf${NC}"

# Create systemd service for auto-start
echo -e "${YELLOW}Creating systemd service...${NC}"

sudo tee /etc/systemd/system/wg-server.service > /dev/null << EOF
[Unit]
Description=WireGuard VPN Server
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
sudo systemctl enable wg-server.service

echo -e "${GREEN}Systemd service created and enabled${NC}"

# Create management scripts
cat > "$WIREGUARD_DIR/start-server.sh" << 'EOF'
#!/bin/bash
# WireGuard server start script

WIREGUARD_DIR="$HOME/.wireguard"

echo "Starting WireGuard server..."
sudo wg-quick up "$WIREGUARD_DIR/wg0.conf"

if [[ $? -eq 0 ]]; then
    echo "✅ WireGuard server started"
    echo "Server IP: 10.0.0.1"
    echo "Listening on port: 51820"
else
    echo "❌ Failed to start WireGuard server"
    exit 1
fi
EOF

chmod +x "$WIREGUARD_DIR/start-server.sh"

cat > "$WIREGUARD_DIR/stop-server.sh" << 'EOF'
#!/bin/bash
# WireGuard server stop script

WIREGUARD_DIR="$HOME/.wireguard"

echo "Stopping WireGuard server..."
sudo wg-quick down "$WIREGUARD_DIR/wg0.conf"

if [[ $? -eq 0 ]]; then
    echo "✅ WireGuard server stopped"
else
    echo "❌ Failed to stop WireGuard server"
    exit 1
fi
EOF

chmod +x "$WIREGUARD_DIR/stop-server.sh"

cat > "$WIREGUARD_DIR/server-status.sh" << 'EOF'
#!/bin/bash
# WireGuard server status script

WIREGUARD_DIR="$HOME/.wireguard"

echo "=== WireGuard Server Status ==="
echo

if sudo wg show wg0 >/dev/null 2>&1; then
    echo "✅ Server is running"
    echo
    echo "Interface details:"
    sudo wg show wg0
    echo
    echo "Server IP: 10.0.0.1"
    echo "Listening Port: 51820"
    echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unknown')"
else
    echo "❌ Server is not running"
fi

echo
echo "Configuration file: $WIREGUARD_DIR/wg0.conf"
echo "Service status: $(systemctl is-active wg-server.service)"
EOF

chmod +x "$WIREGUARD_DIR/server-status.sh"

# Create Azure client configuration template
cat > "$WIREGUARD_DIR/azure-client-template.conf" << EOF
[Interface]
PrivateKey = AZURE_CLIENT_PRIVATE_KEY_PLACEHOLDER
Address = 10.0.0.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${PUBLIC_IP}:51820
AllowedIPs = 10.0.0.0/24, 10.0.1.0/24
PersistentKeepalive = 25
EOF

echo -e "${GREEN}Azure client configuration template created: $WIREGUARD_DIR/azure-client-template.conf${NC}"

echo -e "${GREEN}Setup complete!${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. Start the WireGuard server: $WIREGUARD_DIR/start-server.sh"
echo "2. Open port 51820/UDP on your firewall/router"
echo "3. Configure Azure client with the template configuration"
echo "4. Test the connection from Azure: ping 10.0.0.1"
echo
echo -e "${BLUE}Useful commands:${NC}"
echo "  Start server:    $WIREGUARD_DIR/start-server.sh"
echo "  Stop server:     $WIREGUARD_DIR/stop-server.sh"
echo "  Server status:   $WIREGUARD_DIR/server-status.sh"
echo "  Auto-start:      sudo systemctl start wg-server.service"
echo
echo -e "${BLUE}Important information:${NC}"
echo "  Server Public Key: ${SERVER_PUBLIC_KEY}"
echo "  Server Public IP:  ${PUBLIC_IP}"
echo "  Server Port:       51820"
echo "  Server IP:         10.0.0.1"
echo "  Azure Client IP:   10.0.0.2"
echo
echo -e "${YELLOW}Don't forget to open port 51820/UDP on your firewall/router!${NC}" 