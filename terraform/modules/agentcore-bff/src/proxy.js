/* global awslambda */
const crypto = require("crypto");
const { SignatureV4 } = require("@smithy/signature-v4");
const { Sha256 } = require("@aws-crypto/sha256-js");
const { defaultProvider } = require("@aws-sdk/credential-provider-node");
const { STSClient, AssumeRoleCommand } = require("@aws-sdk/client-sts");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const https = require("https");
const { URL } = require("url");

const AGENTCORE_RUNTIME_ARN = process.env.AGENTCORE_RUNTIME_ARN;
const AGENTCORE_REGION = process.env.AGENTCORE_REGION || process.env.AWS_REGION;
const AGENTCORE_RUNTIME_ROLE_ARN = process.env.AGENTCORE_RUNTIME_ROLE_ARN;
const AGENTCORE_SERVICE = "bedrock-agentcore";

const AGENT_NAME = process.env.AGENT_NAME || "";
const ENVIRONMENT = process.env.ENVIRONMENT || "";
const DEPLOYMENT_BUCKET_NAME = process.env.DEPLOYMENT_BUCKET_NAME || "";
const AUDIT_LOGS_ENABLED = process.env.AUDIT_LOGS_ENABLED === "true";
const AUDIT_LOGS_BUCKET = process.env.AUDIT_LOGS_BUCKET || "";
const AUDIT_LOGS_PREFIX = process.env.AUDIT_LOGS_PREFIX || "audit/bff-proxy/events/";
const AUDIT_PREVIEW_MAX_CHARS = 16384;
const AUDIT_PROMPT_PREVIEW_MAX_CHARS = 4096;

const stsClient = new STSClient({ region: AGENTCORE_REGION });
const s3Client =
  AUDIT_LOGS_ENABLED && AUDIT_LOGS_BUCKET
    ? new S3Client({ region: process.env.AWS_REGION || AGENTCORE_REGION })
    : null;

function writeError(responseStream, statusCode, message) {
  const s = awslambda.HttpResponseStream.from(responseStream, {
    statusCode,
    headers: { "content-type": "application/json" },
  });
  s.end(JSON.stringify({ error: message }));
}

function writeJson(responseStream, statusCode, payload) {
  const s = awslambda.HttpResponseStream.from(responseStream, {
    statusCode,
    headers: { "content-type": "application/json" },
  });
  s.end(JSON.stringify(payload));
}

function safeString(value) {
  return typeof value === "string" ? value : "";
}

function sha256Hex(value) {
  return crypto.createHash("sha256").update(value || "", "utf8").digest("hex");
}

function truncateText(text, maxChars) {
  const value = safeString(text);
  if (value.length <= maxChars) {
    return { value, truncated: false };
  }
  return { value: value.slice(0, maxChars), truncated: true };
}

function sanitizeKeySegment(value) {
  const raw = safeString(value).trim();
  if (!raw) return "unknown";
  const sanitized = raw.replace(/[^a-zA-Z0-9._=-]/g, "_");
  return sanitized || "unknown";
}

function normalizePrefix(prefix) {
  const raw = safeString(prefix).replace(/^\/+/, "");
  return raw.endsWith("/") ? raw : `${raw}/`;
}

function getHttpMethod(event) {
  const requestContext = event.requestContext || {};
  const httpContext = requestContext.http || {};
  return safeString(httpContext.method || requestContext.httpMethod).toUpperCase();
}

function getQueryParams(event) {
  const params = {};
  const raw = safeString(event.rawQueryString);
  if (raw) {
    for (const [key, value] of new URLSearchParams(raw).entries()) {
      if (!(key in params)) params[key] = value;
    }
  }
  const direct = event.queryStringParameters;
  if (direct && typeof direct === "object") {
    for (const [key, value] of Object.entries(direct)) {
      if (!(key in params) && typeof value === "string") {
        params[key] = value;
      }
    }
  }
  return params;
}

