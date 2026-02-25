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
const OPENAPI_CANDIDATE_URLS = [
  '/docs/api/tenancy-admin-v1.openapi.json',
  '/tenancy-admin-v1.openapi.json',
  '/docs/api/mcp-tools-v1.openapi.json',
  '/mcp-tools-v1.openapi.json',
];
const HTTP_METHODS = new Set(['get', 'post', 'put', 'patch', 'delete', 'options', 'head']);
const TENANCY_ADMIN_BASE = '/api/tenancy/v1/admin/tenants';

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

function parseIntegerInput(value, fallback, { min = 1, max = 999 } = {}) {
  const parsed = Number.parseInt(String(value || '').trim(), 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, parsed));
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes < 0) {
    return 'Unknown';
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }

  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }

  const rounded = value >= 100 ? value.toFixed(0) : value >= 10 ? value.toFixed(1) : value.toFixed(2);
  return `${rounded} ${units[unitIndex]}`;
}

function formatIso(isoString) {
  if (!isoString) {
    return 'Unknown';
  }
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) {
    return isoString;
  }
  return date.toLocaleString();
}

function formatTimelineDetail(message, metadata) {
  if (metadata && Object.keys(metadata).length) {
    return `${message || ''}${message ? ' • ' : ''}${JSON.stringify(metadata)}`;
  }
  return message || '';
}

function timelineEventsToItems(events = []) {
  return events.map((event) => ({
    id: event.eventId || `${event.type || event.action || 'event'}-${event.timestamp || event.occurredAt || Date.now()}`,
    label: event.type || event.action || 'EVENT',
    detail: formatTimelineDetail(event.message, event.metadata) || event.actorId || '',
    time: event.timestamp ? formatIso(event.timestamp) : event.occurredAt ? formatIso(event.occurredAt) : nowStamp(),
  }));
}

async function parseResponseError(response) {
  const text = await response.text();
  if (!text) {
    return `HTTP ${response.status}`;
  }

  try {
    const parsed = JSON.parse(text);
    return parsed.error || parsed.message || text;
  } catch {
    return text;
  }
}

function isScopeMismatchErrorMessage(message) {
  const value = String(message || '').toLowerCase();
  return [
    'tenant mismatch',
    'tenant isolation violation',
    'path tenant does not match authenticated tenant',
    'scope mismatch',
    'app scope',
    'missing tenant context',
  ].some((needle) => value.includes(needle));
}

function classifyAuthFailure(status, rawMessage, channel) {
  const message = String(rawMessage || '').trim();
  const lower = message.toLowerCase();

  if (isScopeMismatchErrorMessage(message)) {
    return {
      kind: 'scope-mismatch',
      title: 'Tenant/App Scope Mismatch',
      userMessage:
        'Your current session does not match the selected tenant or app scope. Sign in with the correct role/context, then retry.',
      panelMessage: 'Access denied: selected tenant/app scope does not match the authenticated session.',
      transcriptMessage: 'Access denied: tenant/app scope mismatch. Sign in with the correct role or tenant context, then retry.',
      eventLabel: channel === 'portal' ? 'Portal scope mismatch' : 'Chat scope mismatch',
    };
  }

  if (status === 401 || lower.includes('expired') || lower.includes('session') || lower.includes('invalid token')) {
    return {
      kind: 'session-expired',
      title: 'Session Expired',
      userMessage: 'Your sign-in session expired or is no longer valid. Sign in again, then retry the request.',
      panelMessage: 'Authentication required: your portal session expired or is invalid. Sign in again and retry.',
      transcriptMessage: 'Session expired or invalid. Sign in again, then retry your request.',
      eventLabel: channel === 'portal' ? 'Portal session expired' : 'Chat session expired',
    };
  }

  return {
    kind: 'auth-required',
    title: 'Authentication Required',
    userMessage: 'Authentication is required for this action. Sign in again and retry.',
    panelMessage: 'Authentication required for this request. Sign in again and retry.',
    transcriptMessage: 'Authentication required. Sign in again, then retry your request.',
    eventLabel: channel === 'portal' ? 'Portal auth required' : 'Chat auth required',
  };
}

