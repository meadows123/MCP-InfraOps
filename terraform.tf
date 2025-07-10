terraform { 
  cloud { 
    organization = "Cisconnects" 

    workspaces { 
      name = "MCP-InfraOps" 
    } 
  } 

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.85.0"
    }
  }
}