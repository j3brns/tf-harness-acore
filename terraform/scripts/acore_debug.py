#!/usr/bin/env python3
import sys
import time
import random
import threading
import argparse
import subprocess
import json
import boto3
from pathlib import Path
from datetime import datetime

# --- Dependency Check ---
try:
    from rich.console import Console
    from rich.layout import Layout
    from rich.live import Live
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text
    from rich.style import Style
    from rich.align import Align
except ImportError:
    print("\033[0;32mError: The Matrix requires 'rich'. Install it via:\033[0m")
    print("\033[1;32mpip install rich boto3\033[0m")
    sys.exit(1)

# --- Configuration ---
MATRIX_GREEN = "bold green"
MATRIX_DARK = "green on black"
MATRIX_STYLE = Style(color="green", bgcolor="black", bold=True)

console = Console(style=MATRIX_STYLE)

# --- Mock Data (Simulating CloudWatch/X-Ray for prototype) ---
LOG_MESSAGES = [
    "Initializing AgentCore Runtime environment...",
    "Loading MCP Tool: s3-tools...",
    "Loading MCP Tool: titanic-data...",
    "Establishing secure connection to Bedrock Gateway...",
    "Verifying identity proof...",
    "Identity confirmed. Agent is active.",
    "Listening for events...",
    "Incoming payload: { 'action': 'invoke', 'agentId': 'AG-12345' }",
    "Processing natural language query...",
    "Routing to Lambda target: arn:aws:lambda:eu-west-2:123456789012:function:agent",
    "Executing tool: list_buckets",
    "Tool execution successful. Duration: 142ms",
    "Generating response...",
]

TRACES = [
    ("Gateway", "200 OK", "12ms"),
    ("Authorizer", "ALLOW", "4ms"),
    ("Router", "Forward", "2ms"),
    ("Lambda", "Invoke", "145ms"),
    ("Bedrock", "Generate", "850ms"),
]

# --- Functions ---


def discover_config():
    """Tries to discover configuration from Terraform outputs."""
    try:
        # Check if we are in scripts/ or root
        cwd = Path.cwd()
        tf_dir = cwd if (cwd / "main.tf").exists() else cwd.parent

        cmd = ["terraform", "output", "-json"]
        res = subprocess.check_output(cmd, cwd=tf_dir, stderr=subprocess.DEVNULL).decode()
        outputs = json.loads(res)

        config = {
            "region": "eu-west-2",  # Default
            "agent_id": outputs.get("agentcore_runtime_arn", {}).get("value")
            or outputs.get("gateway_id", {}).get("value"),
            "log_group": outputs.get("log_group_name", {}).get("value"),
        }

        # Region usually in provider or a variable, let's try to find it
        # If not in outputs, we might need to check terraform.tfstate or just default
        return config
    except Exception:
        return {"region": "eu-west-2", "agent_id": None, "log_group": None}


def matrix_rain_effect(duration=3.0):
    """Simulates the falling code effect before startup."""
    start = time.time()
    width = console.width
    chars = "abcdefghijklmnopqrstuvwxyz0123456789@#$%^&*="

    while time.time() - start < duration:
        line = ""
        for _ in range(width):
            if random.random() < 0.05:
                line += f"[green]{random.choice(chars)}[/green]"
            else:
                line += " "
        console.print(line, end="")
        time.sleep(0.05)

    console.clear()


def show_kung_fu_banner():
    """Displays the epic banner."""
    banner = """
    ╔════════════════════════════════════════════════════════════════╗
    ║                                                                ║
    ║   AGENTCORE DEBUGGER v1.0                                      ║
    ║   STATUS: CONNECTED                                            ║
    ║                                                                ║
    ║   > UPLOADING SKILLSETS... 100%                                ║
    ║   > NEURAL LINK... STABLE                                      ║
    ║                                                                ║
    ║   [bold white blink]I KNOW KUNG FU.[/bold white blink]                                         ║
    ║                                                                ║
    ╚════════════════════════════════════════════════════════════════╝
    """
    console.print(Align.center(banner), style=MATRIX_GREEN)
    time.sleep(2)
    console.clear()


def generate_layout():
    layout = Layout()
    layout.split(Layout(name="header", size=3), Layout(name="main", ratio=1), Layout(name="footer", size=3))
    layout["main"].split_row(Layout(name="logs", ratio=2), Layout(name="status", ratio=1))
    return layout


def get_log_panel(log_buffer):
    text = Text()
    for ts, msg in log_buffer[-20:]:
        text.append(f"[{ts}] ", style="dim green")
        text.append(f"{msg}\n", style=MATRIX_GREEN)

    return Panel(text, title="[bold green]LIVE LOGS (CLOUDWATCH)[/bold green]", border_style="green", padding=(1, 1))


def get_status_panel():
    table = Table(show_header=True, header_style="bold black on green", border_style="green", expand=True)
    table.add_column("Component")
    table.add_column("Status")
    table.add_column("Latency")

    for comp, status, lat in TRACES:
        table.add_row(comp, status, lat)

    return Panel(table, title="[bold green]SYSTEM TRACE[/bold green]", border_style="green")


