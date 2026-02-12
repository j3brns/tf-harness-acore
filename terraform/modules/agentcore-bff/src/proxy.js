/* global awslambda */
const AWS = require("aws-sdk");
const https = require("https");
const { URL } = require("url");

const AGENTCORE_RUNTIME_ARN = process.env.AGENTCORE_RUNTIME_ARN;
const AGENTCORE_REGION = process.env.AGENTCORE_REGION || process.env.AWS_REGION;
const AGENTCORE_SERVICE = "bedrock-agentcore";

if (AGENTCORE_REGION) {
  AWS.config.update({ region: AGENTCORE_REGION });
}

function resolveEndpoint(region) {
  return `https://bedrock-agentcore.${region}.amazonaws.com`;
}

function getCredentials() {
  return new Promise((resolve, reject) => {
    AWS.config.getCredentials((err) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(AWS.config.credentials);
    });
  });
}

function signRequest(method, url, headers, body) {
  const parsed = new URL(url);
  const endpoint = new AWS.Endpoint(parsed.host);
  const request = new AWS.HttpRequest(endpoint, AGENTCORE_REGION);

  request.method = method;
  request.path = parsed.pathname + parsed.search;
  request.body = body;
  request.headers = Object.assign({}, headers);
  request.headers.host = parsed.host;
  request.headers["Content-Length"] = Buffer.byteLength(body);

  const signer = new AWS.Signers.V4(request, AGENTCORE_SERVICE);
  signer.addAuthorization(AWS.config.credentials, new Date());

  return request;
}

function sendRequest(request, body, responseStream, sessionId) {
  return new Promise((resolve, reject) => {
    const options = {
      method: request.method,
      hostname: request.endpoint.hostname,
      path: request.path,
      headers: request.headers,
    };

    const upstream = https.request(options, (res) => {
      const statusCode = res.statusCode || 200;
      if (statusCode >= 400) {
        let errorBody = "";
        res.on("data", (chunk) => {
          errorBody += chunk.toString("utf-8");
        });
        res.on("end", () => {
          const errStream = awslambda.HttpResponseStream.from(responseStream, {
            statusCode,
            headers: { "content-type": "application/json" },
          });
          errStream.end(JSON.stringify({ error: errorBody }));
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
    const errStream = awslambda.HttpResponseStream.from(responseStream, {
      statusCode: 500,
      headers: { "content-type": "application/json" },
    });
    errStream.end(JSON.stringify({ error: "Missing AGENTCORE_RUNTIME_ARN" }));
    return;
  }
  if (!AGENTCORE_REGION) {
    const errStream = awslambda.HttpResponseStream.from(responseStream, {
      statusCode: 500,
      headers: { "content-type": "application/json" },
    });
    errStream.end(JSON.stringify({ error: "Missing AGENTCORE_REGION" }));
    return;
  }

  const authorizer = (event.requestContext || {}).authorizer || {};
  const accessToken = authorizer.access_token;

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
  } catch (err) {
    const errStream = awslambda.HttpResponseStream.from(responseStream, {
      statusCode: 400,
      headers: { "content-type": "application/json" },
    });
    errStream.end(JSON.stringify({ error: "Invalid JSON" }));
    return;
  }

  if (!prompt) {
    const errStream = awslambda.HttpResponseStream.from(responseStream, {
      statusCode: 400,
      headers: { "content-type": "application/json" },
    });
    errStream.end(JSON.stringify({ error: "Missing prompt" }));
    return;
  }

  try {
    const arnParts = AGENTCORE_RUNTIME_ARN.split(":");
    if (arnParts.length < 6) {
      throw new Error("Invalid AGENTCORE_RUNTIME_ARN format");
    }
    const accountId = arnParts[4];
    const endpoint = resolveEndpoint(AGENTCORE_REGION);
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

    const payload = JSON.stringify({ prompt });

    await getCredentials();
    const request = signRequest("POST", url.toString(), headers, payload);
    await sendRequest(request, payload, responseStream, sessionId);
  } catch (err) {
    const errStream = awslambda.HttpResponseStream.from(responseStream, {
      statusCode: 500,
      headers: { "content-type": "application/json" },
    });
    errStream.end(JSON.stringify({ error: String(err) }));
  }
});
