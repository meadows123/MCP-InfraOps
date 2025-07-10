#!/bin/bash

# WireGuard Key Generation and Configuration Script
# This script helps you generate WireGuard keys and configure terraform.tfvars

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== WireGuard Key Generation and Configuration ===${NC}"
echo

# Check if WireGuard is installed
if ! command -v wg &> /dev/null; then
    echo -e "${YELLOW}WireGuard not found. Installing...${NC}"
    
    if [[ -f /etc/debian_version ]]; then
        sudo apt update
        sudo apt install -y wireguard wireguard-tools
    elif [[ -f /etc/redhat-release ]]; then
        if command -v dnf &> /dev/null; then
            sudo dnf install -y wireguard-tools
        else
            sudo yum install -y wireguard-tools
        fi
    else
        echo -e "${RED}Please install WireGuard manually and run this script again.${NC}"
        exit 1
    fi
fi

# Create keys directory
KEYS_DIR="./wireguard-keys"
mkdir -p "$KEYS_DIR"

# Generate Azure client keys
echo -e "${YELLOW}Generating Azure WireGuard client keys...${NC}"
wg genkey | tee "$KEYS_DIR/azure_client_private.key" | wg pubkey > "$KEYS_DIR/azure_client_public.key"
chmod 600 "$KEYS_DIR/azure_client_private.key"
chmod 600 "$KEYS_DIR/azure_client_public.key"

AZURE_CLIENT_PRIVATE_KEY=$(cat "$KEYS_DIR/azure_client_private.key")
AZURE_CLIENT_PUBLIC_KEY=$(cat "$KEYS_DIR/azure_client_public.key")

echo -e "${GREEN}Azure client keys generated:${NC}"
echo -e "Private Key: ${AZURE_CLIENT_PRIVATE_KEY}"
echo -e "Public Key:  ${AZURE_CLIENT_PUBLIC_KEY}"
echo

# Get SSH public key
echo -e "${YELLOW}SSH Public Key Setup:${NC}"
echo -e "Please provide your SSH public key for accessing the Azure VM."
echo -e "If you don't have one, you can generate it with: ssh-keygen -t rsa -b 4096"
echo

read -p "Enter your SSH public key (or press Enter to use default): " SSH_PUBLIC_KEY

if [[ -z "$SSH_PUBLIC_KEY" ]]; then
    # Try to find existing SSH key
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        SSH_PUBLIC_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
        echo -e "${GREEN}Using existing SSH key: $HOME/.ssh/id_rsa.pub${NC}"
    else
        echo -e "${RED}No SSH public key found. Please generate one with: ssh-keygen -t rsa -b 4096${NC}"
        exit 1
    fi
fi

# Get home server configuration
echo -e "${YELLOW}Home WireGuard Server Configuration:${NC}"
echo -e "You need to provide your home WireGuard server details."
echo

read -p "Enter your home server's public key: " HOME_SERVER_PUBLIC_KEY
read -p "Enter your home server's public IP: " HOME_SERVER_IP
read -p "Enter your home server's WireGuard port (default: 51820): " HOME_SERVER_PORT

HOME_SERVER_PORT=${HOME_SERVER_PORT:-51820}
HOME_SERVER_ENDPOINT="${HOME_SERVER_IP}:${HOME_SERVER_PORT}"

# Update terraform.tfvars
echo -e "${YELLOW}Updating terraform.tfvars...${NC}"

cat > terraform.tfvars << EOF
# Terraform Variables Configuration
# Generated on $(date)

# SSH Configuration for Azure VM
admin_ssh_public_key = "${SSH_PUBLIC_KEY}"

# WireGuard Configuration
wireguard_client_private_key = "${AZURE_CLIENT_PRIVATE_KEY}"
wireguard_client_public_key  = "${AZURE_CLIENT_PUBLIC_KEY}"

# Your Home WireGuard Server Configuration
home_wireguard_server_public_key = "${HOME_SERVER_PUBLIC_KEY}"
home_wireguard_server_endpoint   = "${HOME_SERVER_ENDPOINT}"
EOF

echo -e "${GREEN}terraform.tfvars updated successfully!${NC}"
echo

# Create home server configuration template
echo -e "${YELLOW}Creating home server configuration template...${NC}"

cat > "$KEYS_DIR/home_server_peer_config.txt" << EOF
# Add this peer configuration to your home WireGuard server
# File: /etc/wireguard/wg0.conf (on your home Linux VM)

[Peer]
# Azure Client VM
PublicKey = ${AZURE_CLIENT_PUBLIC_KEY}
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25
EOF

echo -e "${GREEN}Home server peer configuration saved to: $KEYS_DIR/home_server_peer_config.txt${NC}"
echo

# Show next steps
echo -e "${BLUE}=== Next Steps ===${NC}"
echo
echo -e "${YELLOW}1. Update your home WireGuard server:${NC}"
echo -e "   Add the peer configuration from: $KEYS_DIR/home_server_peer_config.txt"
echo -e "   to your home server's /etc/wireguard/wg0.conf"
echo
echo -e "${YELLOW}2. Restart your home WireGuard server:${NC}"
echo -e "   sudo systemctl restart wg-quick@wg0"
echo
echo -e "${YELLOW}3. Deploy the Azure infrastructure:${NC}"
echo -e "   terraform init"
echo -e "   terraform plan"
echo -e "   terraform apply"
echo
echo -e "${YELLOW}4. Test the connection:${NC}"
echo -e "   ssh azureuser@<AZURE_VM_PUBLIC_IP>"
echo -e "   sudo wg show"
echo -e "   ping 10.0.0.1  # Should reach your home server"
echo
echo -e "${GREEN}Configuration complete!${NC}"
echo -e "Keys saved in: $KEYS_DIR/"
echo -e "terraform.tfvars updated with your values" 