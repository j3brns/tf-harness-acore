import React from 'https://esm.sh/react@18.3.1';
import { createRoot } from 'https://esm.sh/react-dom@18.3.1/client';
import htm from 'https://esm.sh/htm@3.1.1';
import {
  ActionButton,
  AppShell,
  AuthCard,
  EmptyState,
  JsonPreview,
  LibraryList,
  MetricCard,
  MetricGrid,
  Panel,
  PromptComposer,
  StatusBadge,
  Timeline,
  ToolCatalog,
  Transcript,
} from '../../../examples/5-integrated/frontend/components.js';

const html = htm.bind(React.createElement);

function Preview() {
  const [prompt, setPrompt] = React.useState('');

  const metrics = [
    { label: 'Latency', value: '124ms', detail: 'P95 threshold', tone: 'success' },
    { label: 'Errors', value: '3', detail: 'Last 24h', tone: 'danger' },
    { label: 'Active Sessions', value: '1,284', detail: '+12% vs yesterday', tone: 'info' },
    { label: 'Compliance', value: '98.2%', detail: 'Cedar evaluation score', tone: 'neutral' },
  ];

  const messages = [
    { id: '1', role: 'system', text: 'System initialized.', timestamp: '10:00:00' },
    { id: '2', role: 'user', text: 'Analyze the Titanic dataset.', timestamp: '10:01:00' },
    { id: '3', role: 'assistant', text: 'I found 2,224 passengers in the record set.', timestamp: '10:01:05' },
    { id: '4', role: 'error', text: 'Access denied to restricted columns.', timestamp: '10:01:10' },
  ];

  const events = [
    { id: 'e1', label: 'Gateway Connected', detail: 'SigV4 handshake complete', time: '10:00:00' },
    { id: 'e2', label: 'Model Load', detail: 'Claude-3.5-Sonnet ready', time: '10:00:05' },
    { id: 'e3', label: 'Policy Check', detail: 'ABAC verified for Tenant-X', time: '10:01:00' },
  ];

  const tools = [
    { id: 't1', name: 's3_explorer', description: 'Lists objects in S3 buckets.', method: 'MCP' },
    { id: 't2', name: 'sql_runner', description: 'Executes Athena queries.', method: 'MCP' },
  ];

  const sidebar = html`
    <div className="flex flex-col gap-5">
      <${Panel} title="Metric Cards" subtitle="Standalone data points.">
        <div className="flex flex-col gap-3">
          <${MetricCard} label="Status" value="Healthy" tone="success" />
          <${MetricCard} label="Alerts" value="Critical" tone="danger" />
          <${MetricCard} label="System" value="Active" tone="info" />
          <${MetricCard} label="Neutral" value="Balanced" tone="neutral" />
        </div>
      </${Panel}>

      <${Panel} title="Status Badges" subtitle="Different state variants.">
        <div className="flex flex-wrap gap-2">
          <${StatusBadge} state="connected" />
          <${StatusBadge} state="unauthorized" />
          <${StatusBadge} state="disconnected" />
          <${StatusBadge} state="streaming" />
          <${StatusBadge} state="idle" />
        </div>
      </${Panel}>

      <${Panel} title="Action Buttons" subtitle="Button tones.">
        <div className="flex flex-wrap gap-2">
          <${ActionButton} label="Neutral" tone="neutral" />
          <${ActionButton} label="Primary" tone="primary" />
          <${ActionButton} label="Danger" tone="danger" />
          <${ActionButton} label="Disabled" disabled=${true} />
        </div>
      </${Panel}>
    </div>
  `;

  return html`
    <${AppShell}
      title="Component Preview Console"
      subtitle="Exposing all library components for accessibility and visual regression testing."
      sidebar=${sidebar}
    >
      <div className="flex flex-col gap-5">
        <${Panel} title="Metrics Grid" subtitle="Grouped data overview.">
          <${MetricGrid} items=${metrics} />
        </${Panel}>

        <${Panel} title="Auth & Empty States" subtitle="Interaction gates.">
          <div className="space-y-4">
            <${AuthCard} onLogin=${() => alert('Login')} />
            <${EmptyState} title="No Data" description="Check back later." />
            <${EmptyState} title="Compact Empty" description="Used in sidebars." compact=${true} />
          </div>
        </${Panel}>

        <${Panel} title="Transcript" subtitle="Chat history representation.">
          <div className="space-y-4">
            <${Transcript} items=${messages} />
            <${Transcript} items=${messages} isStreaming=${true} />
          </div>
        </${Panel}>

        <${Panel} title="Timeline" subtitle="Event stream.">
          <${Timeline} events=${events} />
        </${Panel}>

        <${Panel} title="Tool Catalog" subtitle="Available capabilities.">
          <${ToolCatalog} tools=${tools} sourceLabel="Mock Preview" />
        </${Panel}>

        <${Panel} title="Payload Preview" subtitle="JSON data rendering.">
          <${JsonPreview} data=${{ hello: 'world', count: 42, nested: { key: 'value' } }} />
        </${Panel}>

        <${Panel} title="Prompt Composer" subtitle="Input field states.">
          <div className="space-y-4">
            <${PromptComposer}
              value=${prompt}
              onChange=${setPrompt}
              onSubmit=${(e) => { e.preventDefault(); alert(prompt); }}
              placeholder="Active prompt composer..."
            />
            <${PromptComposer}
              value="Disabled input content"
              onChange=${() => {}}
              onSubmit=${(e) => e.preventDefault()}
              disabled=${true}
            />
          </div>
        </${Panel}>

        <${Panel} title="Library Index" subtitle="Component listing.">
          <${LibraryList} />
        </${Panel}>
      </div>
    </${AppShell}>
  `;
}

const root = createRoot(document.getElementById('app'));
root.render(html`<${Preview} />`);
