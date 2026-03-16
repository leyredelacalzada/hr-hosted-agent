# Part 2: Enterprise Setup — Hosted Agent + Foundry IQ + MAF Architecture

**Same agent. Same code. Enterprise-grade infrastructure.**

This is **Part 2** of the [Hosted Agent tutorial](../README.md). It deploys the exact same HR agent from Part 1, but on enterprise infrastructure with:

| Enterprise Feature | What It Does |
|---|---|
| **Customer-Managed Keys (CMK)** | All data at rest encrypted with YOUR key from YOUR Key Vault |
| **Keyless Auth (Managed Identity)** | Zero API keys anywhere — all auth via User-Assigned Managed Identity + RBAC |
| **Private Endpoints** | Every service behind a VNET — no public internet exposure |

> **Key insight:** Your application code does not change. `main.py`, `deploy.py`, `Dockerfile` — all identical to Part 1. The enterprise security is entirely in the infrastructure layer (Bicep).

---

## Architecture

```
┌──────────────────── Virtual Network (10.0.0.0/16) ────────────────────┐
│                                                                        │
│  Private Endpoints Subnet (10.0.1.0/24)                               │
│  ┌────────────────────────────────────────────────────────────────┐   │
│  │                                                                │   │
│  │   ┌───────────────── Azure AI Foundry ─────────────────┐      │   │
│  │   │                                                     │      │   │
│  │   │  ┌──────────────┐       ┌──────────────────────┐   │      │   │
│  │   │  │ Hosted Agent  │──MI──▶│ AI Services (OpenAI)  │   │      │   │
│  │   │  │ (container)   │       │ 🔒 CMK │ 🔑 MI only   │   │      │   │
│  │   │  │  :8088        │       └──────────────────────┘   │      │   │
│  │   │  └──────┬───────┘                                   │      │   │
│  │   │         │              ┌──────────────────────┐     │      │   │
│  │   │         └─────MI──────▶│ AI Search            │     │      │   │
│  │   │                        │ 🔒 CMK │ 🔑 MI only   │     │      │   │
│  │   │                        └──────────────────────┘     │      │   │
│  │   └─────────────────────────────────────────────────────┘      │   │
│  │                                                                │   │
│  │   ┌──────────┐  ┌───────────┐  ┌──────────────────────┐      │   │
│  │   │ Key Vault │  │ Storage   │  │ Container Registry   │      │   │
│  │   │ 🔑 CMK src│  │ 🔒 CMK    │  │ 🔒 CMK │ Premium     │      │   │
│  │   │ 🔐 RBAC   │  │ 🔑 MI     │  │ 🔑 MI only          │      │   │
│  │   └──────────┘  └───────────┘  └──────────────────────┘      │   │
│  └────────────────────────────────────────────────────────────────┘   │
│                                                                        │
│  🔐 User-Assigned Managed Identity (single identity, all RBAC roles) │
│  🔑 Customer-Managed Key from Key Vault (RSA-2048, all data at rest)  │
│  🔒 Private Endpoints + Private DNS Zones (zero public exposure)      │
└────────────────────────────────────────────────────────────────────────┘
```

### What's different from Part 1

| Aspect | Part 1 (Standard) | Part 2 (Enterprise) |
|---|---|---|
| **Network** | Public endpoints | Private endpoints + VNET |
| **Encryption** | Microsoft-managed keys | Customer-managed keys (CMK) from your Key Vault |
| **Authentication** | DefaultAzureCredential (any method) | Managed Identity only — API keys disabled on ALL services |
| **Key Vault** | Not needed | RBAC-only, purge-protected, soft-delete enabled |
| **ACR** | Basic SKU | Premium SKU (required for PE + CMK) |
| **AI Services** | `disableLocalAuth: false` | `disableLocalAuth: true` |
| **AI Search** | API keys available | `disableLocalAuth: true`, CMK enforcement enabled |
| **Storage** | Shared key access | `allowSharedKeyAccess: false` |
| **Service auth** | Key-based connections | Identity-based (MI + RBAC, no keys) |
| **App code** | `main.py` | **Identical** — no changes needed |

