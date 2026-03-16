"""Hosted agent entry point — IDENTICAL to Part 1.

The entire point of the enterprise setup is that YOUR APPLICATION CODE DOES NOT CHANGE.
All enterprise security (CMK, Managed Identity, Private Endpoints) is handled at the
infrastructure level via Bicep. The agent code stays the same.

DefaultAzureCredential() automatically picks up the Foundry-managed identity at runtime.
No API keys, no connection strings, no secrets in code.
"""

import os

# --- OpenTelemetry (OPTIONAL — remove if you don't need tracing) ---
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor

APPLICATIONINSIGHTS_CONNECTION_STRING = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")

if APPLICATIONINSIGHTS_CONNECTION_STRING:
    from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter

    provider = TracerProvider()
    provider.add_span_processor(
        SimpleSpanProcessor(
            AzureMonitorTraceExporter(connection_string=APPLICATIONINSIGHTS_CONNECTION_STRING)
        )
    )
    trace.set_tracer_provider(provider)

# --- Azure identity (REQUIRED) ---
# DefaultAzureCredential picks up Foundry's managed identity at runtime.
# In the enterprise setup, this identity has RBAC roles on all resources — no API keys needed.
from azure.identity import DefaultAzureCredential

# --- Agent Framework (REQUIRED) ---
from agent_framework import ChatAgent

# --- Azure AI integrations ---
from agent_framework.azure import AzureAIAgentClient, AzureAISearchContextProvider

# --- Hosting adapter (REQUIRED) ---
from azure.ai.agentserver.agentframework import from_agent_framework

# ---------------------------------------------------------------------------
# Configuration — from environment variables (set in deploy.py or Foundry)
# ---------------------------------------------------------------------------
PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT")
MODEL = os.getenv("MODEL_DEPLOYMENT_NAME", "gpt-4.1")
SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")

_credential = DefaultAzureCredential()

# ---------------------------------------------------------------------------
# Agent logic — same as Part 1
# ---------------------------------------------------------------------------
HR_INSTRUCTIONS = """You are an HR Specialist Agent for Zava Corporation.
Answer questions about HR policies, PTO, benefits, and employee handbook using the knowledge base.
Be specific and cite sources when possible."""


def main():
    client = AzureAIAgentClient(
        project_endpoint=PROJECT_ENDPOINT,
        model_deployment_name=MODEL,
        credential=_credential,
    )

    kb_context = AzureAISearchContextProvider(
        endpoint=SEARCH_ENDPOINT,
        knowledge_base_name="kb1-hr",
        credential=_credential,
        mode="agentic",
        knowledge_base_output_mode="answer_synthesis",
    )

    agent = ChatAgent(
        client,
        name="hr-agent",
        id="hr-agent",
        instructions=HR_INSTRUCTIONS,
        context_providers=[kb_context],
    )

    from_agent_framework(agent).run()


if __name__ == "__main__":
    main()
