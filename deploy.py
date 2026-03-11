"""Deploy the HR hosted agent to Microsoft Foundry.

Usage:
    az login
    python deploy.py
"""

import os
from dotenv import load_dotenv
load_dotenv()

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    ImageBasedHostedAgentDefinition,
    ProtocolVersionRecord,
    AgentProtocol,
)
from azure.identity import DefaultAzureCredential

PROJECT_ENDPOINT = os.environ["AZURE_AI_PROJECT_ENDPOINT"]
CONTAINER_IMAGE = os.environ["CONTAINER_IMAGE"]  # e.g. yourregistry.azurecr.io/hr-hosted-agent:latest
SEARCH_ENDPOINT = os.environ["AZURE_SEARCH_ENDPOINT"]
MODEL_DEPLOYMENT_NAME = os.getenv("MODEL_DEPLOYMENT_NAME", "gpt-4.1")

AGENT_NAME = "hr-hosted-agent"


def main():
    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
    )

    agent = client.agents.create_version(
        agent_name=AGENT_NAME,
        description=(
            "HR specialist agent for Zava Corporation. "
            "Answers questions about HR policies, PTO, benefits, and employee handbook."
        ),
        definition=ImageBasedHostedAgentDefinition(
            container_protocol_versions=[
                ProtocolVersionRecord(protocol=AgentProtocol.RESPONSES, version="v1")
            ],
            cpu="1",
            memory="2Gi",
            image=CONTAINER_IMAGE,
            environment_variables={
                "AZURE_AI_PROJECT_ENDPOINT": PROJECT_ENDPOINT,
                "AZURE_SEARCH_ENDPOINT": SEARCH_ENDPOINT,
                "MODEL_DEPLOYMENT_NAME": MODEL_DEPLOYMENT_NAME,
            },
        ),
    )

    print(f"Agent created: {agent.name} (id: {agent.id}, version: {agent.version})")


if __name__ == "__main__":
    main()
