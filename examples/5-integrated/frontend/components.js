import React from 'https://esm.sh/react@18.3.1';
import htm from 'https://esm.sh/htm@3.1.1';

export const html = htm.bind(React.createElement);

export const COMPONENT_LIBRARY_VERSION = '0.1.0';

function cx(...parts) {
  return parts.filter(Boolean).join(' ');
}

const STATUS_STYLES = {
  connected: 'bg-emerald-500/15 text-emerald-200 ring-emerald-400/30',
  unauthorized: 'bg-amber-500/15 text-amber-100 ring-amber-300/30',
  disconnected: 'bg-rose-500/15 text-rose-100 ring-rose-300/30',
  streaming: 'bg-sky-500/15 text-sky-100 ring-sky-300/30',
  idle: 'bg-slate-500/15 text-slate-100 ring-slate-300/30',
};

const TONE_STYLES = {
  neutral: 'from-slate-200/10 to-slate-200/0 text-slate-100',
  success: 'from-emerald-300/15 to-emerald-200/0 text-emerald-100',
  warning: 'from-amber-300/15 to-amber-200/0 text-amber-100',
  danger: 'from-rose-300/15 to-rose-200/0 text-rose-100',
  info: 'from-sky-300/15 to-sky-200/0 text-sky-100',
};

export function StatusBadge({ state = 'idle', label }) {
  return html`
    <span
      className=${cx(
        'inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-semibold ring-1 backdrop-blur-sm',
        STATUS_STYLES[state] || STATUS_STYLES.idle,
      )}
    >
      <span className=${cx('h-1.5 w-1.5 rounded-full', state === 'streaming' ? 'animate-pulse bg-sky-300' : 'bg-current opacity-80')}></span>
      ${label || state.toUpperCase()}
    </span>
  `;
}

export function Panel({ title, subtitle, actions = null, className = '', bodyClassName = '', children }) {
  return html`
    <section className=${cx('glass-panel rounded-2xl border border-white/10', className)}>
      <header className="flex items-start justify-between gap-3 border-b border-white/5 px-4 py-3 sm:px-5">
        <div>
          <h2 className="text-sm font-semibold tracking-wide text-white">${title}</h2>
          ${subtitle
            ? html`<p className="mt-1 text-xs text-slate-300/80">${subtitle}</p>`
            : null}
        </div>
        ${actions ? html`<div className="flex items-center gap-2">${actions}</div>` : null}
      </header>
      <div className=${cx('px-4 py-4 sm:px-5', bodyClassName)}>${children}</div>
    </section>
  `;
}

export function AppShell({ title, subtitle, status, toolbar = null, sidebar = null, children }) {
  return html`
    <div className="dashboard-shell min-h-screen text-slate-100">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-5 px-4 py-5 sm:px-6 lg:px-8">
        <header className="glass-panel rounded-2xl border border-white/10 px-4 py-4 sm:px-5">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <p className="text-xs uppercase tracking-[0.2em] text-sky-200/70">AgentCore Dashboard Kit</p>
              <h1 className="mt-1 text-xl font-semibold text-white sm:text-2xl">${title}</h1>
              ${subtitle ? html`<p className="mt-1 text-sm text-slate-300/85">${subtitle}</p>` : null}
            </div>
            <div className="flex flex-wrap items-center gap-2">
              ${status}
              ${toolbar}
            </div>
          </div>
        </header>

        <div className="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(320px,1fr)]">
          <div className="flex min-h-0 flex-col gap-5">${children}</div>
          <aside className="flex min-h-0 flex-col gap-5">${sidebar}</aside>
        </div>
      </div>
    </div>
  `;
}

export function ActionButton({ label, onClick, disabled = false, tone = 'neutral' }) {
  const toneClass = {
    neutral: 'border-white/15 bg-white/5 text-slate-100 hover:bg-white/10',
    primary: 'border-sky-300/25 bg-sky-300/10 text-sky-100 hover:bg-sky-300/20',
    danger: 'border-rose-300/25 bg-rose-300/10 text-rose-100 hover:bg-rose-300/20',
  }[tone] || 'border-white/15 bg-white/5 text-slate-100 hover:bg-white/10';

  return html`
    <button
      type="button"
      className=${cx(
        'rounded-lg border px-3 py-1.5 text-xs font-medium transition disabled:cursor-not-allowed disabled:opacity-50',
        toneClass,
      )}
      onClick=${onClick}
      disabled=${disabled}
    >
      ${label}
    </button>
  `;
}

