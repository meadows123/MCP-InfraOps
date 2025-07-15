# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
  # Use Azure CLI authentication (default)
  # If you have multiple subscriptions, you can specify one:
  # subscription_id = "your-subscription-id"
  
  # Explicitly set the Azure CLI path for WSL
  use_cli = true
  skip_provider_registration = true
}


variable "subscription_id" {
  type = string
  description = "Azure subscription ID"
}

variable "client_id" {
  type = string
  description = "Azure client ID"
}

variable "client_secret" {
  type      = string
  sensitive = true
  description = "Azure client secret"
}

variable "tenant_id" {
  type = string
  description = "Azure tenant ID"
}
# Variables
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "Cissconnects-MCP"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "UK South"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

# WireGuard VPN Configuration Variables
# These are for the Azure VM that will connect to your home WireGuard server

# WireGuard Client VM (Azure)
variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

#variable "admin_ssh_public_key" {
  #description = "SSH public key for the VM admin user"
 # type        = string
#}

#variable "home_wireguard_server_public_key" {
  #description = "Public key of your home WireGuard server"
 # type        = string
#}

#variable "home_wireguard_server_endpoint" {
  #description = "Public IP:Port of your home WireGuard server (e.g. 1.2.3.4:51820)"
  #type        = string
#}

#variable "wireguard_client_private_key" {
 # description = "Private key for the Azure WireGuard client VM"
  #type        = string
  #sensitive   = true
#}

#variable "wireguard_client_public_key" {
  #description = "Public key for the Azure WireGuard client VM"
 ## type        = string
#}

# Resource Group - will be created in your tenant
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  
  tags = {
    Environment = var.environment
  }
}

# Container Registry - will be created if it doesn't exist
resource "azurerm_container_registry" "acr" {
  name                = "mcpautomationacr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  
  tags = {
    Environment = var.environment
  }
}

# Container App Environment - will be created if it doesn't exist
resource "azurerm_container_app_environment" "main" {
  name                       = "mcp-automation-env"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  
  # Add Key Vault for Container Apps Environment secrets
  infrastructure_subnet_id = azurerm_subnet.aci.id
  
  tags = {
    Environment = var.environment
  }
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "mcp-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
  tags = {
    Environment = var.environment
  }
}

# Subnet for Container Instances
resource "azurerm_subnet" "aci" {
  name                 = "aci-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/23"]
}

# Storage Account for logs and data (cheapest tier)
resource "azurerm_storage_account" "main" {
  name                     = "mcpautomationstorage"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  
  # Cost optimization: Disable features we don't need
  allow_nested_items_to_be_public = false
  
  tags = {
    Environment = var.environment
  }
}

# File Share for shared data (minimal quota)
resource "azurerm_storage_share" "data" {
  name                 = "mcpshareddata"
  storage_account_name = azurerm_storage_account.main.name
  quota                = 5  # Reduced from 50 to 5 GB
}

# Key Vault for secrets (cheapest configuration)
resource "azurerm_key_vault" "main" {
  name                        = "mcp-automation-kv"
  location                    = azurerm_resource_group.main.location
  resource_group_name         = azurerm_resource_group.main.name
  enabled_for_disk_encryption = false  # Disable if not needed
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                   = "standard"
  
  # Cost optimization: Minimal network rules
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
  
  tags = {
    Environment = var.environment
  }
}

# Get current Azure client config
data "azurerm_client_config" "current" {}

# Key Vault Access Policy (minimal permissions)
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List"
  ]

  secret_permissions = [
    "Get", "List", "Set"
  ]
}

# Store ACR admin password in Key Vault
resource "azurerm_key_vault_secret" "acr_password" {
  name         = "acr-password"
  value        = azurerm_container_registry.acr.admin_password
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_container_registry.acr, azurerm_key_vault_access_policy.terraform]
}

# WireGuard VPN Client VM (Azure) - Replaces the container app approach
# The VM will run WireGuard client and connect to your home server

