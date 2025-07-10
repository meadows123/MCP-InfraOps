#!/bin/bash

# MCP Development Session Script
# This script automates the deploy and destroy cycle for cost-effective development

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_SESSION_HOURS=4
DEFAULT_SESSION_MINUTES=0

# Function to display usage
show_usage() {
    echo -e "${BLUE}MCP Development Session Manager${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --hours HOURS     Session duration in hours (default: $DEFAULT_SESSION_HOURS)"
    echo "  -m, --minutes MINUTES Session duration in minutes (default: $DEFAULT_SESSION_MINUTES)"
    echo "  -d, --deploy-only     Only deploy, don't auto-destroy"
    echo "  -s, --skip-confirm    Skip confirmation prompts"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # 4-hour session (default)"
    echo "  $0 -h 2               # 2-hour session"
    echo "  $0 -h 1 -m 30         # 1.5-hour session"
    echo "  $0 -d                 # Deploy only, manual destroy"
    echo ""
}

# Function to calculate session duration
calculate_duration() {
    local hours=$1
    local minutes=$2
    local total_seconds=$((hours * 3600 + minutes * 60))
    echo $total_seconds
}

# Function to format time
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Function to deploy infrastructure
deploy_infrastructure() {
    echo -e "${BLUE}🚀 Deploying MCP Infrastructure...${NC}"
    echo ""
    
    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
        echo -e "${YELLOW}📦 Initializing Terraform...${NC}"
        terraform init
    fi
    
    # Plan the deployment
    echo -e "${YELLOW}📋 Planning deployment...${NC}"
    terraform plan -out=tfplan
    
    # Apply the deployment
    echo -e "${YELLOW}🔨 Applying infrastructure...${NC}"
    terraform apply tfplan
    
    echo -e "${GREEN}✅ Infrastructure deployed successfully!${NC}"
    echo ""
    
    # Show important URLs
    echo -e "${BLUE}📋 Important URLs:${NC}"
    echo -e "Frontend: ${GREEN}$(terraform output -raw frontend_url)${NC}"
    echo -e "Orchestrator: ${GREEN}$(terraform output -raw orchestrator_url)${NC}"
    echo -e "WireGuard Client: ${GREEN}$(terraform output -raw wireguard_vpn_client_name)${NC}"
    echo ""
    
    # Show VPN setup instructions
    echo -e "${BLUE}🔐 VPN Setup Instructions:${NC}"
    echo -e "1. Set up WireGuard server on your Linux VM (10.0.0.1):"
    echo -e "   chmod +x setup-wireguard-server.sh"
    echo -e "   ./setup-wireguard-server.sh"
    echo -e "2. Configure Azure client to connect to your server"
    echo -e "3. Test connection: ping 10.0.0.2 (Azure client)"
    echo -e "4. Azure client will connect to your Linux VM server"
    echo ""
    
    # Show cost estimate
    echo -e "${YELLOW}💰 Cost Estimate:${NC}"
    echo -e "  • Container Apps (16 services): ~$0.55-1.05/hour"
    echo -e "  • Storage & Key Vault: ~$0.10/hour"
    echo -e "  • Total: ~$0.65-1.15/hour"
    echo ""
}

# Function to destroy infrastructure
destroy_infrastructure() {
    echo -e "${YELLOW}🗑️  Destroying infrastructure...${NC}"
    terraform destroy -auto-approve
    echo -e "${GREEN}✅ Infrastructure destroyed successfully!${NC}"
    echo ""
    echo -e "${BLUE}💡 All resources removed. No ongoing costs.${NC}"
}

# Function to show session info
show_session_info() {
    local duration_seconds=$1
    local duration_formatted=$(format_time $duration_seconds)
    local estimated_cost=$(echo "scale=2; $duration_seconds / 3600 * 1.10" | bc -l 2>/dev/null || echo "~$1.10")
    
    echo -e "${BLUE}📅 Session Information:${NC}"
    echo -e "  Duration: ${GREEN}$duration_formatted${NC}"
    echo -e "  Estimated Cost: ${GREEN}$estimated_cost${NC}"
    echo -e "  Auto-destroy: ${GREEN}Yes${NC}"
    echo ""
}

# Function to countdown timer
countdown_timer() {
    local seconds=$1
    
    echo -e "${YELLOW}⏰ Session timer started. Auto-destroy in $(format_time $seconds)${NC}"
    echo -e "${BLUE}Press Ctrl+C to stop the timer and destroy manually${NC}"
    echo ""
    
    while [ $seconds -gt 0 ]; do
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        local secs=$((seconds % 60))
        
        printf "\r⏰ Time remaining: %02d:%02d:%02d" $hours $minutes $secs
        sleep 1
        seconds=$((seconds - 1))
    done
    
    echo ""
    echo -e "${YELLOW}⏰ Session time expired!${NC}"
}

# Parse command line arguments
SESSION_HOURS=$DEFAULT_SESSION_HOURS
SESSION_MINUTES=$DEFAULT_SESSION_MINUTES
DEPLOY_ONLY=false
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--hours)
            SESSION_HOURS="$2"
            shift 2
            ;;
        -m|--minutes)
            SESSION_MINUTES="$2"
            shift 2
            ;;
        -d|--deploy-only)
            DEPLOY_ONLY=true
            shift
            ;;
        -s|--skip-confirm)
            SKIP_CONFIRM=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Calculate session duration
SESSION_DURATION=$(calculate_duration $SESSION_HOURS $SESSION_MINUTES)

# Show session info
show_session_info $SESSION_DURATION

# Confirmation prompt
if [ "$SKIP_CONFIRM" = false ]; then
    echo -e "${YELLOW}⚠️  This will deploy MCP infrastructure for $(format_time $SESSION_DURATION)${NC}"
    echo -e "${YELLOW}Estimated cost: ~$(echo "scale=2; $SESSION_DURATION / 3600 * 1.10" | bc -l 2>/dev/null || echo "$1.10")${NC}"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}👋 Session cancelled.${NC}"
        exit 0
    fi
fi

# Deploy infrastructure
deploy_infrastructure

# If deploy-only mode, exit here
if [ "$DEPLOY_ONLY" = true ]; then
    echo -e "${BLUE}🔧 Deploy-only mode. Infrastructure will remain running.${NC}"
    echo -e "${YELLOW}💡 Run 'terraform destroy' manually when done.${NC}"
    exit 0
fi

# Start countdown timer
countdown_timer $SESSION_DURATION

# Destroy infrastructure
destroy_infrastructure

echo -e "${GREEN}🎉 Development session completed!${NC}" 