---

## Project Structure

```
enterprise/
├── infra/                              # 🏗️  Bicep infrastructure-as-code
│   ├── main.bicep                      #     Orchestrator — deploys everything
│   └── modules/
│       ├── managed-identity.bicep      #     User-assigned MI (single identity)
│       ├── network.bicep               #     VNET + subnets + 7 private DNS zones
│       ├── keyvault.bicep              #     Key Vault + CMK key + PE
│       ├── storage.bicep               #     Storage + CMK + PE (blob + file)
│       ├── ai-services.bicep           #     AI Services + model + Foundry project + CMK + PE
│       ├── ai-search.bicep             #     AI Search + CMK enforcement + PE
│       └── acr.bicep                   #     Container Registry + CMK + PE
├── main.py                             # ⭐ Agent code (identical to Part 1)
├── deploy.py                           # 🚀 Register agent in Foundry (identical to Part 1)
├── deploy-infra.ps1                    # 🏗️  PowerShell script to deploy all infrastructure
├── Dockerfile                          # 🐳 Container image (identical to Part 1)
├── requirements.txt                    # 📦 Dependencies (identical to Part 1)
├── agent.yaml                          # 📄 Agent metadata
└── README.md                           # 📖 This file
```

---

## Prerequisites

### Azure permissions

The deployer needs:
- **Contributor** on the subscription/resource group (to create resources)
- **User Access Administrator** (to create RBAC role assignments)
- The deployment script will auto-grant **Key Vault Crypto Officer** for CMK key creation

### Local tools

- **Azure CLI** (with Bicep) — `az --version` should show Bicep CLI
- **Docker** — for building locally (optional: `az acr build` does cloud builds without Docker)
- **Python 3.12+** — for `deploy.py`
- **PowerShell** — for `deploy-infra.ps1`

---

## Step-by-Step Deployment

### Step 1: Deploy Enterprise Infrastructure

```powershell
# Login to Azure
az login

# Deploy everything (VNET, Key Vault, Storage, AI Services + Foundry Project, AI Search, ACR)
cd enterprise
.\deploy-infra.ps1 -ResourceGroup "rg-hr-agent-enterprise" -Location "eastus2" -Prefix "hragent"
```

This creates **all** Azure resources with:
- ✅ Private endpoints on every service
- ✅ CMK encryption on Storage, AI Services, ACR (+ CMK enforcement on AI Search)
- ✅ API keys disabled on AI Services, AI Search, Storage
- ✅ RBAC roles assigned to the managed identity

The script outputs all the values you need for the next steps.

### Step 1.5: Temporarily Enable Public Access (for initial setup)

> **IMPORTANT:** All services are deployed with public access **disabled** by default. To push
> the container image and register the agent from your local machine, you need to temporarily
> enable public access. This is the expected workflow for initial setup — you'll lock it back
> down in Step 5.
>
> In a real enterprise environment, you'd do this from inside the VNET (via VPN, ExpressRoute,
> or a jumpbox VM with Azure Bastion). For this demo/walkthrough, we temporarily open access.

```powershell
# Enable public access on AI Services
az cognitiveservices account update -g <rg> -n <ai-services-name> `
    --custom-domain <ai-services-name> `
    --set properties.publicNetworkAccess=Enabled

# Enable public access on ACR
az acr update -n <acr-name> --public-network-enabled true

# Enable public access on AI Search (via REST — the CLI has a bug with UserAssigned identity)
az rest --method PATCH `
    --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/<search-name>?api-version=2024-06-01-preview" `
    --headers Content-Type=application/json `
    --body '{"properties":{"publicNetworkAccess":"enabled"}}'
```

### Step 2: Build and Push the Container Image

