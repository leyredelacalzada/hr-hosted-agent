import os

from azure.identity import DefaultAzureCredential
from agent_framework import ChatAgent
from agent_framework.azure import AzureAIAgentClient, AzureAISearchContextProvider
from azure.ai.agentserver.agentframework import from_agent_framework

PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT")
MODEL = os.getenv("MODEL_DEPLOYMENT_NAME", "gpt-4.1")
SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")

_credential = DefaultAzureCredential()

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
