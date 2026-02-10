from bedrock_agentcore import BedrockAgentCoreApp

app = BedrockAgentCoreApp()

@app.entrypoint
def invoke(payload, context=None):
    """
    Entrypoint for the Agent.
    """
    return {
        "status": "success", 
        "message": "Hello from {{ agent_name }}!",
        "payload": payload
    }

if __name__ == "__main__":
    app.run()
