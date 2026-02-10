import json
import os
import boto3

AGENT_ID = os.environ.get('AGENT_ID')
AGENT_ALIAS_ID = os.environ.get('AGENT_ALIAS_ID', 'TSTALIASID')
AGENTCORE_REGION = os.environ.get('AGENTCORE_REGION')

if AGENTCORE_REGION:
    bedrock = boto3.client('bedrock-agent-runtime', region_name=AGENTCORE_REGION)
else:
    bedrock = boto3.client('bedrock-agent-runtime')

def lambda_handler(event, context):
    # Context from Authorizer
    authorizer_context = event.get('requestContext', {}).get('authorizer', {})
    access_token = authorizer_context.get('access_token')
    
    if not access_token:
        print("Warning: No access token found in context")
    
    # Parse body
    try:
        body = json.loads(event.get('body', '{}'))
        prompt = body.get('prompt')
        session_id = body.get('sessionId', 'default-session')
    except:
        return {"statusCode": 400, "body": "Invalid JSON"}

    if not prompt:
        return {"statusCode": 400, "body": "Missing prompt"}

    # Rule 15: Shadow JSON
    try:
        with open('/tmp/shadow_invoker.json', 'w') as f:
            json.dump({
                "agentId": AGENT_ID,
                "agentAliasId": AGENT_ALIAS_ID,
                "sessionId": session_id,
                "inputText": prompt,
                "timestamp": str(os.environ.get('AWS_LAMBDA_REQUEST_ID'))
            }, f)
    except Exception as e:
        print(f"Shadow JSON Error: {e}")

    # Invoke Bedrock Agent
    try:
        response = bedrock.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=prompt
        )
        
        # Parse stream
        completion = ""
        for event in response.get('completion'):
            chunk = event['chunk']
            if chunk:
                completion += chunk['bytes'].decode()

        return {
            "statusCode": 200,
            "body": json.dumps({"response": completion})
        }
        
    except Exception as e:
        print(f"Bedrock Error: {e}")
        return {"statusCode": 500, "body": str(e)}
