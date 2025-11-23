# GitHub Actions Workflow

This workflow automatically builds and deploys the application to Azure Container Apps.

## Setup

### Required GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

1. **AZURE_CLIENT_ID** - Azure Service Principal Client ID
2. **AZURE_TENANT_ID** - Azure Tenant ID
3. **AZURE_SUBSCRIPTION_ID** - Azure Subscription ID
4. **OPENAI_API_KEY** - OpenAI API key for the application
5. **SEMGREP_APP_TOKEN** - Semgrep app token for security scanning

### Creating Azure Service Principal

To create a service principal for GitHub Actions:

```bash
az ad sp create-for-rbac --name "github-actions-cyber-analyzer" \
  --role contributor \
  --scopes /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/cyber-analyzer-rg \
  --sdk-auth
```

Copy the JSON output and add it to GitHub Secrets, or extract individual values:
- `clientId` → `AZURE_CLIENT_ID`
- `tenantId` → `AZURE_TENANT_ID`
- `subscriptionId` → `AZURE_SUBSCRIPTION_ID`

Alternatively, use federated credentials (recommended):

```bash
az ad app create --display-name "github-actions-cyber-analyzer"
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters @federated-credential.json
```

## Workflow Behavior

- **On Push to main/master**: Builds Docker image, pushes to ACR, and deploys to Azure
- **On Pull Request**: Only builds and pushes the Docker image (no deployment)
- **Manual Trigger**: Can be triggered manually from the Actions tab

## Workflow Steps

1. **Build and Push**: Builds the Docker image and pushes it to Azure Container Registry
2. **Deploy**: Runs Terraform to deploy/update the Azure Container App (only on main/master branch)

