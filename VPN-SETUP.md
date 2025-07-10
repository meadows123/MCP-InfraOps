# WireGuard VPN Setup Guide

This guide explains how to set up a secure WireGuard VPN connection between your Azure MCP infrastructure and your home network (CML2.0 server).

## Overview

The Terraform configuration includes a WireGuard VPN server running in Azure that allows secure access to your MCP containers from your home network. This enables:

- Secure access to MCP services from your CML2.0 server
- Network device testing and automation
- Isolated network communication
- Cost-effective development and testing

## Architecture

```
Azure MCP Infrastructure ←→ WireGuard VPN ←→ Home Network (CML2.0)
    10.0.0.2                   10.0.0.1             10.0.0.0/24
```

**Note**: Your Linux VM acts as the WireGuard server (10.0.0.1), and Azure containers connect as clients (10.0.0.2).

## Prerequisites

1. **Azure Infrastructure**: Deployed using Terraform
2. **Linux VM**: Running on your Windows Server (for WireGuard client)
3. **Network Access**: Port 51820/UDP open on Azure

## Step 1: Deploy Azure Infrastructure

```bash
# Navigate to the Terraform directory
cd terraformazure/mcp-ai-test

# Deploy the infrastructure
./dev-session.sh -d  # Deploy only mode
```

This will create:
- 16 Container Apps (including WireGuard VPN server)
- Key Vault for secrets
- Storage Account for data
- All using your existing Azure resources

## Step 2: Get VPN Server Configuration

After deployment, get the VPN server details:

```bash
# Get server configuration
chmod +x get-wireguard-config.sh
./get-wireguard-config.sh
```

This will:
- Extract VPN server FQDN and port from Terraform output
- Create configuration templates
- Save server information to `wireguard-config/` directory

## Step 3: Set Up Linux VM on Windows Server

### Option A: Create a Lightweight Linux VM

1. **Install Hyper-V** (if not already installed):
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
   ```

2. **Create Ubuntu VM**:
   - Download Ubuntu Server 22.04 LTS
   - Create VM with minimal resources (1 CPU, 1GB RAM, 10GB disk)
   - Enable nested virtualization if needed

3. **Network Configuration**:
   - Set VM to use external network adapter
   - Ensure VM can access internet

### Option B: Use WSL2 (Windows Subsystem for Linux)

```powershell
# Install WSL2
wsl --install -d Ubuntu

# Update and install WireGuard
wsl
sudo apt update
sudo apt install -y wireguard wireguard-tools
```

## Step 4: Configure WireGuard Client

On your Linux VM:

```bash
# Copy the setup script to your Linux VM
scp setup-wireguard-client.sh user@your-linux-vm:/home/user/

# On the Linux VM, run the setup
chmod +x setup-wireguard-client.sh
./setup-wireguard-client.sh
```

The script will:
- Install WireGuard if needed
- Generate client keys
- Create configuration files
- Set up systemd service
- Create connection/disconnection scripts

## Step 5: Get Server Public Key

After the WireGuard container starts in Azure, get the server configuration:

```bash
# Get server logs to find the public key
az containerapp logs show \
  --name "wireguard-vpn-server" \
  --resource-group "Cissconnects-MCP" \
  --follow false \
  --tail 100
```

Look for lines containing:
- `PublicKey = <server-public-key>`
- `Interface = wg0`
- `Address = 10.0.0.1/24`

## Step 6: Update Client Configuration

On your Linux VM, edit the WireGuard configuration:

```bash
nano ~/.wireguard/wg0.conf
```

Replace `SERVER_PUBLIC_KEY_PLACEHOLDER` with the actual server public key from Step 5.

## Step 7: Test VPN Connection

On your Linux VM:

```bash
# Connect to VPN
~/.wireguard/connect.sh

# Test connectivity
ping 10.0.0.1  # Should reach Azure VPN server
ping 10.0.0.10 # Should reach MCP containers

# Check VPN status
~/.wireguard/status.sh

# Test MCP service access
curl https://10.0.0.10:3000  # Replace with actual container IP
```

## Step 8: Configure Network Routing

### For CML2.0 Access

If you need to access CML2.0 from Azure containers:

1. **Add route on Linux VM**:
   ```bash
   # Add route to CML2.0 network
   sudo ip route add 192.168.1.0/24 via 10.0.0.2 dev wg0
   ```

2. **Configure Azure containers** to route traffic through VPN:
   - Containers are already configured with VPN environment variables
   - They can access the 10.0.0.0/24 network

### For External Network Access

If you need Azure containers to access your home network:

1. **Enable IP forwarding on Linux VM**:
   ```bash
   echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
   sudo sysctl -w net.ipv4.ip_forward=1
   ```

2. **Add iptables rules**:
   ```bash
   sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
   sudo iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
   sudo iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT
   ```

## Troubleshooting

### Common Issues

1. **Connection Timeout**:
   - Check Azure firewall rules
   - Verify port 51820/UDP is open
   - Check WireGuard container logs

2. **No Route to Host**:
   - Verify VPN is connected: `wg show`
   - Check routing table: `ip route show`
   - Ensure containers are in VPN subnet

3. **Authentication Failed**:
   - Verify public/private key pairs
   - Check WireGuard configuration syntax
   - Restart WireGuard service

### Debug Commands

```bash
# Check VPN status
sudo wg show

# Check routing
ip route show table all | grep wg0

# Check WireGuard logs
sudo journalctl -u wg-azure-mcp.service -f

# Test connectivity
traceroute 10.0.0.1
```

### Azure Container Logs

```bash
# Get WireGuard container logs
az containerapp logs show \
  --name "wireguard-vpn-server" \
  --resource-group "Cissconnects-MCP" \
  --follow true

# Exec into container
az containerapp exec \
  --name "wireguard-vpn-server" \
  --resource-group "Cissconnects-MCP"
```

## Security Considerations

1. **Key Management**: Keep private keys secure
2. **Network Isolation**: VPN traffic is encrypted
3. **Access Control**: Only authorized clients can connect
4. **Monitoring**: Monitor VPN connections and traffic

## Cost Optimization

- VPN server uses minimal resources (0.25 CPU, 512MB RAM)
- Additional cost: ~$0.05-0.10/hour
- Use development sessions to minimize costs
- Destroy infrastructure when not in use

## Next Steps

1. **Test MCP Services**: Verify all services are accessible via VPN
2. **Configure Automation**: Set up automated testing workflows
3. **Monitor Performance**: Track VPN performance and stability
4. **Scale as Needed**: Add more clients or adjust resources

## Support

For issues with:
- **Azure Infrastructure**: Check Terraform logs and Azure portal
- **VPN Connection**: Use troubleshooting commands above
- **MCP Services**: Check container logs and service endpoints 