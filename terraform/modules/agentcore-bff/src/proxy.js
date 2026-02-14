/* global awslambda */
const { SignatureV4 } = require("@smithy/signature-v4");
const { Sha256 } = require("@aws-crypto/sha256-js");
const { defaultProvider } = require("@aws-sdk/credential-provider-node");
const { STSClient, AssumeRoleCommand } = require("@aws-sdk/client-sts");
const https = require("https");
const { URL } = require("url");

const AGENTCORE_RUNTIME_ARN = process.env.AGENTCORE_RUNTIME_ARN;
const AGENTCORE_REGION = process.env.AGENTCORE_REGION || process.env.AWS_REGION;
const AGENTCORE_RUNTIME_ROLE_ARN = process.env.AGENTCORE_RUNTIME_ROLE_ARN;
const AGENTCORE_SERVICE = "bedrock-agentcore";

const stsClient = new STSClient({ region: AGENTCORE_REGION });

function writeError(responseStream, statusCode, message) {
  const s = awslambda.HttpResponseStream.from(responseStream, {
    statusCode,
    headers: { "content-type": "application/json" },
  });
  s.end(JSON.stringify({ error: message }));
}

async function signRequest(method, url, headers, body, credentials) {
  const parsed = new URL(url);
  const signer = new SignatureV4({
    service: AGENTCORE_SERVICE,
    region: AGENTCORE_REGION,
    credentials: credentials || defaultProvider(),
    sha256: Sha256,
  });

  const signed = await signer.sign({
    method,
    protocol: parsed.protocol,
    hostname: parsed.hostname,
    path: parsed.pathname + parsed.search,
    headers: {
      ...headers,
      host: parsed.hostname,
    },
    body,
  });

  return signed;
}

function sendRequest(signed, body, responseStream, sessionId) {
  return new Promise((resolve, reject) => {
    const options = {
      method: signed.method,
      hostname: signed.hostname,
      path: signed.path,
      headers: signed.headers,
    };

    const upstream = https.request(options, (res) => {
      const statusCode = res.statusCode || 200;
      if (statusCode >= 400) {
        let errorBody = "";
        res.on("data", (chunk) => {
          errorBody += chunk.toString("utf-8");
        });
        res.on("end", () => {
          writeError(responseStream, statusCode, errorBody);
          resolve();
        });
        return;
      }

      const responseHeaders = {
        "content-type": "application/x-ndjson; charset=utf-8",
        "cache-control": "no-cache",
      };
      const runtimeSessionId =
        res.headers["x-amzn-bedrock-agentcore-runtime-session-id"] || sessionId;
      if (runtimeSessionId) {
        responseHeaders["x-amzn-bedrock-agentcore-runtime-session-id"] = runtimeSessionId;
      }

      const httpStream = awslambda.HttpResponseStream.from(responseStream, {
        statusCode,
        headers: responseHeaders,
      });

      if (runtimeSessionId) {
        httpStream.write(JSON.stringify({ type: "meta", sessionId: runtimeSessionId }) + "\n");
      }

      res.on("data", (chunk) => {
        const text = chunk.toString("utf-8");
        if (!text) return;
        httpStream.write(JSON.stringify({ type: "delta", delta: text }) + "\n");
      });
      res.on("end", () => {
        httpStream.end();
        resolve();
      });
    });

    upstream.on("error", (err) => reject(err));
    upstream.write(body);
    upstream.end();
  });
}