```powershell
# Option A: Cloud build (recommended — works even with private endpoints, no local Docker needed)
az acr build --registry <acr-name> --image hr-hosted-agent:latest --platform linux/amd64 .

# Option B: Local build + push (requires Docker Desktop running)
docker build --platform linux/amd64 -t <acr-login-server>/hr-hosted-agent:latest .
az acr login --name <acr-name>
docker push <acr-login-server>/hr-hosted-agent:latest
```

### Step 3: Register the Agent in Foundry

```powershell
# Set environment variables (values from Step 1 output)
$env:AZURE_AI_PROJECT_ENDPOINT = "<project-endpoint-from-step-1>"
$env:AZURE_SEARCH_ENDPOINT = "<search-endpoint-from-step-1>"
$env:CONTAINER_IMAGE = "<acr-login-server>/hr-hosted-agent:latest"

# Deploy
python deploy.py
```

### Step 4: Start the Agent

Go to **Azure AI Foundry portal** → **Agents** → find your agent → **Start**.

### Step 5: Re-Disable Public Access (lock it down)

> After the agent is deployed and running, disable public access again. The hosted agent
> runs **inside** Foundry's infrastructure and communicates with all services through the
> private endpoints — it does NOT need public access.

```powershell
# Disable public access on AI Services
az cognitiveservices account update -g <rg> -n <ai-services-name> `
    --custom-domain <ai-services-name> `
    --set properties.publicNetworkAccess=Disabled

# Disable public access on ACR
az acr update -n <acr-name> --public-network-enabled false

# Disable public access on AI Search
az rest --method PATCH `
    --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/<search-name>?api-version=2024-06-01-preview" `
    --headers Content-Type=application/json `
    --body '{"properties":{"publicNetworkAccess":"disabled"}}'
```

After this, the only way to reach these services is through the private endpoints inside the VNET.
The hosted agent continues to work because Foundry routes traffic through the private network.

---

## Bicep Modules Deep Dive

### Managed Identity (`managed-identity.bicep`)

Creates a single **User-Assigned Managed Identity** used across all resources. This is the cornerstone of the keyless auth strategy — one identity, all RBAC roles:

| Role | Resource | Purpose |
|---|---|---|
| Key Vault Crypto User | Key Vault | Use CMK key for encryption/decryption |
| Storage Blob Data Contributor | Storage | Read/write blobs |
| Cognitive Services OpenAI Contributor | AI Services | Call OpenAI models |
| Search Index Data Reader | AI Search | Query search indexes |
| Search Service Contributor | AI Search | Manage search service |
| AcrPull + AcrPush | Container Registry | Pull/push container images |

### Network (`network.bicep`)

Creates a VNET with a private endpoint subnet and **7 private DNS zones**:

| DNS Zone | Service |
|---|---|
| `privatelink.cognitiveservices.azure.com` | AI Services |
| `privatelink.openai.azure.com` | OpenAI endpoints |
| `privatelink.search.windows.net` | AI Search |
| `privatelink.blob.core.windows.net` | Storage (Blob) |
| `privatelink.file.core.windows.net` | Storage (File) |
| `privatelink.vaultcore.azure.net` | Key Vault |
| `privatelink.azurecr.io` | Container Registry |

Each DNS zone is linked to the VNET so private endpoint DNS resolution works automatically.

### Key Vault (`keyvault.bicep`)

- **RBAC-only** (`enableRbacAuthorization: true`) — no access policies
- **Purge protection** enabled (required for CMK)
- Creates a **RSA-2048 CMK key** used by all other services
- Firewall: `defaultAction: Deny`, `bypass: AzureServices`

### AI Services (`ai-services.bicep`)

- **`disableLocalAuth: true`** — API keys completely disabled
- **`allowProjectManagement: true`** — enables Foundry project creation as child resource
- CMK encryption with the user-assigned MI
- Deploys the OpenAI model (default: `gpt-4.1`)
- Creates a **Foundry project** (child of the AI Services account)
- Private endpoint with both `cognitiveservices` and `openai` DNS zones

