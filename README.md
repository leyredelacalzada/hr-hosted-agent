# HR Hosted Agent — From Agent Framework to Microsoft Foundry

This repo shows **step-by-step** how to take an existing [Microsoft Agent Framework](https://github.com/microsoft/agent-framework) agent and turn it into a **hosted agent** running on [Microsoft Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents).

## What changed (original → hosted)

| Aspect | Original (`original/hr_agent.py`) | Hosted (`main.py`) |
|---|---|---|
| **Execution model** | Standalone async script (`asyncio.run`) | Long-running HTTP server (Uvicorn on port 8088) |
| **Credential** | Async `DefaultAzureCredential` (one-shot) | Sync `DefaultAzureCredential` (auto-refresh via hosting adapter) |
| **Entry point** | `asyncio.run(main())` | `from_agent_framework(agent).run()` |
| **API surface** | None — prints to console | REST API: `POST /responses` (OpenAI Responses compatible) |
| **Packaging** | Bare Python script | Docker container (`Dockerfile`) |
| **Deployment** | N/A | Foundry Agent Service via SDK (`deploy.py`) |
| **Observability** | None | Built-in OpenTelemetry (traces, metrics, logs) |
| **Config** | `.env` file via `python-dotenv` | Environment variables set in agent definition |

## Project structure

```
hr-hosted-agent/
├── original/
│   └── hr_agent.py          # Original agent (for reference)
├── main.py                   # Hosted agent entry point
├── requirements.txt          # Python dependencies
├── Dockerfile                # Container image definition
├── agent.yaml                # Agent definition for azd deployment
├── deploy.py                 # SDK-based deployment script
├── .env.example              # Environment variable template
├── .gitignore
└── README.md
```

## Prerequisites

- Python 3.12+
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az login`)
- [Docker](https://docs.docker.com/get-docker/) (for building the container)
- A **Microsoft Foundry project** with:
  - An Azure OpenAI model deployment (e.g. `gpt-4.1`)
  - An Azure AI Search service with the `kb1-hr` index
- An **Azure Container Registry (ACR)** — current: `acrfiqmafdemo.azurecr.io`

## Run locally

1. **Set environment variables** (copy `.env.example` to `.env` and fill in values):

   ```bash
   cp .env.example .env
   # edit .env with your values
   ```

2. **Install dependencies:**

   ```bash
   pip install --pre -r requirements.txt
   ```

3. **Start the agent:**

   ```bash
   python main.py
   ```

   The agent starts on `http://localhost:8088`.

4. **Test with a REST call:**

   PowerShell:
   ```powershell
   $body = @{ input = "What is the PTO policy?" ; stream = $false } | ConvertTo-Json
   Invoke-RestMethod -Uri http://localhost:8088/responses -Method Post -Body $body -ContentType "application/json"
   ```

   curl:
   ```bash
   curl -sS -H "Content-Type: application/json" -X POST http://localhost:8088/responses \
     -d '{"input": "What is the PTO policy?", "stream": false}'
   ```

## Build & push the container

```bash
# Build (always target linux/amd64 — Foundry runs on AMD64)
docker build --platform linux/amd64 -t hr-hosted-agent:latest .

# Login, tag, and push to ACR
az acr login --name acrfiqmafdemo
docker tag hr-hosted-agent:latest acrfiqmafdemo.azurecr.io/hr-hosted-agent:latest
docker push acrfiqmafdemo.azurecr.io/hr-hosted-agent:latest
```

## Deploy to Microsoft Foundry

### Register the agent via Python SDK (`deploy.py`)

```powershell
$env:AZURE_AI_PROJECT_ENDPOINT = "https://foundry-fiq-maf-demo.services.ai.azure.com/api/projects/proj1-fiq-maf-demo"
$env:CONTAINER_IMAGE = "acrfiqmafdemo.azurecr.io/hr-hosted-agent:latest"
$env:AZURE_SEARCH_ENDPOINT = "https://srch-g5mlw6gto4s6i.search.windows.net"

az login
python deploy.py
```

Then go to the Foundry portal → Agents → click **Start hosted agent** on `hr-hosted-agent`.

## Key concepts

### The hosting adapter

`from_agent_framework()` from `azure-ai-agentserver-agentframework` is the bridge between your Agent Framework code and the Foundry runtime. It:

- Starts a Uvicorn web server on port 8088
- Translates Foundry request/response formats to Agent Framework data structures
- Handles conversation management, streaming, and serialization
- Exports OpenTelemetry traces, metrics, and logs

### Agent identity

- **Before publishing**: the agent runs with the Foundry project's managed identity.
- **After publishing**: Foundry provisions a dedicated agent identity — you must reconfigure RBAC for any Azure resources the agent accesses.

## References

- [What are hosted agents?](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents)
- [Foundry samples — hosted agents](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents)
- [Azure Developer CLI ai agent extension](https://aka.ms/azdaiagent/docs)
- [Original HR agent source](https://github.com/leyredelacalzada/FoundryIQ-and-Agent-Framework-demo/blob/main/app/backend/agents/hr_agent.py)
