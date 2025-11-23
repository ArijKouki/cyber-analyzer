terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Configure Azure Provider
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# Add a random acr_suffix to the acr name to make it globally unique.
resource "random_string" "acr_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}
locals {
  acr_basename = replace(var.project_name, "-", "") // only letters/numbers
  // keep base to <= 40 so base+6 <= 46 (under 50 char limit)
  acr_name     = "${substr(local.acr_basename, 0, 40)}${random_string.acr_suffix.result}"
}

# Use existing resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Create Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = "francecentral"
  sku                 = "Basic"
  admin_enabled       = true

  tags = {
    environment = terraform.workspace
    project     = var.project_name
  }
}

# Tag and push existing local Docker image to ACR
resource "null_resource" "docker_tag_push" {
  triggers = {
    acr_name = azurerm_container_registry.acr.name
    image_tag = var.docker_image_tag
  }

  provisioner "local-exec" {
    command     = "az acr login --name ${azurerm_container_registry.acr.name} && docker tag ${var.project_name}:latest ${azurerm_container_registry.acr.login_server}/${var.project_name}:${var.docker_image_tag} && docker push ${azurerm_container_registry.acr.login_server}/${var.project_name}:${var.docker_image_tag}"
    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [azurerm_container_registry.acr]
}

# Reference the pushed image
locals {
  app_image = "${azurerm_container_registry.acr.login_server}/${var.project_name}:${var.docker_image_tag}"
}

# Create Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-logs"
  location            = "francecentral"
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    environment = terraform.workspace
    project     = var.project_name
  }
}

# Create Container App Environment
resource "azurerm_container_app_environment" "main" {
  name                       = "${var.project_name}-env"
  location                   = "francecentral"
  resource_group_name        = data.azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = {
    environment = terraform.workspace
    project     = var.project_name
  }
}

# Create Container App
resource "azurerm_container_app" "main" {
  name                         = var.project_name
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = data.azurerm_resource_group.main.name
  revision_mode                = "Single"

  depends_on = [null_resource.docker_tag_push]

  template {
    container {
      name   = "main"
      image  = local.app_image
      cpu    = 1.0
      memory = "2.0Gi"

      env {
        name  = "OPENAI_API_KEY"
        value = var.openai_api_key
      }

      env {
        name  = "SEMGREP_APP_TOKEN"
        value = var.semgrep_app_token
      }

      env {
        name  = "ENVIRONMENT"
        value = "production"
      }


      env {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      }
    }

    min_replicas = 0
    max_replicas = 1
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password_secret_name = "registry-password"
  }

  secret {
    name  = "registry-password"
    value = azurerm_container_registry.acr.admin_password
  }

  tags = {
    environment = terraform.workspace
    project     = var.project_name
  }
}

# Outputs
output "app_url" {
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
  description = "URL of the deployed application"
}

output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "Azure Container Registry login server"
}

output "acr_name" {
  value       = azurerm_container_registry.acr.name
  description = "Azure Container Registry name"
}

output "resource_group" {
  value       = data.azurerm_resource_group.main.name
  description = "Resource group name"
}