# Frontend Container App (minimal resources)
resource "azurerm_container_app" "frontend" {
  name                         = "mcp-frontend-app"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  template {
    container {
      name   = "frontend"
      image  = "${azurerm_container_registry.acr.login_server}/mcp-frontend:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "VITE_API_BASE_URL"
        value = "https://${azurerm_container_app.orchestrator.latest_revision_fqdn}"
      }

      env {
        name  = "VITE_WS_BASE_URL"
        value = "wss://${azurerm_container_app.orchestrator.latest_revision_fqdn}"
      }

      env {
        name  = "VITE_APP_NAME"
        value = "MCP Network Automation"
      }

      env {
        name  = "VITE_APP_VERSION"
        value = "1.0.0"
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 5173
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "frontend"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

# Orchestrator Container App (minimal resources)
resource "azurerm_container_app" "orchestrator" {
  name                         = "mcp-orchestrator"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  template {
    container {
      name   = "orchestrator"
      image  = "${azurerm_container_registry.acr.login_server}/mcp-orchestrator:latest"
      cpu    = 0.5  # Reduced from 1.0
      memory = "1Gi"  # Reduced from 2Gi

      env {
        name  = "PORT"
        value = "3000"
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name  = "GITHUB_MCP_URL"
        value = "https://${azurerm_container_app.github_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "PYATS_MCP_URL"
        value = "https://${azurerm_container_app.pyats_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "SERVICENOW_MCP_URL"
        value = "https://${azurerm_container_app.servicenow_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "EMAIL_MCP_URL"
        value = "https://${azurerm_container_app.email_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "SLACK_MCP_URL"
        value = "https://${azurerm_container_app.slack_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "GOOGLE_MAPS_MCP_URL"
        value = "https://${azurerm_container_app.google_maps_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "GOOGLE_SEARCH_MCP_URL"
        value = "https://${azurerm_container_app.google_search_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "FILESYSTEM_MCP_URL"
        value = "https://${azurerm_container_app.filesystem_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "SEQUENTIAL_THINKING_MCP_URL"
        value = "https://${azurerm_container_app.sequential_thinking_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "QUICKCHART_MCP_URL"
        value = "https://${azurerm_container_app.quickchart_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "EXCALIDRAW_MCP_URL"
        value = "https://${azurerm_container_app.excalidraw_mcp.latest_revision_fqdn}"
      }

      env {
        name  = "CHATGPT_MCP_URL"
        value = "https://${azurerm_container_app.chatgpt_mcp.latest_revision_fqdn}"
      }

      # VPN network access
      env {
        name  = "VPN_ENABLED"
        value = "true"
      }

      env {
        name  = "VPN_SUBNET"
        value = "10.0.0.0/24"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "orchestrator"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

# Container Apps for MCP Servers (minimal resources)
resource "azurerm_container_app" "github_mcp" {
  name                         = "github-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "github-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/github-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "GITHUB_TOKEN"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/github-token/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "github-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "pyats_mcp" {
  name                         = "pyats-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

    identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "pyats-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/pyats-mcp:latest"
      cpu    = 0.5  # Reduced from 1.0
      memory = "1Gi"  # Reduced from 2Gi

      env {
        name  = "PYATS_TESTBED_PATH"
        value = "/app/testbed.yaml"
      }

      env {
        name  = "PORT"
        value = "3000"
      }

      # VPN access for network devices
      env {
        name  = "VPN_ENABLED"
        value = "true"
      }

      env {
        name  = "VPN_SUBNET"
        value = "10.0.0.0/24"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }


  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "pyats-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "servicenow_mcp" {
  name                         = "servicenow-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "servicenow-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/servicenow-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "SERVICENOW_URL"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/servicenow-url/)"
      }

      env {
        name  = "SERVICENOW_USERNAME"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/servicenow-username/)"
      }

      env {
        name  = "SERVICENOW_PASSWORD"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/servicenow-password/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "servicenow-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "email_mcp" {
  name                         = "email-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

    identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "email-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/email-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "EMAIL_HOST"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/email-host/)"
      }

      env {
        name  = "EMAIL_PORT"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/email-port/)"
      }

      env {
        name  = "EMAIL_ACCOUNT"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/email-account/)"
      }

      env {
        name  = "EMAIL_PASSWORD"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/email-password/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "email-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "slack_mcp" {
  name                         = "slack-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "slack-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/slack-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "SLACK_BOT_TOKEN"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/slack-bot-token/)"
      }

      env {
        name  = "SLACK_TEAM_ID"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/slack-team-id/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "slack-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "google_maps_mcp" {
  name                         = "google-maps-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

    identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "google-maps-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/google-maps-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "GOOGLE_MAPS_API_KEY"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/google-maps-api-key/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "google-maps-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "google_search_mcp" {
  name                         = "google-search-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "google-search-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/google-search-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "GOOGLE_SEARCH_API_KEY"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/google-search-api-key/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "google-search-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "filesystem_mcp" {
  name                         = "filesystem-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "filesystem-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/filesystem-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "filesystem-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "sequential_thinking_mcp" {
  name                         = "sequential-thinking-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

   identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "sequential-thinking-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/sequential-thinking-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  tags = {
    Environment = var.environment
    Service     = "sequential-thinking-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "quickchart_mcp" {
  name                         = "quickchart-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "quickchart-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/quickchart-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "quickchart-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "excalidraw_mcp" {
  name                         = "excalidraw-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "excalidraw-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/excalidraw-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "excalidraw-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

resource "azurerm_container_app" "chatgpt_mcp" {
  name                         = "chatgpt-mcp-server"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"
    
  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "chatgpt-mcp"
      image  = "${azurerm_container_registry.acr.login_server}/chatgpt-mcp:latest"
      cpu    = 0.25  # Reduced from 0.5
      memory = "0.5Gi"  # Reduced from 1Gi

      env {
        name  = "OPENAI_API_KEY"
        value = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault.main.vault_uri}secrets/openai-api-key/)"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port     = 3000
    transport       = "http"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    Environment = var.environment
    Service     = "chatgpt-mcp"
  }
  
  depends_on = [azurerm_key_vault_secret.acr_password]
}

# API Management for MCP Server coordination
resource "azurerm_api_management" "main" {
  name                = "mcp-api-management-2024"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "MCP Automation"
  publisher_email     = "admin@mcpautomation.com"

  sku_name = "Developer_1"

  tags = {
    Environment = var.environment
  }
}

# Outputs
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "container_registry_url" {
  value = azurerm_container_registry.acr.login_server
}

output "container_app_environment_id" {
  value = azurerm_container_app_environment.main.id
}

output "frontend_url" {
  value = "https://${azurerm_container_app.frontend.latest_revision_fqdn}"
}

output "orchestrator_url" {
  value = "https://${azurerm_container_app.orchestrator.latest_revision_fqdn}"
}

#output "wireguard_vpn_client_name" {
  #value = azurerm_linux_virtual_machine.wireguard_client.name
#}

output "wireguard_vpn_client_ip" {
  value = "10.0.0.2"
}

#output "wireguard_vpn_client_public_ip" {
  #value = azurerm_public_ip.wg_client_public_ip.ip_address
#}

#output "wireguard_vpn_client_ssh_command" {
  #value = "ssh azureuser@${azurerm_public_ip.wg_client_public_ip.ip_address}"
#}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "github_mcp_url" {
  value = azurerm_container_app.github_mcp.latest_revision_fqdn
}

output "pyats_mcp_url" {
  value = azurerm_container_app.pyats_mcp.latest_revision_fqdn
}

output "servicenow_mcp_url" {
  value = azurerm_container_app.servicenow_mcp.latest_revision_fqdn
}

output "email_mcp_url" {
  value = azurerm_container_app.email_mcp.latest_revision_fqdn
}

output "slack_mcp_url" {
  value = azurerm_container_app.slack_mcp.latest_revision_fqdn
}

output "google_maps_mcp_url" {
  value = azurerm_container_app.google_maps_mcp.latest_revision_fqdn
}

output "google_search_mcp_url" {
  value = azurerm_container_app.google_search_mcp.latest_revision_fqdn
}

output "filesystem_mcp_url" {
  value = azurerm_container_app.filesystem_mcp.latest_revision_fqdn
}

output "sequential_thinking_mcp_url" {
  value = azurerm_container_app.sequential_thinking_mcp.latest_revision_fqdn
}

output "quickchart_mcp_url" {
  value = azurerm_container_app.quickchart_mcp.latest_revision_fqdn
}

output "excalidraw_mcp_url" {
  value = azurerm_container_app.excalidraw_mcp.latest_revision_fqdn
}

output "chatgpt_mcp_url" {
  value = azurerm_container_app.chatgpt_mcp.latest_revision_fqdn
}

# WireGuard Client VM (Azure)
#resource "azurerm_linux_virtual_machine" "wireguard_client" {
  #name                = "wireguard-client-vm"
  #resource_group_name = azurerm_resource_group.main.name
  #location            = azurerm_resource_group.main.location
  #size                = "Standard_B1s"
  #admin_username      = var.admin_username
  #network_interface_ids = [azurerm_network_interface.wg_client_nic.id]
  #disable_password_authentication = true

  #admin_ssh_key {
    #username   = var.admin_username
    #public_key = var.admin_ssh_public_key
 # }

 # os_disk {
   # caching              = "ReadWrite"
   # storage_account_type = "Standard_LRS"
  #  name                 = "wireguardclientosdisk"
#  }

#  source_image_reference {
 #   publisher = "Canonical"
 #   offer     = "0001-com-ubuntu-server-focal"
 #   sku       = "20_04-lts"
 #   version   = "latest"
 # }

  ##custom_data = base64encode(templatefile("${path.module}/cloud-init-wireguard-client.yaml", {
    #wg_private_key = var.wireguard_client_private_key
    #wg_public_key  = var.wireguard_client_public_key
    #server_public_key = var.home_wireguard_server_public_key
    #server_endpoint   = var.home_wireguard_server_endpoint
  #}))

  #tags = {
  #  Environment = var.environment
    #Service     = "wireguard-client"
 # }
#}

#resource "azurerm_virtual_network" "wg_client_vnet" {
  #name                = "wireguard-client-vnet"
  #address_space       = ["10.10.0.0/16"]
  #location            = azurerm_resource_group.main.location
  #resource_group_name = azurerm_resource_group.main.name
#}

#resource "azurerm_subnet" "wg_client_subnet" {
  #name                 = "wireguard-client-subnet"
  #resource_group_name  = azurerm_resource_group.main.name
  #virtual_network_name = azurerm_virtual_network.wg_client_vnet.name
  #address_prefixes     = ["10.10.1.0/23"]
#}

#resource "azurerm_network_interface" "wg_client_nic" {
 # name                = "wireguard-client-nic"
 # location            = azurerm_resource_group.main.location
#  resource_group_name = azurerm_resource_group.main.name

 # ip_configuration {
 #   name                          = "internal"
 #   subnet_id                     = azurerm_subnet.wg_client_subnet.id
 #   private_ip_address_allocation = "Dynamic"
 #   public_ip_address_id          = azurerm_public_ip.wg_client_public_ip.id
#  }
#}

#resource "azurerm_public_ip" "wg_client_public_ip" {
  #name                = "wireguard-client-public-ip"
 # location            = azurerm_resource_group.main.location
 # resource_group_name = azurerm_resource_group.main.name
 # allocation_method   = "Dynamic"
  #sku                 = "Basic"
#}

resource "azurerm_network_security_group" "wg_client_nsg" {
  name                = "wireguard-client-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Outbound is allowed by default
}

#resource "azurerm_network_interface_security_group_association" "wg_client_nic_nsg" {
  #network_interface_id      = azurerm_network_interface.wg_client_nic.id
  #network_security_group_id = azurerm_network_security_group.wg_client_nsg.id
#}
# trigger from root