exports.handler = awslambda.streamifyResponse(async (event, responseStream) => {
  if (!AGENTCORE_RUNTIME_ARN) {
    writeError(responseStream, 500, "Missing AGENTCORE_RUNTIME_ARN");
    return;
  }
  if (!AGENTCORE_REGION) {
    writeError(responseStream, 500, "Missing AGENTCORE_REGION");
    return;
  }

  const authorizer = (event.requestContext || {}).authorizer || {};
  const accessToken = authorizer.access_token;
  const tenantId = authorizer.tenant_id;
  const appId = authorizer.app_id;
  const authorizedSessionId = authorizer.session_id;

  let prompt;
  let sessionId;
  try {
    const rawBody = event.body
      ? event.isBase64Encoded
        ? Buffer.from(event.body, "base64").toString("utf-8")
        : event.body
      : "{}";
    const body = JSON.parse(rawBody);
    prompt = body.prompt;
    sessionId = body.sessionId || "default-session";
  } catch {
    writeError(responseStream, 400, "Invalid JSON");
    return;
  }

  if (!prompt) {
    writeError(responseStream, 400, "Missing prompt");
    return;
  }

  // Multi-tenancy Isolation Check (Rule 14.1)
  if (authorizedSessionId && sessionId !== authorizedSessionId) {
    writeError(responseStream, 403, "Session isolation violation: tenant mismatch");
    return;
  }

  try {
    const arnParts = AGENTCORE_RUNTIME_ARN.split(":");
    if (arnParts.length < 6) {
      throw new Error("Invalid AGENTCORE_RUNTIME_ARN format");
    }
    const accountId = arnParts[4];
    const endpoint = `https://bedrock-agentcore.${AGENTCORE_REGION}.amazonaws.com`;
    const runtimePath = encodeURIComponent(AGENTCORE_RUNTIME_ARN);
    const url = new URL(`${endpoint}/runtimes/${runtimePath}/invocations`);
    url.searchParams.set("accountId", accountId);

    const headers = {
      accept: "application/json",
      "content-type": "application/json",
      "mcp-session-id": sessionId,
      "x-amzn-bedrock-agentcore-runtime-session-id": sessionId,
    };
    if (accessToken) {
      headers.authorization = `Bearer ${accessToken}`;
    }
    if (tenantId) {
      headers["x-tenant-id"] = tenantId;
    }
    if (appId) {
      headers["x-app-id"] = appId;
    }

    const payload = JSON.stringify({ prompt });

    let credentials;
    if (AGENTCORE_RUNTIME_ROLE_ARN && tenantId && appId) {
      try {
        // Senior Move: Dynamic Session Policy (Physical Isolation)
        const sessionPolicy = {
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Action: ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
              Resource: [
                `arn:aws:s3:::*-deployment-*`,
                `arn:aws:s3:::*-memory-*/${appId}/${tenantId}/*`,
                `arn:aws:s3:::*-memory-*/${appId}/${tenantId}`
              ]
            },
            {
              Effect: "Allow",
              Action: ["bedrock-agentcore:InvokeAgentRuntime"],
              Resource: [AGENTCORE_RUNTIME_ARN]
            }
          ]
        };

        const assumeRoleCmd = new AssumeRoleCommand({
          RoleArn: AGENTCORE_RUNTIME_ROLE_ARN,
          RoleSessionName: `AgentCore-${appId}-${tenantId}`,
          Policy: JSON.stringify(sessionPolicy),
          DurationSeconds: 900
        });

        const assumed = await stsClient.send(assumeRoleCmd);
        credentials = {
          accessKeyId: assumed.Credentials.AccessKeyId,
          secretAccessKey: assumed.Credentials.SecretAccessKey,
          sessionToken: assumed.Credentials.SessionToken
        };
      } catch (err) {
        console.error(`AssumeRole failed: ${err}`);
        // Fallback to default if assumption fails, or throw if strict
        throw new Error(`Identity isolation failed: ${err.message}`);
      }
    }

    const signed = await signRequest("POST", url.toString(), headers, payload, credentials);
    await sendRequest(signed, payload, responseStream, sessionId);
  } catch (err) {
    writeError(responseStream, 500, String(err));
  }
});

// Export internals for testing
exports._writeError = writeError;
exports._signRequest = signRequest;
exports._sendRequest = sendRequest;
