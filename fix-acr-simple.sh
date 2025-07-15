#!/bin/bash

# Fix ACR Registry Blocks in main.tf
# This script updates registry blocks to use direct ACR credentials instead of managed identity

echo "Fixing ACR registry blocks in main.tf..."

# Navigate to the terraform directory
cd terraformazure/mcp-ai-test

# Check if main.tf exists
if [ ! -f "main.tf" ]; then
    echo "Error: main.tf not found in terraformazure/mcp-ai-test/"
    exit 1
fi

# Create a backup
cp main.tf main.tf.backup
echo "Created backup: main.tf.backup"

# Fix registry blocks - replace identity = null with username and password_secret_name
sed -i 's/identity = null/username = azurerm_container_registry.acr.admin_username\n      password_secret_name = "acr-password"/g' main.tf

# Fix any remaining registry blocks that might have different formatting
sed -i 's/registry {/registry {\n      username = azurerm_container_registry.acr.admin_username\n      password_secret_name = "acr-password"/g' main.tf

# Remove any duplicate username/password lines that might have been created
sed -i '/username = azurerm_container_registry.acr.admin_username/{N;/username = azurerm_container_registry.acr.admin_username/d}' main.tf

echo "Registry blocks updated successfully!"
echo "You can now run: terraform apply" 