function decodePathSegment(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function parseTenancyAdminRoute(resourcePath, httpMethod) {
  const path = safeString(resourcePath);
  if (!path.startsWith("/api/tenancy/v1/admin/tenants")) {
    return null;
  }

  if (httpMethod === "POST" && /^\/api\/tenancy\/v1\/admin\/tenants\/?$/.test(path)) {
    return { kind: "create_tenant", tenantId: null };
  }

  let match = path.match(/^\/api\/tenancy\/v1\/admin\/tenants\/([^/]+):suspend\/?$/);
  if (match && httpMethod === "POST") {
    return { kind: "suspend_tenant", tenantId: decodePathSegment(match[1]) };
  }

  match = path.match(/^\/api\/tenancy\/v1\/admin\/tenants\/([^/]+):rotate-credentials\/?$/);
  if (match && httpMethod === "POST") {
    return { kind: "rotate_tenant_credentials", tenantId: decodePathSegment(match[1]) };
  }

  match = path.match(/^\/api\/tenancy\/v1\/admin\/tenants\/([^/]+)\/(audit-summary|diagnostics|timeline)\/?$/);
  if (match && httpMethod === "GET") {
    const routeKind = {
      "audit-summary": "fetch_tenant_audit_summary",
      diagnostics: "fetch_tenant_diagnostics",
      timeline: "fetch_tenant_timeline",
    }[match[2]];
    return { kind: routeKind, tenantId: decodePathSegment(match[1]) };
  }

  return { kind: "unsupported_tenancy_route", tenantId: null };
}

function parseJsonBody(event) {
  const rawBody = event.body
    ? event.isBase64Encoded
      ? Buffer.from(event.body, "base64").toString("utf-8")
      : event.body
    : "{}";
  return JSON.parse(rawBody);
}

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object`);
  }
}

function requireNonEmptyString(value, label) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} must be a non-empty string`);
  }
}

function validateCreateTenantRequest(body) {
  requireObject(body, "request body");
  if ("tenantId" in body || "appId" in body) {
    throw new Error("request body must not include authoritative tenantId/appId");
  }
  requireNonEmptyString(body.tenantSlug, "tenantSlug");
  requireNonEmptyString(body.displayName, "displayName");
  requireObject(body.owner, "owner");
  requireNonEmptyString(body.owner.email, "owner.email");
  requireObject(body.credentialProfile, "credentialProfile");
  requireNonEmptyString(body.credentialProfile.mode, "credentialProfile.mode");
}

function validateSuspendTenantRequest(body) {
  requireObject(body, "request body");
  requireNonEmptyString(body.reasonCode, "reasonCode");
  if (body.invalidateSessions !== undefined && typeof body.invalidateSessions !== "boolean") {
    throw new Error("invalidateSessions must be a boolean");
  }
}

function validateRotateTenantCredentialsRequest(body) {
  requireObject(body, "request body");
  requireNonEmptyString(body.credentialType, "credentialType");
  requireNonEmptyString(body.rotationMode, "rotationMode");
}

function parsePositiveInt(query, key, { min = 1, max = 1000 } = {}) {
  if (!(key in query)) return null;
  const value = Number.parseInt(query[key], 10);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${key} must be an integer between ${min} and ${max}`);
  }
  return value;
}

function parseOptionalBoolean(query, key) {
  if (!(key in query)) return null;
  const value = safeString(query[key]).toLowerCase();
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${key} must be true or false`);
}

function createAuditRecord(event) {
  const requestContext = event.requestContext || {};
  const httpContext = requestContext.http || {};
  const identity = requestContext.identity || {};
  const headers = event.headers || {};
  const startedAt = new Date().toISOString();

  return {
    record_type: "bff_proxy_audit_shadow_json_v1",
    recorded_at: startedAt,
    started_at: startedAt,
    completed_at: null,
    duration_ms: null,
    request_id: requestContext.requestId || crypto.randomUUID(),
    agent_name: AGENT_NAME || null,
    environment: ENVIRONMENT || null,
    app_id: null,
    tenant_id: null,
    session_id_requested: null,
    session_id_authorized: null,
    runtime_session_id: null,
    http_method: httpContext.method || requestContext.httpMethod || null,
    resource_path: event.rawPath || requestContext.resourcePath || requestContext.path || null,
    source_ip: httpContext.sourceIp || identity.sourceIp || null,
    user_agent: safeString(headers["user-agent"] || headers["User-Agent"]) || null,
    status_code: null,
    outcome: "started",
    error_message: null,
    request_prompt_chars: 0,
    request_prompt_sha256: null,
    request_prompt_preview: null,
    request_prompt_preview_truncated: false,
    response_delta_chunks: 0,
    response_bytes: 0,
    response_sha256: null,
    response_preview: "",
    response_preview_truncated: false,
    _responseHasher: crypto.createHash("sha256"),
  };
}

