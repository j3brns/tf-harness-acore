const SignatureV4 = jest.fn().mockImplementation(() => ({
  sign: jest.fn().mockResolvedValue({
    method: "POST",
    hostname: "bedrock-agentcore.us-east-1.amazonaws.com",
    path: "/runtimes/test-arn/invocations?accountId=123456789012",
    headers: { host: "bedrock-agentcore.us-east-1.amazonaws.com" },
    body: '{"prompt":"hello"}',
  }),
}));

module.exports = { SignatureV4 };