### AI Search (`ai-search.bicep`)

- **`disableLocalAuth: true`** — no API keys or query keys
- **`encryptionWithCmk.enforcement: 'Enabled'`** — all new indexes must use CMK
- Semantic search enabled (for knowledge base grounding)

> **Note:** CMK enforcement is at the service level. The actual CMK key must be configured when creating indexes via the SDK. See [Azure AI Search CMK docs](https://learn.microsoft.com/en-us/azure/search/search-security-manage-encryption-keys).

### ACR (`acr.bicep`)

- **Premium SKU** (required for CMK + private endpoints)
- **Admin user disabled** — pull/push via RBAC only
- CMK encryption using the unversioned key URI (auto-rotation compatible)

---

## Initial Setup vs. Production (Private Endpoints Workflow)

When all services have `publicNetworkAccess: 'Disabled'`, you can't reach them from the public
internet — that includes your laptop and the Azure AI Foundry portal.

**For initial setup** (pushing images, deploying the agent, verifying in the portal), you have
three options:

1. **Temporarily enable public access** (simplest — used in this walkthrough)
   - Open public access → push image → deploy agent → verify → re-disable
   - See Step 1.5 and Step 5 in the deployment guide above

2. **Use a jumpbox VM inside the VNET** (enterprise standard)
   - Deploy a VM + Azure Bastion in the VNET
   - RDP/SSH into the VM to run `az acr build`, `python deploy.py`, and access the portal

3. **Connect via VPN** (enterprise with existing infrastructure)
   - Point-to-Site VPN gateway (~30 min setup)
   - Site-to-Site VPN or ExpressRoute (corporate network already connected)

**After the agent is deployed**, it runs inside Foundry's managed infrastructure and communicates
with all services through the **private endpoints** — it does NOT need public access. You only
need public access (or VNET access) for management operations.

---

## Troubleshooting

### Deployment fails on first run
RBAC role assignments can take 5-10 minutes to propagate. If the deployment fails with a permissions error (especially on Key Vault key creation or CMK configuration), wait 5 minutes and retry.

### ACR push fails
The ACR has `publicNetworkAccess: 'Disabled'`. To push images:
- Use `az acr build` to build in the cloud (recommended — works even with private endpoints)
- Or temporarily enable public access: `az acr update --name <acr> --public-network-enabled true`

### Foundry portal shows "unable to connect"
This is expected when public access is disabled. Access the portal from inside the VNET
(via VM/VPN) or temporarily enable public access on AI Services.

### Model deployment not available
The `gpt-4.1` model may not be available in all regions. Check [model availability](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/models) and adjust the `modelDeploymentName` parameter.

---

## Security Checklist

After deployment (with public access re-disabled), verify:

- [ ] All services show "Private endpoint" in their networking settings
- [ ] AI Services → Keys and Endpoint → "Local Authentication: Disabled"
- [ ] AI Search → Keys → no API keys available
- [ ] Storage → Configuration → "Allow storage account key access: Disabled"
- [ ] Key Vault → Access configuration → "Permission model: Azure role-based access control"
- [ ] ACR → Access keys → "Admin user: Disabled"
- [ ] No public IP addresses on any service

You can automate this with the included `validate-enterprise.ps1` script:

```powershell
.\validate-enterprise.ps1 -ResourceGroup "rg-hr-agent-enterprise"
```

---

## Dependencies

Same as Part 1 — the app code doesn't change:

| Package | Purpose |
|---|---|
| `azure-ai-agentserver-agentframework` | Hosting adapter |
| `agent-framework-core` | Core Agent Framework |
| `agent-framework-azure-ai` | Azure AI client |
| `agent-framework-azure-ai-search` | AI Search context provider |
| `azure-ai-projects` | Foundry SDK (deploy.py) |
| `azure-identity` | Azure authentication (DefaultAzureCredential) |