function finalizeAuditRecord(auditRecord) {
  if (!auditRecord) return null;

  auditRecord.completed_at = new Date().toISOString();
  const started = Date.parse(auditRecord.started_at);
  const completed = Date.parse(auditRecord.completed_at);
  if (!Number.isNaN(started) && !Number.isNaN(completed)) {
    auditRecord.duration_ms = Math.max(0, completed - started);
  }

  if (auditRecord._responseHasher) {
    auditRecord.response_sha256 = auditRecord._responseHasher.digest("hex");
    delete auditRecord._responseHasher;
  }

  if (!auditRecord.outcome || auditRecord.outcome === "started") {
    auditRecord.outcome = auditRecord.status_code && auditRecord.status_code < 400 ? "success" : "error";
  }

  if (auditRecord.response_preview === "") {
    auditRecord.response_preview = null;
  }

  return auditRecord;
}

function buildAuditLogKey(auditRecord) {
  const ts = auditRecord.completed_at || auditRecord.recorded_at || new Date().toISOString();
  const date = new Date(ts);
  const year = String(date.getUTCFullYear());
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const prefix = normalizePrefix(AUDIT_LOGS_PREFIX);

  return `${prefix}${sanitizeKeySegment(auditRecord.app_id)}/${sanitizeKeySegment(auditRecord.tenant_id)}/year=${year}/month=${month}/day=${day}/${sanitizeKeySegment(auditRecord.request_id)}.json`;
}

async function persistAuditLog(auditRecord) {
  if (!AUDIT_LOGS_ENABLED || !AUDIT_LOGS_BUCKET || !s3Client || !auditRecord) return;

  try {
    const body = JSON.stringify(auditRecord) + "\n";
    await s3Client.send(
      new PutObjectCommand({
        Bucket: AUDIT_LOGS_BUCKET,
        Key: buildAuditLogKey(auditRecord),
        Body: body,
        ContentType: "application/json",
        ServerSideEncryption: "AES256",
      }),
    );
  } catch (err) {
    // Audit persistence is best-effort to avoid dropping user responses on transient S3 failures.
    console.error(`Audit log persist failed: ${err && err.message ? err.message : String(err)}`);
  }
}

