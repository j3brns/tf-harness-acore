import React, { useEffect, useRef, useState } from 'https://esm.sh/react@18.3.1';
import { createRoot } from 'https://esm.sh/react-dom@18.3.1/client';
import htm from 'https://esm.sh/htm@3.1.1';
import {
  ActionButton,
  AppShell,
  AuthCard,
  COMPONENT_LIBRARY_VERSION,
  JsonPreview,
  LibraryList,
  MetricGrid,
  Panel,
  PromptComposer,
  StatusBadge,
  Timeline,
  ToolCatalog,
  Transcript,
} from './components.js';

const html = htm.bind(React.createElement);

const API_URL = '/api/chat';
const AUTH_URL = '/auth/login';
const OPENAPI_CANDIDATE_URLS = ['/docs/api/mcp-tools-v1.openapi.json', '/mcp-tools-v1.openapi.json'];
const HTTP_METHODS = new Set(['get', 'post', 'put', 'patch', 'delete', 'options', 'head']);

function nowStamp() {
  return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

function makeMessage(role, text) {
  return {
    id: `${role}-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    role,
    text,
    timestamp: nowStamp(),
  };
}

function normalizeStreamLine(line) {
  const trimmed = line.trim();
  if (!trimmed) {
    return null;
  }

  try {
    return JSON.parse(trimmed);
  } catch {
    return { type: 'delta', delta: line };
  }
}

function extractToolsFromOpenApi(spec) {
  if (!spec || !spec.paths || typeof spec.paths !== 'object') {
    return [];
  }

  const tools = [];
  for (const [path, methods] of Object.entries(spec.paths)) {
    if (!methods || typeof methods !== 'object') {
      continue;
    }

    for (const [method, operation] of Object.entries(methods)) {
      if (!HTTP_METHODS.has(method)) {
        continue;
      }

      if (!operation || typeof operation !== 'object') {
        continue;
      }

      tools.push({
        id: `${method}:${path}`,
        method: method.toUpperCase(),
        name: operation.operationId || path,
        description: operation.summary || operation.description || '',
      });
    }
  }

  return tools.slice(0, 12);
}

function sampleTools() {
  return [
    {
      id: 'tool:s3.list_objects',
      method: 'MCP',
      name: 's3.list_objects',
      description: 'List objects in a tenant-scoped S3 prefix for dashboard exploration.',
    },
    {
      id: 'tool:analytics.run_query',
      method: 'MCP',
      name: 'analytics.run_query',
      description: 'Execute a scoped analytics query and stream results back to the panel.',
    },
    {
      id: 'tool:research.fetch_sources',
      method: 'MCP',
      name: 'research.fetch_sources',
      description: 'Resolve and summarize source documents for deep-research workflows.',
    },
  ];
}

function inferAuthState() {
  return document.cookie.includes('session_id') ? 'connected' : 'unauthorized';
}

function App() {
  const [authState, setAuthState] = useState(inferAuthState());
  const [prompt, setPrompt] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [transportStatus, setTransportStatus] = useState('idle');
  const [messages, setMessages] = useState(() => [
    makeMessage('system', 'AgentCore frontend component library loaded.'),
    makeMessage('system', 'Use these React/Tailwind panels to compose specialized dashboards.'),
  ]);
  const [events, setEvents] = useState(() => [
    { id: 'boot', label: 'UI booted', detail: `Component library v${COMPONENT_LIBRARY_VERSION}`, time: nowStamp() },
  ]);
  const [toolCatalog, setToolCatalog] = useState(sampleTools());
  const [toolSource, setToolSource] = useState('Embedded sample catalog');
  const [toolsLoading, setToolsLoading] = useState(false);
  const [lastPayload, setLastPayload] = useState(null);
  const streamedCharsRef = useRef(0);
  const [, forceMetricsTick] = useState(0);

  function addEvent(label, detail = '') {
    setEvents((current) => [
      { id: `${Date.now()}-${Math.random().toString(16).slice(2)}`, label, detail, time: nowStamp() },
      ...current,
    ].slice(0, 14));
  }

  function refreshAuth() {
    const next = inferAuthState();
    setAuthState(next);
    return next;
  }

  async function loadToolCatalog() {
    setToolsLoading(true);
    addEvent('Catalog lookup', 'Checking for generated MCP OpenAPI spec');

    for (const candidate of OPENAPI_CANDIDATE_URLS) {
      try {
        const response = await fetch(candidate, { cache: 'no-store' });
        if (!response.ok) {
          continue;
        }
        const spec = await response.json();
        const tools = extractToolsFromOpenApi(spec);
        if (tools.length) {
          setToolCatalog(tools);
          setToolSource(candidate);
          addEvent('Catalog loaded', `Loaded ${tools.length} operations from ${candidate}`);
          setToolsLoading(false);
          return;
        }
      } catch (error) {
        addEvent('Catalog error', error.message);
      }
    }

    setToolCatalog(sampleTools());
    setToolSource('Embedded sample catalog');
    addEvent('Catalog fallback', 'Using embedded sample tool catalog');
    setToolsLoading(false);
  }

  useEffect(() => {
    refreshAuth();
    loadToolCatalog();
  }, []);

  useEffect(() => {
    const interval = window.setInterval(() => {
      forceMetricsTick((x) => x + 1);
    }, 1000);
    return () => window.clearInterval(interval);
  }, []);

  async function handleSubmit(event) {
    event.preventDefault();
    const text = prompt.trim();
    if (!text || isStreaming) {
      return;
    }

    setPrompt('');
    setMessages((current) => [...current, makeMessage('user', text)]);
    setLastPayload({ prompt: text });
    addEvent('Request queued', 'Sending prompt to /api/chat');

    setTransportStatus('streaming');
    setIsStreaming(true);

    let assistantId = null;
    let assistantText = '';

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ prompt: text }),
      });

      if (response.status === 401 || response.status === 403) {
        setMessages((current) => [...current, makeMessage('error', 'SESSION_EXPIRED')]);
        setAuthState('unauthorized');
        addEvent('Auth required', `HTTP ${response.status}`);
        setTransportStatus('unauthorized');
        return;
      }

      if (!response.ok) {
        const errorText = await response.text();
        setMessages((current) => [...current, makeMessage('error', errorText || `HTTP ${response.status}`)]);
        addEvent('Request failed', `HTTP ${response.status}`);
        setTransportStatus('disconnected');
        return;
      }

      setAuthState('connected');
      addEvent('Request accepted', response.body ? 'Streaming response available' : 'JSON response fallback');

      assistantId = `assistant-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      setMessages((current) => [
        ...current,
        { id: assistantId, role: 'assistant', text: '', timestamp: nowStamp() },
      ]);

      if (!response.body || !response.body.getReader) {
        const data = await response.json();
        const fallbackText = data.response || JSON.stringify(data);
        assistantText = fallbackText;
        streamedCharsRef.current += fallbackText.length;
        setLastPayload(data);
        setMessages((current) => current.map((msg) => (msg.id === assistantId ? { ...msg, text: fallbackText } : msg)));
        addEvent('JSON response', `Received ${fallbackText.length} characters`);
        setTransportStatus('connected');
        return;
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { value, done } = await reader.read();
        if (done) {
          break;
        }

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          const packet = normalizeStreamLine(line);
          if (!packet) {
            continue;
          }

          if (packet.error) {
            setMessages((current) => [...current, makeMessage('error', String(packet.error))]);
            addEvent('Stream error', String(packet.error));
            continue;
          }

          if (packet.type === 'delta' && typeof packet.delta === 'string') {
            assistantText += packet.delta;
            streamedCharsRef.current += packet.delta.length;
            setMessages((current) => current.map((msg) => (msg.id === assistantId ? { ...msg, text: assistantText } : msg)));
            continue;
          }

          if (packet.type === 'done') {
            setLastPayload(packet);
            addEvent('Stream done', 'Received completion marker');
          }
        }
      }

      if (buffer.trim()) {
        const packet = normalizeStreamLine(buffer);
        if (packet && packet.type === 'delta' && typeof packet.delta === 'string') {
          assistantText += packet.delta;
          streamedCharsRef.current += packet.delta.length;
          setMessages((current) => current.map((msg) => (msg.id === assistantId ? { ...msg, text: assistantText } : msg)));
        }
      }

      addEvent('Stream complete', `Received ${assistantText.length} characters`);
      setTransportStatus('connected');
    } catch (error) {
      setMessages((current) => [...current, makeMessage('error', error.message)]);
      addEvent('Transport error', error.message);
      setTransportStatus('disconnected');
    } finally {
      setIsStreaming(false);
      setTransportStatus((current) => (current === 'streaming' ? 'connected' : current));
      refreshAuth();
    }
  }

  const statusState = isStreaming ? 'streaming' : transportStatus === 'idle' ? authState : transportStatus;
  const statusLabel = isStreaming
    ? 'STREAMING'
    : statusState === 'connected'
      ? 'CONNECTED'
      : statusState === 'unauthorized'
        ? 'AUTH REQUIRED'
        : statusState === 'disconnected'
          ? 'DISCONNECTED'
          : 'READY';

  const assistantMessages = messages.filter((msg) => msg.role === 'assistant').length;
  const errors = messages.filter((msg) => msg.role === 'error').length;
  const metrics = [
    {
      label: 'Session State',
      value: authState === 'connected' ? 'Authorized' : 'Sign-In Needed',
      detail: authState === 'connected' ? 'Cookie detected in browser context' : 'Use OIDC login to create session',
      tone: authState === 'connected' ? 'success' : 'warning',
    },
    {
      label: 'Assistant Responses',
      value: String(assistantMessages),
      detail: `${errors} error event(s)`,
      tone: errors ? 'warning' : 'info',
    },
    {
      label: 'Streamed Characters',
      value: String(streamedCharsRef.current),
      detail: isStreaming ? 'Active stream' : 'Accumulated this page session',
      tone: isStreaming ? 'info' : 'neutral',
    },
    {
      label: 'Tool Catalog Entries',
      value: String(toolCatalog.length),
      detail: toolSource,
      tone: toolCatalog.length ? 'success' : 'neutral',
    },
  ];

  function clearTranscript() {
    setMessages([
      makeMessage('system', 'Transcript cleared.'),
      makeMessage('system', 'Compose a new dashboard interaction. Components remain reusable.'),
    ]);
    addEvent('Transcript cleared', 'Chat messages removed from local state');
  }

  function handleLogin() {
    addEvent('Redirecting', 'Navigating to /auth/login');
    window.location.href = AUTH_URL;
  }

  const toolbar = html`
    <div className="flex flex-wrap items-center gap-2">
      <${StatusBadge} state=${statusState} label=${statusLabel} />
      <${ActionButton} label="Refresh Auth" onClick=${refreshAuth} />
      <${ActionButton} label="Reload Tools" onClick=${loadToolCatalog} disabled=${toolsLoading} />
      <${ActionButton} label="Clear" onClick=${clearTranscript} tone="danger" />
    </div>
  `;

  const sidebar = html`
    <${Panel} title="Component Library" subtitle="Reusable React + Tailwind building blocks for specialized agent dashboards.">
      <div className="space-y-3">
        <div className="rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-xs text-slate-200">
          Version <span className="font-mono text-white">v${COMPONENT_LIBRARY_VERSION}</span>
        </div>
        <${LibraryList} />
      </div>
    </${Panel}>

    <${Panel} title="Tool Catalog" subtitle="Auto-loads MCP OpenAPI output when available.">
      <${ToolCatalog} tools=${toolCatalog} sourceLabel=${toolSource} loading=${toolsLoading} />
    </${Panel}>

    <${Panel} title="Activity" subtitle="Transport and UI events for debugging.">
      <${Timeline} events=${events} />
    </${Panel}>

    <${Panel} title="Last Payload" subtitle="Preview the last request or protocol packet.">
      <${JsonPreview} data=${lastPayload} emptyLabel="No requests sent yet." />
    </${Panel}>
  `;

  return html`
    <${AppShell}
      title="AgentCore Operator Console"
      subtitle="Static-hosted dashboard shell using reusable React/Tailwind components (no bundler required)."
      status=${html``}
      toolbar=${toolbar}
      sidebar=${sidebar}
    >
      <${Panel}
        title="Session Overview"
        subtitle="Composable cards for auth, metrics, and runtime state."
      >
        <div className="space-y-4">
          <${MetricGrid} items=${metrics} />
          ${authState !== 'connected' ? html`<${AuthCard} onLogin=${handleLogin} />` : null}
        </div>
      </${Panel}>

      <${Panel}
        title="Conversation"
        subtitle="Drop this transcript panel into any specialist dashboard."
        className="min-h-[22rem]"
        bodyClassName="space-y-4"
      >
        <div className="max-h-[26rem] overflow-auto pr-1">
          <${Transcript} items=${messages} isStreaming=${isStreaming} />
        </div>
        <${PromptComposer}
          value=${prompt}
          onChange=${setPrompt}
          onSubmit=${handleSubmit}
          disabled=${isStreaming}
          placeholder="Ask for research, analytics, or tool execution..."
          submitLabel=${isStreaming ? 'Streaming...' : 'Send'}
        />
      </${Panel}>
    </${AppShell}>
  `;
}

const root = createRoot(document.getElementById('app'));
root.render(html`<${App} />`);
