#!/bin/bash

# Get WireGuard Server Configuration from Azure
# This script retrieves the WireGuard server configuration after Terraform deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Get WireGuard Server Configuration ===${NC}"
echo

# Check if terraform.tfstate exists
if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}terraform.tfstate not found. Please run 'terraform apply' first.${NC}"
    exit 1
fi

# Get WireGuard VPN server FQDN from terraform output
echo -e "${YELLOW}Getting WireGuard VPN server details...${NC}"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq for JSON parsing...${NC}"
    if [[ -f /etc/debian_version ]]; then
        sudo apt update && sudo apt install -y jq
    elif [[ -f /etc/redhat-release ]]; then
        if command -v dnf &> /dev/null; then
            sudo dnf install -y jq
        else
            sudo yum install -y jq
        fi
    else
        echo -e "${RED}Please install jq manually to parse Terraform output${NC}"
        exit 1
    fi
fi

# Get VPN server details from terraform output
VPN_SERVER_FQDN=$(terraform output -raw wireguard_vpn_url 2>/dev/null || echo "")
VPN_SERVER_PORT=$(terraform output -raw wireguard_vpn_port 2>/dev/null || echo "51820")

if [[ -z "$VPN_SERVER_FQDN" ]]; then
    echo -e "${RED}Could not get VPN server FQDN from Terraform output${NC}"
    echo -e "${YELLOW}Please run 'terraform apply' first, then try again${NC}"
    exit 1
fi

echo -e "${GREEN}VPN Server FQDN: ${VPN_SERVER_FQDN}${NC}"
echo -e "${GREEN}VPN Server Port: ${VPN_SERVER_PORT}${NC}"

# Create configuration directory
CONFIG_DIR="./wireguard-config"
mkdir -p "$CONFIG_DIR"

# Create server info file
cat > "$CONFIG_DIR/server-info.txt" << EOF
WireGuard VPN Server Configuration
==================================

Server FQDN: ${VPN_SERVER_FQDN}
Server Port: ${VPN_SERVER_PORT}
Protocol: UDP

Client Configuration:
- Client IP: 10.0.0.2/24
- Allowed IPs: 10.0.0.0/24, 10.0.1.0/24
- DNS: 8.8.8.8, 8.8.4.4

Next Steps:
1. Run the WireGuard client setup script on your Linux VM
2. Get the client public key from the setup script
3. Add the client public key to the Azure WireGuard server
4. Get the server public key and update the client configuration
5. Test the connection

Useful Commands:
- Check VPN status: wg show
- Test connectivity: ping 10.0.0.1
- Check routes: ip route show table all | grep wg0
EOF

echo -e "${GREEN}Server information saved to: $CONFIG_DIR/server-info.txt${NC}"

# Create client configuration template
cat > "$CONFIG_DIR/client-template.conf" << EOF
[Interface]
PrivateKey = YOUR_CLIENT_PRIVATE_KEY
Address = 10.0.0.2/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = SERVER_PUBLIC_KEY_PLACEHOLDER
Endpoint = ${VPN_SERVER_FQDN}:${VPN_SERVER_PORT}
AllowedIPs = 10.0.0.0/24, 10.0.1.0/24
PersistentKeepalive = 25
EOF

echo -e "${GREEN}Client configuration template saved to: $CONFIG_DIR/client-template.conf${NC}"

# Instructions for getting server configuration
echo -e "${BLUE}=== Next Steps ===${NC}"
echo
echo -e "${YELLOW}1. Deploy the Terraform infrastructure:${NC}"
echo "   terraform apply"
echo
echo -e "${YELLOW}2. Get the WireGuard server configuration:${NC}"
echo "   # The WireGuard container will generate configuration files"
echo "   # You can access them through the container logs or by connecting to the container"
echo
echo -e "${YELLOW}3. On your Linux VM, run the client setup script:${NC}"
echo "   chmod +x setup-wireguard-client.sh"
echo "   ./setup-wireguard-client.sh"
echo
echo -e "${YELLOW}4. Get the server public key:${NC}"
echo "   # After deployment, you can get this from the WireGuard container logs"
echo "   # or by connecting to the container and checking /config/wg0.conf"
echo
echo -e "${YELLOW}5. Update the client configuration:${NC}"
echo "   # Replace SERVER_PUBLIC_KEY_PLACEHOLDER with the actual server public key"
echo "   # Replace YOUR_CLIENT_PRIVATE_KEY with the generated private key"
echo
echo -e "${GREEN}Configuration files saved to: $CONFIG_DIR/${NC}"

# Create a script to get server config from container logs
cat > "$CONFIG_DIR/get-server-config.sh" << 'EOF'
#!/bin/bash

# Get WireGuard server configuration from container logs
# Run this after terraform apply

set -e

echo "Getting WireGuard server configuration from Azure container..."

# Get the container app name
CONTAINER_APP_NAME="wireguard-vpn-server"

# Get the resource group
RESOURCE_GROUP="Cissconnects-MCP"

# Get container logs
echo "Fetching container logs..."
az containerapp logs show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --follow false \
  --tail 100

echo
echo "To get the server public key, look for lines containing 'PublicKey' in the logs"
echo "The server configuration should be in /config/wg0.conf inside the container"
echo
echo "You can also exec into the container to get the configuration:"
echo "az containerapp exec --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP"
EOF

chmod +x "$CONFIG_DIR/get-server-config.sh"

echo -e "${GREEN}Server config retrieval script created: $CONFIG_DIR/get-server-config.sh${NC}"
echo
echo -e "${BLUE}All configuration files are ready in: $CONFIG_DIR${NC}" 