export function MetricGrid({ items = [] }) {
  return html`
    <div className="grid gap-3 sm:grid-cols-2">${items.map((item) => html`<${MetricCard} ...${item} />`)}</div>
  `;
}

export function MetricCard({ label, value, detail, tone = 'neutral' }) {
  return html`
    <div className=${cx('rounded-xl border border-white/10 bg-gradient-to-b p-3', TONE_STYLES[tone] || TONE_STYLES.neutral)}>
      <div className="text-xs uppercase tracking-wide text-slate-300/85">${label}</div>
      <div className="mt-2 text-xl font-semibold tracking-tight">${value}</div>
      ${detail ? html`<div className="mt-1 text-xs text-slate-300/80">${detail}</div>` : null}
    </div>
  `;
}

export function PromptComposer({ value, onChange, onSubmit, disabled = false, placeholder = 'Ask the agent...', submitLabel = 'Send' }) {
  return html`
    <form className="flex flex-col gap-3" onSubmit=${onSubmit}>
      <label className="sr-only" htmlFor="prompt">Prompt</label>
      <textarea
        id="prompt"
        rows="3"
        className="w-full resize-y rounded-xl border border-white/10 bg-slate-950/70 px-3 py-2 text-sm text-slate-100 outline-none ring-0 placeholder:text-slate-400/70 focus:border-sky-300/40"
        placeholder=${placeholder}
        value=${value}
        onInput=${(event) => onChange(event.target.value)}
        disabled=${disabled}
      />
      <div className="flex items-center justify-between gap-3">
        <p className="text-xs text-slate-300/70">Supports JSON streaming (`application/x-ndjson`) and JSON fallback responses.</p>
        <button
          type="submit"
          disabled=${disabled || !value.trim()}
          className="rounded-xl border border-sky-300/30 bg-sky-300/10 px-4 py-2 text-sm font-semibold text-sky-100 transition hover:bg-sky-300/20 disabled:cursor-not-allowed disabled:opacity-50"
        >
          ${submitLabel}
        </button>
      </div>
    </form>
  `;
}

export function AuthCard({ onLogin, message = 'Authentication required to start the session.', loginLabel = 'Sign in via OIDC' }) {
  return html`
    <div className="rounded-xl border border-amber-300/20 bg-amber-300/5 p-4 text-sm text-amber-100">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="font-semibold">Session Gate</div>
          <p className="mt-1 text-xs text-amber-100/80">${message}</p>
        </div>
        <button
          type="button"
          onClick=${onLogin}
          className="rounded-xl border border-amber-300/30 bg-amber-300/10 px-4 py-2 text-xs font-semibold uppercase tracking-wide text-amber-100 transition hover:bg-amber-300/20"
        >
          ${loginLabel}
        </button>
      </div>
    </div>
  `;
}

export function Transcript({ items = [], isStreaming = false }) {
  if (!items.length) {
    return html`<${EmptyState} title="No transcript yet" description="Send a prompt to populate the conversation transcript." />`;
  }

  return html`
    <div className="space-y-3">
      ${items.map(
        (item) => html`<${TranscriptLine} key=${item.id} item=${item} />`,
      )}
      ${isStreaming
        ? html`<div className="inline-flex items-center gap-2 rounded-lg border border-sky-300/20 bg-sky-300/5 px-3 py-2 text-xs text-sky-100">
            <span className="h-2 w-2 animate-pulse rounded-full bg-sky-300"></span>
            Streaming response...
          </div>`
        : null}
    </div>
  `;
}

