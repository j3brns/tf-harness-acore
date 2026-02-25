const EventEmitter = require("events");

// --- Mock awslambda global ---
const mockStreamWrite = jest.fn();
const mockStreamEnd = jest.fn();
const mockHttpStream = { write: mockStreamWrite, end: mockStreamEnd };

// --- Mock STS ---
const mockStsSend = jest.fn();
jest.mock("@aws-sdk/client-sts", () => ({
  STSClient: jest.fn(() => ({ send: mockStsSend })),
  AssumeRoleCommand: jest.fn((args) => args),
}));

// --- Mock S3 (audit persistence) ---
const mockS3Send = jest.fn();
jest.mock("@aws-sdk/client-s3", () => ({
  S3Client: jest.fn(() => ({ send: mockS3Send })),
  PutObjectCommand: jest.fn((args) => args),
}));

function setupAwsLambdaGlobal() {
  global.awslambda = {
    HttpResponseStream: {
      from: jest.fn(() => mockHttpStream),
    },
    streamifyResponse: (fn) => fn,
  };
}

// --- Mock https (shared reference) ---
const mockHttpsRequest = jest.fn();
jest.mock("https", () => ({ request: mockHttpsRequest }));

// --- Set env vars BEFORE requiring proxy ---
process.env.AGENTCORE_RUNTIME_ARN =
  "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/test";
process.env.AGENTCORE_REGION = "us-east-1";

setupAwsLambdaGlobal();
const { handler, _writeError } = require("./proxy");
// Capture the SAME SignatureV4 mock that proxy.js uses (before resetModules corrupts cache)
const { SignatureV4 } = require("@smithy/signature-v4");
const { STSClient, AssumeRoleCommand } = require("@aws-sdk/client-sts");

// --- Helpers ---
function makeEvent(body, overrides = {}) {
  return {
    body: typeof body === "string" ? body : JSON.stringify(body),
    isBase64Encoded: false,
    requestContext: { authorizer: overrides.authorizer || {} },
    ...overrides,
  };
}

function mockResponseStream() {
  return { _mock: true };
}

/**
 * Sets up https.request mock that invokes the callback with a fake response,
 * then emits data chunks and "end" on the next tick (after listeners attach).
 */
function setupMockRequest(statusCode, headers, chunks) {
  const mockReq = new EventEmitter();
  mockReq.write = jest.fn();
  mockReq.end = jest.fn();

  mockHttpsRequest.mockImplementation((_opts, cb) => {
    const res = new EventEmitter();
    res.statusCode = statusCode;
    res.headers = headers || {};

    // Tick 1: invoke callback so listeners attach
    process.nextTick(() => {
      cb(res);
      // Tick 2: emit data + end after listeners are wired
      process.nextTick(() => {
        for (const chunk of chunks) {
          res.emit("data", Buffer.from(chunk, "utf-8"));
        }
        res.emit("end");
      });
    });

    return mockReq;
  });

  return mockReq;
}

