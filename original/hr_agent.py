"""HR Agent - Original version from FoundryIQ-and-Agent-Framework-demo.

This is the ORIGINAL agent using Agent Framework with AzureAISearchContextProvider.
It runs as a standalone async script — NOT containerized, NOT hosted.
"""

import asyncio
import os

from dotenv import load_dotenv
load_dotenv()

from azure.identity.aio import DefaultAzureCredential

from agent_framework import Agent, Message, Content
from agent_framework.azure import AzureAIAgentClient, AzureAISearchContextProvider

SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")
PROJECT_ENDPOINT = os.getenv("AZURE_AI_PROJECT_ENDPOINT")
MODEL = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")

HR_INSTRUCTIONS = """You are an HR Specialist Agent for Zava Corporation.
Answer questions about HR policies, PTO, benefits, and employee handbook using the knowledge base.
Be specific and cite sources when possible."""


async def run_hr_agent(query: str) -> str:
    """Run the HR agent with a query."""
    async with DefaultAzureCredential() as credential:
        async with (
            AzureAIAgentClient(
                project_endpoint=PROJECT_ENDPOINT,
                model_deployment_name=MODEL,
                credential=credential,
            ) as client,
            AzureAISearchContextProvider(
                endpoint=SEARCH_ENDPOINT,
                knowledge_base_name="kb1-hr",
                credential=credential,
                mode="agentic",
                knowledge_base_output_mode="answer_synthesis",
            ) as kb_context,
        ):
            agent = Agent(
                client=client,
                context_provider=kb_context,
                instructions=HR_INSTRUCTIONS,
            )

            message = Message(role="user", contents=[Content.from_text(query)])

            response = await agent.run(message)
            return response.text


async def main():
    print("\nHR Agent (kb1-hr)")
    print("=" * 50)

    query = "What is the PTO policy?"
    print(f"\nQuery: {query}")

    response = await run_hr_agent(query)
    print(f"\nResponse:\n{response}")


if __name__ == "__main__":
    asyncio.run(main())