export function TranscriptLine({ item }) {
  const roleTone = {
    system: 'border-slate-300/10 bg-slate-300/5 text-slate-200',
    user: 'border-sky-300/20 bg-sky-300/10 text-sky-100',
    assistant: 'border-emerald-300/20 bg-emerald-300/10 text-emerald-100',
    error: 'border-rose-300/20 bg-rose-300/10 text-rose-100',
  }[item.role] || 'border-white/10 bg-white/5 text-slate-100';

  return html`
    <article className=${cx('rounded-xl border p-3', roleTone)}>
      <div className="mb-2 flex items-center justify-between gap-2">
        <span className="text-[11px] font-semibold uppercase tracking-[0.18em] opacity-80">${item.role}</span>
        ${item.timestamp ? html`<span className="text-[11px] opacity-70">${item.timestamp}</span>` : null}
      </div>
      <pre className="whitespace-pre-wrap break-words font-mono text-xs leading-5">${item.text || ''}</pre>
    </article>
  `;
}

export function Timeline({ events = [] }) {
  if (!events.length) {
    return html`<${EmptyState} title="No activity" description="Runtime and transport events will appear here." compact=${true} />`;
  }

  return html`
    <ol className="space-y-2">
      ${events.map(
        (event) => html`
          <li key=${event.id} className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
            <div className="flex items-center justify-between gap-2 text-xs">
              <span className="font-medium text-white">${event.label}</span>
              <span className="text-slate-300/70">${event.time}</span>
            </div>
            ${event.detail ? html`<p className="mt-1 text-xs text-slate-300/80">${event.detail}</p>` : null}
          </li>
        `,
      )}
    </ol>
  `;
}

export function ToolCatalog({ tools = [], sourceLabel = 'Example schema', loading = false }) {
  if (loading) {
    return html`<p className="text-xs text-slate-300/80">Loading tool metadata...</p>`;
  }

  return html`
    <div className="space-y-3">
      <p className="text-xs text-slate-300/75">Source: ${sourceLabel}</p>
      ${tools.length
        ? html`
            <ul className="space-y-2">
              ${tools.map(
                (tool) => html`
                  <li key=${tool.id} className="rounded-lg border border-white/10 bg-white/5 px-3 py-2">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <p className="text-sm font-medium text-white">${tool.name}</p>
                        <p className="mt-1 text-xs text-slate-300/80">${tool.description || 'No description'}</p>
                      </div>
                      ${tool.method
                        ? html`<span className="rounded-md border border-sky-300/20 bg-sky-300/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-sky-100">${tool.method}</span>`
                        : null}
                    </div>
                  </li>
                `,
              )}
            </ul>
          `
        : html`<${EmptyState} title="No tools discovered" description="Add an OpenAPI spec to populate specialized tool panels." compact=${true} />`}
    </div>
  `;
}

export function JsonPreview({ data, emptyLabel = 'No payload yet' }) {
  return html`
    <div className="rounded-xl border border-white/10 bg-slate-950/70">
      <div className="border-b border-white/5 px-3 py-2 text-xs uppercase tracking-wide text-slate-300/75">Payload Preview</div>
      <pre className="max-h-64 overflow-auto p-3 text-xs leading-5 text-slate-100"><code>${data ? JSON.stringify(data, null, 2) : emptyLabel}</code></pre>
    </div>
  `;
}

export function EmptyState({ title, description, compact = false }) {
  return html`
    <div className=${cx('rounded-xl border border-dashed border-white/15 bg-white/5 text-center text-slate-300/80', compact ? 'p-3' : 'p-5')}>
      <p className="text-sm font-medium text-slate-100">${title}</p>
      <p className="mt-1 text-xs">${description}</p>
    </div>
  `;
}

export function LibraryList() {
  const components = [
    'AppShell',
    'Panel',
    'StatusBadge',
    'ActionButton',
    'MetricGrid / MetricCard',
    'PromptComposer',
    'AuthCard',
    'Transcript / TranscriptLine',
    'Timeline',
    'ToolCatalog',
    'JsonPreview',
  ];

  return html`
    <ul className="grid gap-2 text-xs sm:grid-cols-2">
      ${components.map(
        (name) => html`<li key=${name} className="rounded-lg border border-white/10 bg-white/5 px-3 py-2 font-mono text-slate-100">${name}</li>`,
      )}
    </ul>
  `;
}