// --- Tests ---
describe("proxy.js", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockStreamWrite.mockClear();
    mockStreamEnd.mockClear();
    mockHttpsRequest.mockClear();
    mockStsSend.mockClear();
    mockS3Send.mockClear();
    setupAwsLambdaGlobal();
  });

  describe("input validation", () => {
    test("returns 500 when AGENTCORE_RUNTIME_ARN is missing", async () => {
      const savedArn = process.env.AGENTCORE_RUNTIME_ARN;
      delete process.env.AGENTCORE_RUNTIME_ARN;
      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: jest.fn() }));
      const { handler: h } = require("./proxy");

      const stream = mockResponseStream();
      await h(makeEvent({ prompt: "hi" }), stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 500,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Missing AGENTCORE_RUNTIME_ARN" })
      );

      process.env.AGENTCORE_RUNTIME_ARN = savedArn;
    });

    test("returns 500 when AGENTCORE_REGION is missing", async () => {
      const savedRegion = process.env.AGENTCORE_REGION;
      const savedAws = process.env.AWS_REGION;
      delete process.env.AGENTCORE_REGION;
      delete process.env.AWS_REGION;
      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: jest.fn() }));
      process.env.AGENTCORE_RUNTIME_ARN =
        "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/test";
      const { handler: h } = require("./proxy");

      const stream = mockResponseStream();
      await h(makeEvent({ prompt: "hi" }), stream);

      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Missing AGENTCORE_REGION" })
      );

      process.env.AGENTCORE_REGION = savedRegion;
      if (savedAws) process.env.AWS_REGION = savedAws;
    });

    test("returns 400 for invalid JSON body", async () => {
      const stream = mockResponseStream();
      await handler({ body: "not-json{{{", isBase64Encoded: false, requestContext: {} }, stream);

      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Invalid JSON" })
      );
    });

    test("returns 400 when prompt is missing", async () => {
      const stream = mockResponseStream();
      await handler(makeEvent({ notPrompt: "hi" }), stream);

      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Missing prompt" })
      );
    });
  });

  describe("happy path streaming", () => {
    test("streams NDJSON response with meta and delta events", async () => {
      setupMockRequest(
        200,
        { "x-amzn-bedrock-agentcore-runtime-session-id": "sess-123" },
        ["chunk1", "chunk2"]
      );

      const stream = mockResponseStream();
      await handler(makeEvent({ prompt: "hello", sessionId: "my-sess" }), stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: expect.objectContaining({
          "content-type": "application/x-ndjson; charset=utf-8",
          "cache-control": "no-cache",
          "x-amzn-bedrock-agentcore-runtime-session-id": "sess-123",
        }),
      });

      expect(mockStreamWrite).toHaveBeenCalledWith(
        JSON.stringify({ type: "meta", sessionId: "sess-123" }) + "\n"
      );
      expect(mockStreamWrite).toHaveBeenCalledWith(
        JSON.stringify({ type: "delta", delta: "chunk1" }) + "\n"
      );
      expect(mockStreamWrite).toHaveBeenCalledWith(
        JSON.stringify({ type: "delta", delta: "chunk2" }) + "\n"
      );
      expect(mockStreamEnd).toHaveBeenCalled();
    });

    test("uses default-session when sessionId is not provided", async () => {
      setupMockRequest(200, {}, ["data"]);

      const stream = mockResponseStream();
      await handler(makeEvent({ prompt: "hello" }), stream);

      expect(mockStreamWrite).toHaveBeenCalledWith(
        expect.stringContaining('"sessionId":"default-session"')
      );
    });
  });

  describe("upstream errors", () => {
    test("forwards upstream 4xx/5xx as error response", async () => {
      setupMockRequest(403, {}, ["Access Denied"]);

      const stream = mockResponseStream();
      await handler(makeEvent({ prompt: "hello" }), stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 403,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Access Denied" })
      );
    });

    test("handles network errors from upstream", async () => {
      const mockReq = new EventEmitter();
      mockReq.write = jest.fn();
      mockReq.end = jest.fn();
      mockHttpsRequest.mockImplementation(() => {
        process.nextTick(() => mockReq.emit("error", new Error("ECONNREFUSED")));
        return mockReq;
      });

      const stream = mockResponseStream();
      await handler(makeEvent({ prompt: "hello" }), stream);

      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Error: ECONNREFUSED" })
      );
    });
  });

  describe("base64 body decoding", () => {
    test("decodes base64 body when isBase64Encoded is true", async () => {
      setupMockRequest(200, {}, ["ok"]);

      const b64Body = Buffer.from(JSON.stringify({ prompt: "encoded" })).toString("base64");
      const stream = mockResponseStream();
      await handler(
        { body: b64Body, isBase64Encoded: true, requestContext: {} },
        stream
      );

      expect(mockStreamEnd).toHaveBeenCalled();
      expect(mockHttpsRequest).toHaveBeenCalled();
    });
  });

  describe("access token forwarding", () => {
    test("includes authorization header when access_token is present", async () => {
      setupMockRequest(200, {}, ["ok"]);

      const stream = mockResponseStream();
      await handler(
        makeEvent({ prompt: "hello" }, { authorizer: { access_token: "tok-abc" } }),
        stream
      );

      // SignatureV4 was instantiated; grab the sign mock from that instance
      expect(SignatureV4).toHaveBeenCalled();
      // mockImplementation returns from the factory, captured in mock.results
      const instance = SignatureV4.mock.results[SignatureV4.mock.results.length - 1].value;
      const signCall = instance.sign.mock.calls[0][0];
      expect(signCall.headers.authorization).toBe("Bearer tok-abc");
    });

    test("does not include authorization header when access_token is absent", async () => {
      setupMockRequest(200, {}, ["ok"]);

      const stream = mockResponseStream();
      await handler(makeEvent({ prompt: "hello" }), stream);

      const instance = SignatureV4.mock.results[SignatureV4.mock.results.length - 1].value;
      const signCall = instance.sign.mock.calls[0][0];
      expect(signCall.headers.authorization).toBeUndefined();
    });
  });

  describe("Multi-tenancy and Isolation (Rule 14)", () => {
    test("forwards tenant_id header when present in authorizer context", async () => {
      setupMockRequest(200, {}, ["ok"]);

      const stream = mockResponseStream();
      await handler(
        makeEvent(
          { prompt: "hello" },
          { authorizer: { tenant_id: "tenant-123", access_token: "tok", app_id: "test-app" } }
        ),
        stream
      );

      const instance = SignatureV4.mock.results[SignatureV4.mock.results.length - 1].value;
      const signCall = instance.sign.mock.calls[0][0];
      expect(signCall.headers["x-tenant-id"]).toBe("tenant-123");
      expect(signCall.headers["x-app-id"]).toBe("test-app");
    });

    test("prevents cross-tenant session access (Rule 14.1)", async () => {
      const stream = mockResponseStream();
      const event = makeEvent(
        { prompt: "hello", sessionId: "session-tenant-B" },
        {
          authorizer: {
            tenant_id: "tenant-A",
            session_id: "session-tenant-A"
          }
        }
      );

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 403,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Session isolation violation: tenant mismatch" })
      );
    });

    test("performs physical isolation via AssumeRole (Rule 14.3)", async () => {
      process.env.AGENTCORE_RUNTIME_ROLE_ARN = "arn:aws:iam::123456789012:role/runtime";
      setupMockRequest(200, {}, ["ok"]);

      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: mockHttpsRequest }));
      jest.mock("@aws-sdk/client-sts", () => ({
        STSClient: jest.fn(() => ({ send: mockStsSend })),
        AssumeRoleCommand: jest.fn((args) => args),
      }));
      // Re-mock SignatureV4 for this isolated test
      jest.mock("@smithy/signature-v4", () => ({
        SignatureV4: jest.fn().mockImplementation(() => ({
          sign: jest.fn().mockResolvedValue({
            method: "POST", hostname: "host", path: "/", headers: {},
          }),
        })),
      }));

      const { handler: h } = require("./proxy");
      const { SignatureV4: SigV4 } = require("@smithy/signature-v4");

      mockStsSend.mockResolvedValue({
        Credentials: {
          AccessKeyId: "ak-assumed",
          SecretAccessKey: "sk-assumed",
          SessionToken: "tok-assumed",
        }
      });

      const stream = mockResponseStream();
      await h(
        makeEvent(
          { prompt: "hello" },
          { authorizer: { tenant_id: "tenant-A", app_id: "app-A", session_id: "default-session" } }
        ),
        stream
      );

      expect(mockStsSend).toHaveBeenCalled();
      const assumeCall = mockStsSend.mock.calls[0][0];
      expect(assumeCall.RoleArn).toBe("arn:aws:iam::123456789012:role/runtime");
      expect(assumeCall.RoleSessionName).toBe("AgentCore-app-A-tenant-A");

      const policy = JSON.parse(assumeCall.Policy);
      const s3Statement = policy.Statement.find(s => s.Action.includes("s3:GetObject"));
      expect(s3Statement.Resource).toContain("arn:aws:s3:::*-memory-*/app-A/tenant-A/*");

      // Verify credentials were used for signing
      const sigV4Instance = SigV4.mock.results[SigV4.mock.results.length - 1].value;
      const credentialsUsed = SigV4.mock.calls[SigV4.mock.calls.length - 1][0].credentials;
      expect(credentialsUsed.accessKeyId).toBe("ak-assumed");

      delete process.env.AGENTCORE_RUNTIME_ROLE_ARN;
    });
  });

  describe("ABAC claim mismatch paths (Rule 14)", () => {
    test("does not call AssumeRole when tenant_id is absent from authorizer context", async () => {
      process.env.AGENTCORE_RUNTIME_ROLE_ARN = "arn:aws:iam::123456789012:role/runtime";
      setupMockRequest(200, {}, ["ok"]);

      const stream = mockResponseStream();
      // app_id is present but tenant_id is missing — AssumeRole requires both
      await handler(
        makeEvent({ prompt: "hello" }, { authorizer: { app_id: "app-A" } }),
        stream
      );

      expect(mockStsSend).not.toHaveBeenCalled();

      delete process.env.AGENTCORE_RUNTIME_ROLE_ARN;
    });

    test("does not call AssumeRole when app_id is absent from authorizer context", async () => {
      process.env.AGENTCORE_RUNTIME_ROLE_ARN = "arn:aws:iam::123456789012:role/runtime";
      setupMockRequest(200, {}, ["ok"]);

      const stream = mockResponseStream();
      // tenant_id is present but app_id is missing — AssumeRole requires both
      await handler(
        makeEvent({ prompt: "hello" }, { authorizer: { tenant_id: "tenant-A" } }),
        stream
      );

      expect(mockStsSend).not.toHaveBeenCalled();

      delete process.env.AGENTCORE_RUNTIME_ROLE_ARN;
    });

    test("does not set x-tenant-id header when tenant_id is absent from authorizer context", async () => {
      setupMockRequest(200, {}, ["ok"]);

      const stream = mockResponseStream();
      await handler(makeEvent({ prompt: "hello" }, { authorizer: { app_id: "app-A" } }), stream);

      const instance = SignatureV4.mock.results[SignatureV4.mock.results.length - 1].value;
      const signCall = instance.sign.mock.calls[0][0];
      expect(signCall.headers["x-tenant-id"]).toBeUndefined();
    });
  });

  describe("Tenancy Admin API", () => {
    test("returns diagnostics mock response", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance/diagnostics",
        requestContext: {
          http: { method: "GET" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "app-1"
          }
        }
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: { "content-type": "application/json" },
      });
      const response = JSON.parse(mockStreamEnd.mock.calls[0][0]);
      expect(response.tenantId).toBe("acme-finance");
      expect(response.health).toBe("HEALTHY");
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });

    test("rejects tenant admin route when path tenant does not match authorizer tenant", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance/diagnostics",
        requestContext: {
          http: { method: "GET" },
          authorizer: {
            tenant_id: "other-tenant",
            app_id: "app-1"
          }
        }
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 403,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Tenant isolation violation: path tenant does not match authenticated tenant" })
      );
    });

    test("returns timeline mock response", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance/timeline",
        rawQueryString: "limit=1",
        requestContext: {
          http: { method: "GET" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "app-1"
          }
        }
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: { "content-type": "application/json" },
      });
      const response = JSON.parse(mockStreamEnd.mock.calls[0][0]);
      expect(response.events).toBeInstanceOf(Array);
      expect(response.events.length).toBe(1);
    });

    test("returns audit-summary mock response", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance/audit-summary",
        rawQueryString: "windowHours=12&includeActors=true",
        requestContext: {
          http: { method: "GET" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "app-1"
          }
        }
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: { "content-type": "application/json" },
      });
      const response = JSON.parse(mockStreamEnd.mock.calls[0][0]);
      expect(response.summary).toBeDefined();
      expect(response.window.hours).toBe(12);
      expect(response.actorBreakdown).toEqual([]);
    });

    test("returns create-tenant stub response and does not fall through to chat", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "admin-tenant",
            app_id: "portal-prod"
          }
        },
        body: JSON.stringify({
          tenantSlug: "acme-finance",
          displayName: "Acme Finance",
          owner: { email: "owner@acme.example" },
          credentialProfile: { mode: "PORTAL_CLIENT_SECRET" }
        }),
        isBase64Encoded: false
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 201,
        headers: { "content-type": "application/json" },
      });
      const response = JSON.parse(mockStreamEnd.mock.calls[0][0]);
      expect(response.tenantId).toBe("acme-finance");
      expect(response.appId).toBe("portal-prod");
      expect(response.status).toBe("PENDING_ONBOARDING");
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });

    test("returns 422 when create-tenant body includes authoritative tenant fields", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "admin-tenant",
            app_id: "portal-prod"
          }
        },
        body: JSON.stringify({
          tenantId: "should-not-be-accepted",
          tenantSlug: "acme-finance",
          displayName: "Acme Finance",
          owner: { email: "owner@acme.example" },
          credentialProfile: { mode: "PORTAL_CLIENT_SECRET" }
        }),
        isBase64Encoded: false
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 422,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "request body must not include authoritative tenantId/appId" })
      );
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });

    test("returns suspend-tenant stub response", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance:suspend",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "portal-prod"
          }
        },
        body: JSON.stringify({
          reasonCode: "SECURITY",
          invalidateSessions: true
        }),
        isBase64Encoded: false
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: { "content-type": "application/json" },
      });
      const response = JSON.parse(mockStreamEnd.mock.calls[0][0]);
      expect(response.tenantId).toBe("acme-finance");
      expect(response.status).toBe("SUSPENDED");
      expect(response.invalidateSessions).toBe(true);
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });

    test("returns 403 for tenant-targeted admin route when authorizer tenant is missing", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance:suspend",
        requestContext: {
          http: { method: "POST" },
          authorizer: { app_id: "portal-prod" }
        },
        body: JSON.stringify({ reasonCode: "SECURITY" }),
        isBase64Encoded: false
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 403,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Missing tenant context for tenant-targeted admin route" })
      );
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });

    test("returns rotate-credentials stub response", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance:rotate-credentials",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "portal-prod"
          }
        },
        body: JSON.stringify({
          credentialType: "OIDC_CLIENT_SECRET",
          rotationMode: "GRACEFUL"
        }),
        isBase64Encoded: false
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: { "content-type": "application/json" },
      });
      const response = JSON.parse(mockStreamEnd.mock.calls[0][0]);
      expect(response.tenantId).toBe("acme-finance");
      expect(response.status).toBe("ACCEPTED");
      expect(response.rotationId).toMatch(/^rot-/);
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });

    test("returns 422 for invalid rotate-credentials request body", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance:rotate-credentials",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "portal-prod"
          }
        },
        body: JSON.stringify({
          rotationMode: "GRACEFUL"
        }),
        isBase64Encoded: false
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 422,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "credentialType must be a non-empty string" })
      );
    });

    test("returns 404 for unsupported tenancy admin route instead of falling through to chat", async () => {
      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance/unknown-action",
        requestContext: {
          http: { method: "GET" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "portal-prod"
          }
        }
      };

      await handler(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 404,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Unsupported tenancy admin route" })
      );
      expect(mockHttpsRequest).not.toHaveBeenCalled();
    });
  });

  describe("audit logging", () => {
    test("persists tenant-admin audit logs to S3 with sanitized key and SSE-S3", async () => {
      process.env.AUDIT_LOGS_ENABLED = "true";
      process.env.AUDIT_LOGS_BUCKET = "audit-bucket";
      process.env.AUDIT_LOGS_PREFIX = "/audit/custom";

      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: mockHttpsRequest }));
      const { handler: h } = require("./proxy");
      const { S3Client: S3ClientLocal, PutObjectCommand: PutObjectCommandLocal } = require("@aws-sdk/client-s3");

      mockS3Send.mockResolvedValueOnce({});

      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme%2Ffinance/diagnostics",
        requestContext: {
          requestId: "req:1",
          http: { method: "GET" },
          authorizer: {
            tenant_id: "acme/finance",
            app_id: "portal prod"
          }
        }
      };

      await h(event, stream);

      expect(S3ClientLocal).toHaveBeenCalled();
      expect(mockS3Send).toHaveBeenCalledTimes(1);
      expect(PutObjectCommandLocal).toHaveBeenCalledTimes(1);
      const putArgs = mockS3Send.mock.calls[0][0];
      expect(putArgs.Bucket).toBe("audit-bucket");
      expect(putArgs.ContentType).toBe("application/json");
      expect(putArgs.ServerSideEncryption).toBe("AES256");
      expect(putArgs.Key).toMatch(/^audit\/custom\//);
      expect(putArgs.Key).toContain("portal_prod/acme_finance/");
      expect(putArgs.Key).toContain("req_1.json");

      const body = JSON.parse(String(putArgs.Body).trim());
      expect(body.app_id).toBe("portal prod");
      expect(body.tenant_id).toBe("acme/finance");
      expect(body.status_code).toBe(200);
      expect(body.outcome).toBe("success");

      delete process.env.AUDIT_LOGS_ENABLED;
      delete process.env.AUDIT_LOGS_BUCKET;
      delete process.env.AUDIT_LOGS_PREFIX;
    });

    test("captures chat prompt/response truncation, hashes, and counters in audit record", async () => {
      process.env.AUDIT_LOGS_ENABLED = "true";
      process.env.AUDIT_LOGS_BUCKET = "audit-bucket";

      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: mockHttpsRequest }));
      const { handler: h } = require("./proxy");

      mockS3Send.mockResolvedValueOnce({});
      const longPrompt = "p".repeat(5000);
      const longDelta = "x".repeat(17000);
      setupMockRequest(
        200,
        { "x-amzn-bedrock-agentcore-runtime-session-id": "runtime-sess-1" },
        [longDelta]
      );

      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/chat",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "tenant-A",
            app_id: "app-A",
            session_id: "sess-1"
          }
        },
        body: JSON.stringify({ prompt: longPrompt, sessionId: "sess-1" }),
        isBase64Encoded: false
      };

      await h(event, stream);

      expect(mockHttpsRequest).toHaveBeenCalledTimes(1);
      expect(mockS3Send).toHaveBeenCalledTimes(1);
      const putArgs = mockS3Send.mock.calls[0][0];
      const body = JSON.parse(String(putArgs.Body).trim());

      expect(body.request_prompt_chars).toBe(5000);
      expect(body.request_prompt_preview_truncated).toBe(true);
      expect(body.request_prompt_preview.length).toBe(4096);
      expect(body.request_prompt_sha256).toMatch(/^[a-f0-9]{64}$/);

      expect(body.runtime_session_id).toBe("runtime-sess-1");
      expect(body.response_delta_chunks).toBe(1);
      expect(body.response_bytes).toBe(17000);
      expect(body.response_preview_truncated).toBe(true);
      expect(body.response_preview.length).toBe(16384);
      expect(body.response_sha256).toMatch(/^[a-f0-9]{64}$/);
      expect(body.outcome).toBe("success");

      delete process.env.AUDIT_LOGS_ENABLED;
      delete process.env.AUDIT_LOGS_BUCKET;
    });

    test("persists audit record for AssumeRole isolation failures and returns 500 without upstream call", async () => {
      process.env.AUDIT_LOGS_ENABLED = "true";
      process.env.AUDIT_LOGS_BUCKET = "audit-bucket";
      process.env.AGENTCORE_RUNTIME_ROLE_ARN = "arn:aws:iam::123456789012:role/runtime";

      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: mockHttpsRequest }));
      jest.mock("@aws-sdk/client-sts", () => ({
        STSClient: jest.fn(() => ({ send: mockStsSend })),
        AssumeRoleCommand: jest.fn((args) => args),
      }));
      const { handler: h } = require("./proxy");

      mockStsSend.mockRejectedValueOnce(new Error("sts denied"));
      mockS3Send.mockResolvedValueOnce({});
      const consoleSpy = jest.spyOn(console, "error").mockImplementation(() => {});

      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/chat",
        requestContext: {
          http: { method: "POST" },
          authorizer: {
            tenant_id: "tenant-A",
            app_id: "app-A",
            session_id: "sess-1"
          }
        },
        body: JSON.stringify({ prompt: "hello", sessionId: "sess-1" }),
        isBase64Encoded: false
      };

      await h(event, stream);

      expect(mockHttpsRequest).not.toHaveBeenCalled();
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Error: Identity isolation failed: sts denied" })
      );
      expect(mockS3Send).toHaveBeenCalledTimes(1);
      const putArgs = mockS3Send.mock.calls[0][0];
      const body = JSON.parse(String(putArgs.Body).trim());
      expect(body.status_code).toBe(500);
      expect(body.outcome).toBe("error");
      expect(body.error_message).toBe("Identity isolation failed: sts denied");
      expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining("AssumeRole failed"));

      consoleSpy.mockRestore();
      delete process.env.AUDIT_LOGS_ENABLED;
      delete process.env.AUDIT_LOGS_BUCKET;
      delete process.env.AGENTCORE_RUNTIME_ROLE_ARN;
    });

    test("does not fail request when audit persistence to S3 errors", async () => {
      process.env.AUDIT_LOGS_ENABLED = "true";
      process.env.AUDIT_LOGS_BUCKET = "audit-bucket";

      jest.resetModules();
      setupAwsLambdaGlobal();
      jest.mock("https", () => ({ request: mockHttpsRequest }));
      const { handler: h } = require("./proxy");

      mockS3Send.mockRejectedValueOnce(new Error("s3 unavailable"));
      const consoleSpy = jest.spyOn(console, "error").mockImplementation(() => {});

      const stream = mockResponseStream();
      const event = {
        rawPath: "/api/tenancy/v1/admin/tenants/acme-finance/diagnostics",
        requestContext: {
          http: { method: "GET" },
          authorizer: {
            tenant_id: "acme-finance",
            app_id: "portal-prod"
          }
        }
      };

      await h(event, stream);

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 200,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalled();
      expect(mockS3Send).toHaveBeenCalledTimes(1);
      expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining("Audit log persist failed"));

      consoleSpy.mockRestore();
      delete process.env.AUDIT_LOGS_ENABLED;
      delete process.env.AUDIT_LOGS_BUCKET;
    });
  });

  describe("writeError helper", () => {
    test("writes structured JSON error to response stream", () => {
      const stream = mockResponseStream();
      _writeError(stream, 422, "Validation failed");

      expect(global.awslambda.HttpResponseStream.from).toHaveBeenCalledWith(stream, {
        statusCode: 422,
        headers: { "content-type": "application/json" },
      });
      expect(mockStreamEnd).toHaveBeenCalledWith(
        JSON.stringify({ error: "Validation failed" })
      );
    });
  });
});