function userFacingApiError(status, contextLabel) {
  return `${contextLabel} failed (HTTP ${status}). Retry the request. If it continues, check the Activity panel for timing/context.`;
}

function App() {
  const [authState, setAuthState] = useState(inferAuthState());
  const [prompt, setPrompt] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [transportStatus, setTransportStatus] = useState('idle');
  const [tenantId, setTenantId] = useState('acme-finance');
  const [auditWindowHours, setAuditWindowHours] = useState('24');
  const [timelineLimit, setTimelineLimit] = useState('10');
  const [includeActors, setIncludeActors] = useState(true);
  const [portalData, setPortalData] = useState({
    diagnostics: null,
    auditSummary: null,
    timeline: null,
  });
  const [portalLoading, setPortalLoading] = useState({
    diagnostics: false,
    auditSummary: false,
    timeline: false,
  });
  const [portalErrors, setPortalErrors] = useState({
    diagnostics: '',
    auditSummary: '',
    timeline: '',
  });
  const [portalErrorKinds, setPortalErrorKinds] = useState({
    diagnostics: '',
    auditSummary: '',
    timeline: '',
  });
  const [authNotice, setAuthNotice] = useState(null);
  const [messages, setMessages] = useState(() => [
    makeMessage('system', 'AgentCore frontend component library loaded.'),
    makeMessage('system', 'Tenancy portal diagnostics and audit timeline panels are available below.'),
  ]);
  const [events, setEvents] = useState(() => [
    { id: 'boot', label: 'UI booted', detail: `Component library v${COMPONENT_LIBRARY_VERSION}`, time: nowStamp() },
  ]);
  const [toolCatalog, setToolCatalog] = useState(sampleTools());
  const [toolSource, setToolSource] = useState('Embedded sample catalog');
  const [toolsLoading, setToolsLoading] = useState(false);
  const [lastPayload, setLastPayload] = useState(null);
  const streamedCharsRef = useRef(0);
  const lastPortalRetryRef = useRef(null);
  const lastFailedChatPromptRef = useRef('');
  const [, forceMetricsTick] = useState(0);

  function addEvent(label, detail = '') {
    setEvents((current) => [
      { id: `${Date.now()}-${Math.random().toString(16).slice(2)}`, label, detail, time: nowStamp() },
      ...current,
    ].slice(0, 20));
  }

  function refreshAuth() {
    const next = inferAuthState();
    setAuthState(next);
    if (next === 'connected') {
      setAuthNotice(null);
    }
    return next;
  }

  function normalizedTenantId() {
    return tenantId.trim();
  }

  function setPortalError(kind, category, message) {
    setPortalErrors((current) => ({ ...current, [kind]: message }));
    setPortalErrorKinds((current) => ({ ...current, [kind]: category }));
  }

  function clearPortalError(kind) {
    setPortalError(kind, '', '');
  }

  function showAuthNotice(details, retryAction, retryLabel) {
    lastPortalRetryRef.current = retryAction || null;
    setAuthNotice({
      kind: details.kind,
      title: details.title,
      message: details.userMessage,
      retryLabel: retryLabel || '',
    });
  }

  function retryLastPortalAction() {
    if (typeof lastPortalRetryRef.current === 'function') {
      lastPortalRetryRef.current();
    }
  }

  async function fetchTenantAdminResource(kind, url, successLabel) {
    setPortalLoading((current) => ({ ...current, [kind]: true }));
    clearPortalError(kind);
    addEvent('Portal request', `${successLabel}: ${url}`);

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        cache: 'no-store',
      });

      if (response.status === 401 || response.status === 403) {
        const rawErrorMessage = await parseResponseError(response);
        const classified = classifyAuthFailure(response.status, rawErrorMessage, 'portal');
        setAuthState('unauthorized');
        setTransportStatus('unauthorized');
        setPortalError(kind, 'auth', classified.panelMessage);
        showAuthNotice(classified, () => fetchTenantAdminResource(kind, url, successLabel), `Retry ${successLabel}`);
        setLastPayload({
          kind: 'portal-auth-error',
          resource: kind,
          status: response.status,
          category: classified.kind,
        });
        addEvent(classified.eventLabel, `${successLabel}: HTTP ${response.status}`);
        return null;
      }

      if (!response.ok) {
        await parseResponseError(response);
        setPortalError(kind, 'api', userFacingApiError(response.status, `${successLabel} request`));
        addEvent('Portal request failed', `${successLabel}: HTTP ${response.status}`);
        setTransportStatus('disconnected');
        setLastPayload({
          kind: 'portal-api-error',
          resource: kind,
          status: response.status,
        });
        return null;
      }

      const data = await response.json();
      setPortalData((current) => ({ ...current, [kind]: data }));
      setLastPayload({ kind, url, response: data });
      setAuthState('connected');
      setAuthNotice(null);
      setTransportStatus((current) => (current === 'idle' ? 'connected' : current));
      addEvent('Portal response', `${successLabel} loaded`);
      return data;
    } catch (error) {
      setPortalError(kind, 'api', `${successLabel} request failed before a response was received. Retry the request.`);
      addEvent('Portal transport error', `${successLabel}: ${error.message}`);
      setTransportStatus('disconnected');
      setLastPayload({
        kind: 'portal-transport-error',
        resource: kind,
        message: 'Network or transport failure while loading tenant portal data',
      });
      return null;
    } finally {
      setPortalLoading((current) => ({ ...current, [kind]: false }));
    }
  }

  async function loadTenantDiagnostics() {
    const slug = normalizedTenantId();
    if (!slug) {
      setPortalError('diagnostics', 'validation', 'Tenant ID is required');
      return null;
    }

    return fetchTenantAdminResource(
      'diagnostics',
      `${TENANCY_ADMIN_BASE}/${encodeURIComponent(slug)}/diagnostics`,
      `Diagnostics ${slug}`,
    );
  }

  async function loadTenantAuditSummary() {
    const slug = normalizedTenantId();
    if (!slug) {
      setPortalError('auditSummary', 'validation', 'Tenant ID is required');
      return null;
    }

    const windowHours = parseIntegerInput(auditWindowHours, 24, { min: 1, max: 168 });
    const params = new URLSearchParams({
      windowHours: String(windowHours),
      includeActors: includeActors ? 'true' : 'false',
    });

    return fetchTenantAdminResource(
      'auditSummary',
      `${TENANCY_ADMIN_BASE}/${encodeURIComponent(slug)}/audit-summary?${params.toString()}`,
      `Audit summary ${slug}`,
    );
  }

  async function loadTenantTimeline() {
    const slug = normalizedTenantId();
    if (!slug) {
      setPortalError('timeline', 'validation', 'Tenant ID is required');
      return null;
    }

    const limit = parseIntegerInput(timelineLimit, 10, { min: 1, max: 100 });
    const params = new URLSearchParams({ limit: String(limit) });

    return fetchTenantAdminResource(
      'timeline',
      `${TENANCY_ADMIN_BASE}/${encodeURIComponent(slug)}/timeline?${params.toString()}`,
      `Timeline ${slug}`,
    );
  }

  async function refreshTenantPortal() {
    const slug = normalizedTenantId();
    if (!slug) {
      setPortalErrors({
        diagnostics: 'Tenant ID is required',
        auditSummary: 'Tenant ID is required',
        timeline: 'Tenant ID is required',
      });
      setPortalErrorKinds({
        diagnostics: 'validation',
        auditSummary: 'validation',
        timeline: 'validation',
      });
      addEvent('Portal validation', 'Tenant ID is required before loading portal data');
      return;
    }

    addEvent('Portal refresh', `Loading diagnostics, audit summary, and timeline for ${slug}`);
    await Promise.allSettled([loadTenantDiagnostics(), loadTenantAuditSummary(), loadTenantTimeline()]);
  }

  async function loadToolCatalog() {
    setToolsLoading(true);
    addEvent('Catalog lookup', 'Checking for generated Tenancy/MCP OpenAPI specs');

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
    lastFailedChatPromptRef.current = text;
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
        const rawErrorMessage = await parseResponseError(response);
        const classified = classifyAuthFailure(response.status, rawErrorMessage, 'chat');
        setMessages((current) => [...current, makeMessage('error', classified.transcriptMessage)]);
        setAuthState('unauthorized');
        setAuthNotice({
          kind: classified.kind,
          title: classified.title,
          message: `${classified.userMessage} Your prompt has been restored for retry.`,
          retryLabel: 'Restore Prompt',
        });
        addEvent(classified.eventLabel, `HTTP ${response.status}`);
        setTransportStatus('unauthorized');
        setPrompt(text);
        setLastPayload({
          kind: 'chat-auth-error',
          status: response.status,
          category: classified.kind,
        });
        return;
      }

      if (!response.ok) {
        await parseResponseError(response);
        setMessages((current) => [
          ...current,
          makeMessage('error', userFacingApiError(response.status, 'Chat request')),
        ]);
        addEvent('Request failed', `HTTP ${response.status}`);
        setTransportStatus('disconnected');
        setLastPayload({
          kind: 'chat-api-error',
          status: response.status,
        });
        return;
      }

      setAuthState('connected');
      setAuthNotice(null);
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
  const portalErrorCount = Object.values(portalErrors).filter(Boolean).length;
  const diagnostics = portalData.diagnostics;
  const auditSummary = portalData.auditSummary;
  const tenantTimeline = portalData.timeline;
  const portalBusy = Object.values(portalLoading).some(Boolean);

  const metrics = [
    {
      label: 'Session State',
      value: authState === 'connected' ? 'Authorized' : 'Sign-In Needed',
      detail: authState === 'connected' ? 'API access confirmed in browser session' : 'Use OIDC login to create session',
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
      label: 'API Catalog Entries',
      value: String(toolCatalog.length),
      detail: toolSource,
      tone: toolCatalog.length ? 'success' : 'neutral',
    },
    {
      label: 'Tenant Health',
      value: diagnostics?.health || 'Not Loaded',
      detail: diagnostics?.generatedAt ? `Generated ${formatIso(diagnostics.generatedAt)}` : 'Load tenant diagnostics',
      tone: diagnostics?.health === 'HEALTHY' ? 'success' : diagnostics ? 'warning' : 'neutral',
    },
    {
      label: 'Timeline Events',
      value: String(tenantTimeline?.events?.length || 0),
      detail: portalBusy ? 'Refreshing tenant portal data' : `${portalErrorCount} portal error(s)`,
      tone: portalErrorCount ? 'warning' : tenantTimeline?.events?.length ? 'info' : 'neutral',
    },
  ];

  function clearTranscript() {
    setMessages([
      makeMessage('system', 'Transcript cleared.'),
      makeMessage('system', 'Portal diagnostics and timeline data remain available until refreshed.'),
    ]);
    addEvent('Transcript cleared', 'Chat messages removed from local state');
  }

  function handleLogin() {
    addEvent('Redirecting', 'Navigating to /auth/login');
    window.location.href = AUTH_URL;
  }

  function handleRetryAuthNotice() {
    if (!authNotice?.retryLabel) {
      return;
    }
    if (authNotice.retryLabel === 'Restore Prompt') {
      if (lastFailedChatPromptRef.current) {
        setPrompt(lastFailedChatPromptRef.current);
      }
      addEvent('Prompt restored', 'Restored last prompt after authentication failure');
      return;
    }
    retryLastPortalAction();
  }

  function renderPortalError(kind) {
    const message = portalErrors[kind];
    if (!message) {
      return null;
    }
    const toneClass =
      portalErrorKinds[kind] === 'auth'
        ? 'border-amber-300/20 bg-amber-300/5 text-amber-100'
        : 'border-rose-300/20 bg-rose-300/5 text-rose-100';
    return html`<div className=${`rounded-xl border px-3 py-2 text-xs ${toneClass}`}>${message}</div>`;
  }

  const diagnosticsMetrics = diagnostics
    ? [
        {
          label: 'Health',
          value: diagnostics.health || 'UNKNOWN',
          detail: diagnostics.generatedAt ? `Generated ${formatIso(diagnostics.generatedAt)}` : 'No generation timestamp',
          tone: diagnostics.health === 'HEALTHY' ? 'success' : 'warning',
        },
        {
          label: 'Policy Version',
          value: diagnostics.policyVersion || 'Unknown',
          detail: diagnostics.appId ? `App ${diagnostics.appId}` : 'App scope unavailable',
          tone: 'info',
        },
        {
          label: 'Deployment SHA',
          value: diagnostics.lastDeploymentSha ? String(diagnostics.lastDeploymentSha).slice(0, 12) : 'Unknown',
          detail: diagnostics.lastDeploymentSha || 'No deployment SHA reported',
          tone: 'neutral',
        },
        {
          label: 'Memory Usage',
          value: formatBytes(diagnostics.memoryUsage?.usedBytes),
          detail: diagnostics.memoryUsage?.summary || 'No memory usage summary',
          tone: 'neutral',
        },
      ]
    : [];

  const auditMetrics = auditSummary
    ? [
        {
          label: 'Total Events',
          value: String(auditSummary.summary?.totalEvents ?? 0),
          detail: auditSummary.window ? `${auditSummary.window.hours}h window` : 'No window metadata',
          tone: 'info',
        },
        {
          label: 'Success / Failure',
          value: `${auditSummary.summary?.successCount ?? 0} / ${auditSummary.summary?.failureCount ?? 0}`,
          detail: auditSummary.generatedAt ? `Generated ${formatIso(auditSummary.generatedAt)}` : 'No generation timestamp',
          tone: (auditSummary.summary?.failureCount ?? 0) > 0 ? 'warning' : 'success',
        },
        {
          label: 'Credential Rotations',
          value: String(auditSummary.summary?.credentialRotations ?? 0),
          detail: 'Within selected window',
          tone: 'neutral',
        },
        {
          label: 'Suspensions',
          value: String(auditSummary.summary?.suspensions ?? 0),
          detail: 'Within selected window',
          tone: (auditSummary.summary?.suspensions ?? 0) > 0 ? 'warning' : 'neutral',
        },
      ]
    : [];

  const timelineItems = timelineEventsToItems(tenantTimeline?.events || []);
  const auditRecentItems = timelineEventsToItems(
    (auditSummary?.lastEvents || []).map((item) => ({
      eventId: item.eventId,
      occurredAt: item.occurredAt,
      action: `${item.action || 'AUDIT'}:${item.result || 'UNKNOWN'}`,
      message: item.actorId ? `${item.actorType || 'ACTOR'} ${item.actorId}` : item.action,
    })),
  );

  const toolbar = html`
    <div className="flex flex-wrap items-center gap-2">
      <${StatusBadge} state=${statusState} label=${statusLabel} />
      <${ActionButton} label="Refresh Auth" onClick=${refreshAuth} />
      <${ActionButton} label="Reload API Catalog" onClick=${loadToolCatalog} disabled=${toolsLoading} />
      <${ActionButton} label="Refresh Tenant" onClick=${refreshTenantPortal} disabled=${portalBusy} tone="primary" />
      <${ActionButton} label="Clear Chat" onClick=${clearTranscript} tone="danger" />
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

    <${Panel} title="API Catalog" subtitle="Auto-loads tenancy admin OpenAPI (or MCP fallback) when available.">
      <${ToolCatalog} tools=${toolCatalog} sourceLabel=${toolSource} loading=${toolsLoading} />
    </${Panel}>

    <${Panel} title="Activity" subtitle="Transport and UI events for debugging.">
      <${Timeline} events=${events} />
    </${Panel}>

    <${Panel} title="Last Payload" subtitle="Preview the last request or protocol packet.">
      <${JsonPreview} data=${lastPayload} emptyLabel="No requests sent yet." />
    </${Panel}>
  `;

  const authNoticeBanner = authNotice
    ? html`
        <div className=${`rounded-xl border px-4 py-3 ${
          authNotice.kind === 'scope-mismatch'
            ? 'border-rose-300/20 bg-rose-300/5 text-rose-100'
            : 'border-amber-300/20 bg-amber-300/5 text-amber-100'
        }`}>
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <div className="text-sm font-semibold">${authNotice.title}</div>
              <p className="mt-1 text-xs opacity-90">${authNotice.message}</p>
            </div>
            <div className="flex flex-wrap items-center gap-2">
              <${ActionButton} label="Sign in again" onClick=${handleLogin} tone="primary" />
              ${authNotice.retryLabel
                ? html`<${ActionButton} label=${authNotice.retryLabel} onClick=${handleRetryAuthNotice} />`
                : null}
            </div>
          </div>
        </div>
      `
    : null;

  return html`
    <${AppShell}
      title="AgentCore Tenant Operations Portal"
      subtitle="Static-hosted tenancy diagnostics and audit timeline UI built on the reusable React/Tailwind component library."
      status=${html``}
      toolbar=${toolbar}
      sidebar=${sidebar}
    >
      <${Panel}
        title="Session Overview"
        subtitle="Composable cards for auth, streaming, and tenancy operational state."
      >
        <div className="space-y-4">
          <${MetricGrid} items=${metrics} />
          ${authNoticeBanner}
          ${authState !== 'connected' ? html`<${AuthCard} onLogin=${handleLogin} message="Authentication required to load tenant diagnostics and audit timeline data." />` : null}
          <div className="rounded-xl border border-white/10 bg-white/5 p-4">
            <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm font-semibold text-white">Tenant Diagnostics Controls</p>
                <p className="mt-1 text-xs text-slate-300/80">Consume C3 tenancy admin endpoints for diagnostics, bounded audit summary, and timeline views.</p>
              </div>
              ${portalBusy ? html`<${StatusBadge} state="streaming" label="LOADING" />` : html`<${StatusBadge} state="idle" label="READY" />`}
            </div>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <label className="text-xs text-slate-200">
                <span className="mb-1 block uppercase tracking-wide text-slate-300/75">Tenant ID</span>
                <input
                  type="text"
                  value=${tenantId}
                  onInput=${(event) => setTenantId(event.target.value)}
                  placeholder="acme-finance"
                  className="w-full rounded-lg border border-white/10 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none placeholder:text-slate-400/70 focus:border-sky-300/40"
                />
              </label>
              <label className="text-xs text-slate-200">
                <span className="mb-1 block uppercase tracking-wide text-slate-300/75">Audit Window (hours)</span>
                <input
                  type="number"
                  min="1"
                  max="168"
                  value=${auditWindowHours}
                  onInput=${(event) => setAuditWindowHours(event.target.value)}
                  className="w-full rounded-lg border border-white/10 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none focus:border-sky-300/40"
                />
              </label>
              <label className="text-xs text-slate-200">
                <span className="mb-1 block uppercase tracking-wide text-slate-300/75">Timeline Limit</span>
                <input
                  type="number"
                  min="1"
                  max="100"
                  value=${timelineLimit}
                  onInput=${(event) => setTimelineLimit(event.target.value)}
                  className="w-full rounded-lg border border-white/10 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none focus:border-sky-300/40"
                />
              </label>
              <label className="flex items-center gap-2 rounded-lg border border-white/10 bg-slate-950/60 px-3 py-2 text-xs text-slate-200">
                <input
                  type="checkbox"
                  checked=${includeActors}
                  onChange=${(event) => setIncludeActors(event.target.checked)}
                  className="h-4 w-4 rounded border-white/20 bg-slate-900 text-sky-300"
                />
                Include actor breakdown
              </label>
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <${ActionButton} label="Load All" onClick=${refreshTenantPortal} disabled=${portalBusy} tone="primary" />
              <${ActionButton} label="Diagnostics" onClick=${loadTenantDiagnostics} disabled=${portalLoading.diagnostics} />
              <${ActionButton} label="Audit Summary" onClick=${loadTenantAuditSummary} disabled=${portalLoading.auditSummary} />
              <${ActionButton} label="Timeline" onClick=${loadTenantTimeline} disabled=${portalLoading.timeline} />
            </div>
            <div className="mt-3 text-xs text-slate-300/75">
              Endpoints: <span className="font-mono">/diagnostics</span>, <span className="font-mono">/audit-summary</span>, <span className="font-mono">/timeline</span>
            </div>
          </div>
        </div>
      </${Panel}>

      <${Panel}
        title="Tenant Diagnostics"
        subtitle="Health, deployment SHA, policy version, and memory usage summary from the tenancy admin API."
        bodyClassName="space-y-4"
      >
        ${renderPortalError('diagnostics')}
        ${diagnostics
          ? html`
              <${MetricGrid} items=${diagnosticsMetrics} />
              <${JsonPreview} data=${diagnostics} emptyLabel="No diagnostics response loaded." />
            `
          : html`<p className="text-xs text-slate-300/80">Load a tenant to populate diagnostics.</p>`}
      </${Panel}>

      <${Panel}
        title="Tenant Audit Summary"
        subtitle="Bounded audit counts and actor breakdown for the selected tenant."
        bodyClassName="space-y-4"
      >
        ${renderPortalError('auditSummary')}
        ${auditSummary
          ? html`
              <${MetricGrid} items=${auditMetrics} />
              <div className="grid gap-4 lg:grid-cols-2">
                <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                  <div className="text-xs uppercase tracking-wide text-slate-300/75">Window</div>
                  <div className="mt-2 space-y-1 text-xs text-slate-200">
                    <div><span className="text-slate-400">From:</span> ${formatIso(auditSummary.window?.from)}</div>
                    <div><span className="text-slate-400">To:</span> ${formatIso(auditSummary.window?.to)}</div>
                    <div><span className="text-slate-400">Generated:</span> ${formatIso(auditSummary.generatedAt)}</div>
                  </div>
                </div>
                <div className="rounded-xl border border-white/10 bg-white/5 p-3">
                  <div className="text-xs uppercase tracking-wide text-slate-300/75">Actor Breakdown</div>
                  ${(auditSummary.actorBreakdown || []).length
                    ? html`
                        <ul className="mt-2 space-y-2 text-xs">
                          ${(auditSummary.actorBreakdown || []).map(
                            (actor) => html`
                              <li key=${actor.actorId} className="rounded-lg border border-white/10 bg-slate-950/50 px-3 py-2">
                                <div className="flex items-center justify-between gap-2">
                                  <span className="font-mono text-slate-100">${actor.actorId}</span>
                                  <span className="text-slate-300">${actor.count}</span>
                                </div>
                                <div className="mt-1 text-[11px] uppercase tracking-wide text-slate-400">${actor.actorType}</div>
                              </li>
                            `,
                          )}
                        </ul>
                      `
                    : html`<p className="mt-2 text-xs text-slate-300/80">No actor breakdown returned (toggle \"Include actor breakdown\").</p>`}
                </div>
              </div>
              <div>
                <div className="mb-2 text-xs uppercase tracking-wide text-slate-300/75">Recent Audit Events</div>
                <${Timeline} events=${auditRecentItems} />
              </div>
            `
          : html`<p className="text-xs text-slate-300/80">Load the audit summary to view counts and actor breakdown.</p>`}
      </${Panel}>

      <${Panel}
        title="Tenant Audit Timeline"
        subtitle="Timeline endpoint view consumable by portal operators and API clients."
        bodyClassName="space-y-4"
      >
        ${renderPortalError('timeline')}
        ${tenantTimeline
          ? html`
              <${Timeline} events=${timelineItems} />
              <${JsonPreview} data=${tenantTimeline} emptyLabel="No timeline response loaded." />
            `
          : html`<p className="text-xs text-slate-300/80">Load the tenant timeline to inspect recent tenant events.</p>`}
      </${Panel}>

      <${Panel}
        title="Conversation"
        subtitle="Optional chat panel retained for streaming/BFF validation while using the portal UI."
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
