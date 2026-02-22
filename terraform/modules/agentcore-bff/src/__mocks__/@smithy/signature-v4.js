const SignatureV4 = jest.fn().mockImplementation(() => ({
  sign: jest.fn().mockResolvedValue({
    method: "POST",
    hostname: "bedrock-agentcore.eu-central-1.amazonaws.com",
    path: "/runtimes/test-arn/invocations?accountId=123456789012",
    headers: { host: "bedrock-agentcore.eu-central-1.amazonaws.com" },
    body: '{"prompt":"hello"}',
  }),
}));

module.exports = { SignatureV4 };
