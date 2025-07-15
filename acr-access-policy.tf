# ACR Access Policy for Container Apps
# This allows Container Apps to pull images from the Azure Container Registry

# Get the Container Apps environment's managed identity
data "azurerm_container_app_environment" "main" {
  name                = azurerm_container_app_environment.main.name
  resource_group_name = azurerm_resource_group.main.name
}

# ACR Access Policy for Container Apps Environment
resource "azurerm_container_registry_scope_map" "container_apps" {
  name                    = "container-apps-pull"
  resource_group_name     = azurerm_resource_group.main.name
  container_registry_name = azurerm_container_registry.acr.name
  description             = "Allow Container Apps to pull images"

  actions = [
    "repositories/mcpautomationacr/github-mcp/content/read",
    "repositories/mcpautomationacr/pyats-mcp/content/read",
    "repositories/mcpautomationacr/servicenow-mcp/content/read",
    "repositories/mcpautomationacr/email-mcp/content/read",
    "repositories/mcpautomationacr/slack-mcp/content/read",
    "repositories/mcpautomationacr/google-maps-mcp/content/read",
    "repositories/mcpautomationacr/google-search-mcp/content/read",
    "repositories/mcpautomationacr/filesystem-mcp/content/read",
    "repositories/mcpautomationacr/sequential-thinking-mcp/content/read",
    "repositories/mcpautomationacr/quickchart-mcp/content/read",
    "repositories/mcpautomationacr/excalidraw-mcp/content/read",
    "repositories/mcpautomationacr/chatgpt-mcp/content/read",
    "repositories/mcpautomationacr/netbox-mcp/content/read",
    "repositories/mcpautomationacr/mcpyats/content/read",
    "repositories/mcpautomationacr/streamlit-app/content/read",
    "repositories/mcpautomationacr/frontend/content/read",
    "repositories/mcpautomationacr/orchestrator/content/read"
  ]
}

# ACR Token for Container Apps
resource "azurerm_container_registry_token" "container_apps" {
  name                    = "container-apps-token"
  resource_group_name     = azurerm_resource_group.main.name
  container_registry_name = azurerm_container_registry.acr.name
  scope_map_id            = azurerm_container_registry_scope_map.container_apps.id
}

# ACR Token Password
resource "azurerm_container_registry_token_password" "container_apps" {
  container_registry_token_id = azurerm_container_registry_token.container_apps.id
  password1 {
    expiry = timeadd(timestamp(), "8760h") # 1 year
  }
} 