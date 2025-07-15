# Fix for Container App Registry Authentication
# This file provides the correct registry configuration for all Container Apps

# Override registry configurations for all Container Apps
locals {
  registry_config = {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }
}

# Update all Container Apps to use the correct registry configuration
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
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "PYATS_TESTBED_PATH"
        value = "/app/testbed.yaml"
      }

      env {
        name  = "PORT"
        value = "3000"
      }

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
    server   = local.registry_config.server
    username = local.registry_config.username
    password_secret_name = local.registry_config.password_secret_name
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
      cpu    = 0.25
      memory = "0.5Gi"

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
    server   = local.registry_config.server
    username = local.registry_config.username
    password_secret_name = local.registry_config.password_secret_name
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
}

# Continue with other Container Apps...
# (This is a partial fix - you'll need to add the rest) 