const SignatureV4 = jest.fn().mockImplementation(() => ({
  sign: jest.fn().mockResolvedValue({
    method: "POST",
    hostname: "bedrock-agentcore.eu-west-2.amazonaws.com",
    path: "/runtimes/test-arn/invocations?accountId=123456789012",
    headers: { host: "bedrock-agentcore.eu-west-2.amazonaws.com" },
    body: '{"prompt":"hello"}',
  }),
}));

module.exports = { SignatureV4 };