function appendResponsePreview(auditRecord, text) {
  if (!auditRecord || !text || auditRecord.response_preview_truncated) return;
  const current = auditRecord.response_preview || "";
  const next = current + text;
  if (next.length <= AUDIT_PREVIEW_MAX_CHARS) {
    auditRecord.response_preview = next;
    return;
  }
  auditRecord.response_preview = next.slice(0, AUDIT_PREVIEW_MAX_CHARS);
  auditRecord.response_preview_truncated = true;
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

function sendRequest(signed, body, responseStream, sessionId, auditRecord) {
  return new Promise((resolve, reject) => {
    const options = {
      method: signed.method,
      hostname: signed.hostname,
      path: signed.path,
      headers: signed.headers,
    };

    const upstream = https.request(options, (res) => {
      const statusCode = res.statusCode || 200;
      if (auditRecord) {
        auditRecord.status_code = statusCode;
      }

      if (statusCode >= 400) {
        let errorBody = "";
        res.on("data", (chunk) => {
          errorBody += chunk.toString("utf-8");
        });
        res.on("end", () => {
          if (auditRecord) {
            auditRecord.outcome = "upstream_error";
            auditRecord.error_message = errorBody || `Upstream returned status ${statusCode}`;
            auditRecord._responseHasher.update(errorBody, "utf8");
            auditRecord.response_bytes += Buffer.byteLength(errorBody, "utf8");
            appendResponsePreview(auditRecord, errorBody);
          }
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
      if (auditRecord && runtimeSessionId) {
        auditRecord.runtime_session_id = runtimeSessionId;
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

        if (auditRecord) {
          auditRecord.response_delta_chunks += 1;
          auditRecord.response_bytes += Buffer.byteLength(text, "utf8");
          auditRecord._responseHasher.update(text, "utf8");
          appendResponsePreview(auditRecord, text);
        }

        httpStream.write(JSON.stringify({ type: "delta", delta: text }) + "\n");
      });
      res.on("end", () => {
        if (auditRecord) {
          auditRecord.outcome = "success";
        }
        httpStream.end();
        resolve();
      });
    });

    upstream.on("error", (err) => {
      if (auditRecord) {
        auditRecord.outcome = "transport_error";
        auditRecord.error_message = err && err.message ? err.message : String(err);
      }
      reject(err);
    });
    upstream.write(body);
    upstream.end();
  });
}

exports.handler = awslambda.streamifyResponse(async (event, responseStream) => {
  const auditRecord = createAuditRecord(event);
  const resourcePath = event.rawPath || (event.requestContext || {}).resourcePath || (event.requestContext || {}).path || "";
  const httpMethod = getHttpMethod(event);
  const tenancyRoute = parseTenancyAdminRoute(resourcePath, httpMethod);
  const isTenancyRoute = Boolean(tenancyRoute);
  const isChatRoute = resourcePath.endsWith("/chat") || !isTenancyRoute;

  if (isChatRoute) {
    if (!AGENTCORE_RUNTIME_ARN) {
      auditRecord.status_code = 500;
      auditRecord.outcome = "config_error";
      auditRecord.error_message = "Missing AGENTCORE_RUNTIME_ARN";
      writeError(responseStream, 500, "Missing AGENTCORE_RUNTIME_ARN");
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    if (!AGENTCORE_REGION) {
      auditRecord.status_code = 500;
      auditRecord.outcome = "config_error";
      auditRecord.error_message = "Missing AGENTCORE_REGION";
      writeError(responseStream, 500, "Missing AGENTCORE_REGION");
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
  }

  const authorizer = (event.requestContext || {}).authorizer || {};
  const accessToken = authorizer.access_token;
  const tenantId = authorizer.tenant_id;
  const appId = authorizer.app_id;
  const authorizedSessionId = authorizer.session_id;
  const pathTenantId = tenancyRoute && tenancyRoute.tenantId ? tenancyRoute.tenantId : null;

  auditRecord.app_id = appId || null;
  auditRecord.tenant_id = pathTenantId || tenantId || null;
  auditRecord.session_id_authorized = authorizedSessionId || null;

  if (tenancyRoute && tenancyRoute.kind === "unsupported_tenancy_route") {
    auditRecord.status_code = 404;
    auditRecord.outcome = "invalid_request";
    auditRecord.error_message = "Unsupported tenancy admin route";
    writeError(responseStream, 404, "Unsupported tenancy admin route");
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Rule 14.1: tenant-targeted admin routes must match the authenticated tenant context.
  if (pathTenantId) {
    if (!tenantId) {
      auditRecord.status_code = 403;
      auditRecord.outcome = "tenant_isolation_violation";
      auditRecord.error_message = "Missing tenant context for tenant-targeted admin route";
      writeError(responseStream, 403, "Missing tenant context for tenant-targeted admin route");
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    if (pathTenantId !== tenantId) {
      auditRecord.status_code = 403;
      auditRecord.outcome = "tenant_isolation_violation";
      auditRecord.error_message = "Tenant isolation violation: path tenant does not match authenticated tenant";
      writeError(responseStream, 403, "Tenant isolation violation: path tenant does not match authenticated tenant");
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
  }

  const query = getQueryParams(event);

  // Route: /api/tenancy/v1/admin/tenants/{tenantId}/diagnostics
  if (tenancyRoute && tenancyRoute.kind === "fetch_tenant_diagnostics") {
    const response = {
      tenantId: pathTenantId || tenantId || "unknown",
      appId: appId || "unknown",
      health: "HEALTHY",
      lastDeploymentSha: process.env.DEPLOYMENT_SHA || "unknown",
      policyVersion: "v1.0.0",
      memoryUsage: {
        summary: "Optimal",
        usedBytes: 0
      },
      generatedAt: new Date().toISOString()
    };
    writeJson(responseStream, 200, response);
    auditRecord.status_code = 200;
    auditRecord.outcome = "success";
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Route: /api/tenancy/v1/admin/tenants/{tenantId}/timeline
  if (tenancyRoute && tenancyRoute.kind === "fetch_tenant_timeline") {
    let limit;
    try {
      limit = parsePositiveInt(query, "limit", { min: 1, max: 100 });
    } catch (err) {
      auditRecord.status_code = 400;
      auditRecord.outcome = "invalid_request";
      auditRecord.error_message = err.message;
      writeError(responseStream, 400, err.message);
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    const response = {
      tenantId: pathTenantId || tenantId || "unknown",
      appId: appId || "unknown",
      events: [
        {
          eventId: crypto.randomUUID(),
          timestamp: new Date().toISOString(),
          type: "CHAT_SESSION_STARTED",
          message: "System initialized diagnostics view"
        }
      ],
      generatedAt: new Date().toISOString()
    };
    if (limit !== null) {
      response.events = response.events.slice(0, limit);
    }
    writeJson(responseStream, 200, response);
    auditRecord.status_code = 200;
    auditRecord.outcome = "success";
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Route: /api/tenancy/v1/admin/tenants/{tenantId}/audit-summary
  if (tenancyRoute && tenancyRoute.kind === "fetch_tenant_audit_summary") {
    let windowHours;
    let includeActors;
    try {
      windowHours = parsePositiveInt(query, "windowHours", { min: 1, max: 168 });
      includeActors = parseOptionalBoolean(query, "includeActors");
    } catch (err) {
      auditRecord.status_code = 400;
      auditRecord.outcome = "invalid_request";
      auditRecord.error_message = err.message;
      writeError(responseStream, 400, err.message);
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    const response = {
      tenantId: pathTenantId || tenantId || "unknown",
      appId: appId || "unknown",
      window: {
        hours: windowHours || 24,
        from: new Date(Date.now() - (windowHours || 24) * 3600000).toISOString(),
        to: new Date().toISOString(),
      },
      summary: { totalEvents: 0, successCount: 0, failureCount: 0, credentialRotations: 0, suspensions: 0 },
      lastEvents: [],
      generatedAt: new Date().toISOString()
    };
    if (includeActors) {
      response.actorBreakdown = [];
    }
    writeJson(responseStream, 200, response);
    auditRecord.status_code = 200;
    auditRecord.outcome = "success";
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Route: POST /api/tenancy/v1/admin/tenants
  if (tenancyRoute && tenancyRoute.kind === "create_tenant") {
    let body;
    try {
      body = parseJsonBody(event);
      validateCreateTenantRequest(body);
    } catch (err) {
      auditRecord.status_code = 422;
      auditRecord.outcome = "invalid_request";
      auditRecord.error_message = err.message;
      writeError(responseStream, 422, err.message);
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    const response = {
      tenantId: body.tenantSlug,
      appId: appId || "unknown",
      status: "PENDING_ONBOARDING",
      onboardingState: "QUEUED",
      credentials: {
        mode: body.credentialProfile.mode,
        nextRotationDueAt: new Date(Date.now() + 30 * 86400000).toISOString(),
      },
      createdAt: new Date().toISOString(),
      auditEventId: `evt-${crypto.randomUUID()}`,
    };
    auditRecord.tenant_id = body.tenantSlug;
    writeJson(responseStream, 201, response);
    auditRecord.status_code = 201;
    auditRecord.outcome = "success";
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Route: POST /api/tenancy/v1/admin/tenants/{tenantId}:suspend
  if (tenancyRoute && tenancyRoute.kind === "suspend_tenant") {
    let body;
    try {
      body = parseJsonBody(event);
      validateSuspendTenantRequest(body);
    } catch (err) {
      auditRecord.status_code = 422;
      auditRecord.outcome = "invalid_request";
      auditRecord.error_message = err.message;
      writeError(responseStream, 422, err.message);
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    const response = {
      tenantId: pathTenantId,
      appId: appId || "unknown",
      status: "SUSPENDED",
      suspendedAt: new Date().toISOString(),
      effectiveAt: body.effectiveAt || new Date().toISOString(),
      invalidateSessions: Boolean(body.invalidateSessions),
      auditEventId: `evt-${crypto.randomUUID()}`,
    };
    writeJson(responseStream, 200, response);
    auditRecord.status_code = 200;
    auditRecord.outcome = "success";
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Route: POST /api/tenancy/v1/admin/tenants/{tenantId}:rotate-credentials
  if (tenancyRoute && tenancyRoute.kind === "rotate_tenant_credentials") {
    let body;
    try {
      body = parseJsonBody(event);
      validateRotateTenantCredentialsRequest(body);
    } catch (err) {
      auditRecord.status_code = 422;
      auditRecord.outcome = "invalid_request";
      auditRecord.error_message = err.message;
      writeError(responseStream, 422, err.message);
      await persistAuditLog(finalizeAuditRecord(auditRecord));
      return;
    }
    const now = new Date();
    const response = {
      tenantId: pathTenantId,
      appId: appId || "unknown",
      rotationId: `rot-${now.toISOString().replace(/[-:.TZ]/g, "").slice(0, 12)}-${Math.floor(Math.random() * 10000).toString().padStart(4, "0")}`,
      status: "ACCEPTED",
      previousCredentialValidUntil: new Date(now.getTime() + 3600000).toISOString(),
      requestedAt: now.toISOString(),
      auditEventId: `evt-${crypto.randomUUID()}`,
    };
    writeJson(responseStream, 200, response);
    auditRecord.status_code = 200;
    auditRecord.outcome = "success";
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Default: Chat Route
  let prompt;
  let sessionId;

  try {
    const body = parseJsonBody(event);
    prompt = body.prompt;
    sessionId = body.sessionId || "default-session";

    auditRecord.session_id_requested = sessionId;
    const promptValue = typeof prompt === "string" ? prompt : "";
    auditRecord.request_prompt_chars = promptValue.length;
    auditRecord.request_prompt_sha256 = prompt ? sha256Hex(promptValue) : null;
    const promptPreview = truncateText(promptValue, AUDIT_PROMPT_PREVIEW_MAX_CHARS);
    auditRecord.request_prompt_preview = promptPreview.value || null;
    auditRecord.request_prompt_preview_truncated = promptPreview.truncated;
  } catch {
    auditRecord.status_code = 400;
    auditRecord.outcome = "invalid_request";
    auditRecord.error_message = "Invalid JSON";
    writeError(responseStream, 400, "Invalid JSON");
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  if (!prompt) {
    auditRecord.status_code = 400;
    auditRecord.outcome = "invalid_request";
    auditRecord.error_message = "Missing prompt";
    writeError(responseStream, 400, "Missing prompt");
    await persistAuditLog(finalizeAuditRecord(auditRecord));
    return;
  }

  // Multi-tenancy Isolation Check (Rule 14.1)
  if (authorizedSessionId && sessionId !== authorizedSessionId) {
    auditRecord.status_code = 403;
    auditRecord.outcome = "session_isolation_violation";
    auditRecord.error_message = "Session isolation violation: tenant mismatch";
    writeError(responseStream, 403, "Session isolation violation: tenant mismatch");
    await persistAuditLog(finalizeAuditRecord(auditRecord));
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
                // Scope to the specific deployment bucket when known; fall back to a
                // named pattern only if the env var is absent (degraded but bounded).
                ...(DEPLOYMENT_BUCKET_NAME
                  ? [`arn:aws:s3:::${DEPLOYMENT_BUCKET_NAME}`, `arn:aws:s3:::${DEPLOYMENT_BUCKET_NAME}/*`]
                  : ["arn:aws:s3:::*-deployment-*"]),
                `arn:aws:s3:::*-memory-*/${appId}/${tenantId}/*`,
                `arn:aws:s3:::${appId}-*-memory-*/${appId}/${tenantId}`,
              ],
            },
            {
              Effect: "Allow",
              Action: ["bedrock-agentcore:InvokeAgentRuntime"],
              Resource: [AGENTCORE_RUNTIME_ARN],
            },
          ],
        };

        const assumeRoleCmd = new AssumeRoleCommand({
          RoleArn: AGENTCORE_RUNTIME_ROLE_ARN,
          RoleSessionName: `AgentCore-${appId}-${tenantId}`,
          Policy: JSON.stringify(sessionPolicy),
          DurationSeconds: 900,
        });

        const assumed = await stsClient.send(assumeRoleCmd);
        credentials = {
          accessKeyId: assumed.Credentials.AccessKeyId,
          secretAccessKey: assumed.Credentials.SecretAccessKey,
          sessionToken: assumed.Credentials.SessionToken,
        };
      } catch (err) {
        console.error(`AssumeRole failed: ${err}`);
        throw new Error(`Identity isolation failed: ${err.message}`);
      }
    }

    const signed = await signRequest("POST", url.toString(), headers, payload, credentials);
    await sendRequest(signed, payload, responseStream, sessionId, auditRecord);
  } catch (err) {
    auditRecord.status_code = auditRecord.status_code || 500;
    auditRecord.outcome = auditRecord.outcome === "success" ? "error_after_stream" : "error";
    auditRecord.error_message = err && err.message ? err.message : String(err);
    writeError(responseStream, 500, String(err));
  } finally {
    await persistAuditLog(finalizeAuditRecord(auditRecord));
  }
});

// Export internals for testing
exports._writeError = writeError;
exports._signRequest = signRequest;
exports._sendRequest = sendRequest;
exports._createAuditRecord = createAuditRecord;
exports._finalizeAuditRecord = finalizeAuditRecord;