class CloudWatchTailer:
    def __init__(self, region, log_group):
        self.region = region
        self.log_group = log_group
        self.log_buffer = []
        self.last_timestamp = int((time.time() - 3600) * 1000)  # Last hour
        try:
            self.logs = boto3.client("logs", region_name=region)
            self.active = True
        except Exception:
            self.active = False

    def fetch_logs(self):
        if not self.active or not self.log_group:
            return
        try:
            response = self.logs.filter_log_events(
                logGroupName=self.log_group, startTime=self.last_timestamp + 1, limit=10
            )
            for event in response.get("events", []):
                ts = datetime.fromtimestamp(event["timestamp"] / 1000.0).strftime("%H:%M:%S")
                self.log_buffer.append((ts, event["message"]))
                self.last_timestamp = max(self.last_timestamp, event["timestamp"])
        except Exception:
            # Silently fail or log briefly
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-intro", action="store_true", help="Skip the matrix intro")
    parser.add_argument("--region", help="AWS Region")
    parser.add_argument("--agent-id", help="Bedrock Agent ID")
    parser.add_argument("--log-group", help="CloudWatch Log Group Name")
    args = parser.parse_args()

    # Configuration Discovery
    config = discover_config()
    region = args.region or config.get("region") or "eu-west-2"
    agent_id = args.agent_id or config.get("agent_id") or "UNKNOWN"
    log_group = args.log_group or config.get("log_group")

    if not args.skip_intro:
        matrix_rain_effect()
        show_kung_fu_banner()

    layout = generate_layout()

    # Header
    layout["header"].update(
        Panel(
            Align.center(f"[bold green]AGENTCORE MATRIX DEBUGGER // ID: {agent_id} // REGION: {region}[/bold green]"),
            style="green on black",
        )
    )

    # Footer
    layout["footer"].update(
        Panel(
            Align.left(
                "[green]COMMANDS: [bold]q[/bold]: Quit | [bold]c[/bold]: Clear Logs | [bold]r[/bold]: Reload Agent[/green]"
            ),
            border_style="green",
        )
    )

    tailer = CloudWatchTailer(region, log_group)

    # Target module for reload (Rule 5 OCDS)
    target_module = "module.agentcore_runtime"
    reloading = False

    def run_terraform_apply():
        nonlocal reloading
        # Check if we are in scripts/ or root
        cwd = Path.cwd()
        tf_dir = cwd if (cwd / "main.tf").exists() else cwd.parent

        cmd = ["terraform", "apply", "-auto-approve", "-input=false", f"-target={target_module}"]
        try:
            subprocess.run(cmd, cwd=tf_dir, check=True, capture_output=True)
            tailer.log_buffer.append((datetime.now().strftime("%H:%M:%S"), "[SYSTEM] Agent reloaded successfully."))
        except Exception:
            tailer.log_buffer.append((datetime.now().strftime("%H:%M:%S"), "[ERROR] Reload failed."))
        finally:
            reloading = False

    def trigger_reload():
        nonlocal reloading
        if reloading:
            return
        reloading = True
        ts = datetime.now().strftime("%H:%M:%S")
        tailer.log_buffer.append((ts, "[SYSTEM] Hot-Reload initiated (OCDS compliance)..."))
        thread = threading.Thread(target=run_terraform_apply)
        thread.start()

    # Keyboard handling (Windows)
    import msvcrt

    with Live(layout, refresh_per_second=4, screen=True):
        while True:
            # Check for input
            if msvcrt.kbhit():
                key = msvcrt.getch().decode("utf-8").lower()
                if key == "q":
                    break
                elif key == "c":
                    tailer.log_buffer = []
                elif key == "r":
                    trigger_reload()

            # Status Update
            if reloading:
                layout["header"].update(
                    Panel(
                        Align.center(
                            f"[bold yellow]SYSTEM REBUILDING... (OCDS STAGE 2) // ID: {agent_id}[/bold yellow]"
                        ),
                        style="yellow on black",
                    )
                )
            else:
                layout["header"].update(
                    Panel(
                        Align.center(
                            f"[bold green]AGENTCORE MATRIX DEBUGGER // ID: {agent_id} // REGION: {region}[/bold green]"
                        ),
                        style="green on black",
                    )
                )

            # Real logs
            tailer.fetch_logs()

            # If no real logs yet, show some "System ready" noise
            if not tailer.log_buffer and random.random() < 0.1:
                ts = datetime.now().strftime("%H:%M:%S")
                tailer.log_buffer.append((ts, "System operational. Waiting for traffic..."))

            layout["logs"].update(get_log_panel(tailer.log_buffer))
            layout["status"].update(get_status_panel())

            time.sleep(0.5)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.clear()
        console.print("[bold green]Connection Terminated.[/bold green]")
