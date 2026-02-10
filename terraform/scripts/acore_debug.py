#!/usr/bin/env python3
import sys
import time
import random
import threading
import argparse
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
    from rich.syntax import Syntax
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
    "Routing to Lambda target: arn:aws:lambda:us-east-1:123456789012:function:agent",
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
    layout.split(
        Layout(name="header", size=3),
        Layout(name="main", ratio=1),
        Layout(name="footer", size=3)
    )
    layout["main"].split_row(
        Layout(name="logs", ratio=2),
        Layout(name="status", ratio=1)
    )
    return layout

def get_log_panel(log_buffer):
    text = Text()
    for ts, msg in log_buffer[-20:]:
        text.append(f"[{ts}] ", style="dim green")
        text.append(f"{msg}
", style=MATRIX_GREEN)
    
    return Panel(
        text,
        title="[bold green]LIVE LOGS (CLOUDWATCH)[/bold green]",
        border_style="green",
        padding=(1, 1)
    )

def get_status_panel():
    table = Table(show_header=True, header_style="bold black on green", border_style="green", expand=True)
    table.add_column("Component")
    table.add_column("Status")
    table.add_column("Latency")
    
    for comp, status, lat in TRACES:
        table.add_row(comp, status, lat)

    return Panel(
        table,
        title="[bold green]SYSTEM TRACE[/bold green]",
        border_style="green"
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-intro", action="store_true", help="Skip the matrix intro")
    args = parser.parse_args()

    if not args.skip_intro:
        matrix_rain_effect()
        show_kung_fu_banner()

    layout = generate_layout()
    
    # Header
    layout["header"].update(
        Panel(
            Align.center("[bold green]AGENTCORE MATRIX DEBUGGER // CONNECTED TO: us-east-1[/bold green]"),
            style="green on black"
        )
    )

    # Footer
    layout["footer"].update(
        Panel(
            Align.left("[green]COMMANDS: [bold]q[/bold]: Quit | [bold]c[/bold]: Clear Logs | [bold]r[/bold]: Reload Agent[/green]"),
            border_style="green"
        )
    )

    log_buffer = []
    
    with Live(layout, refresh_per_second=4, screen=True) as live:
        while True:
            # Simulate incoming logs
            if random.random() < 0.3:
                msg = random.choice(LOG_MESSAGES)
                ts = datetime.now().strftime("%H:%M:%S")
                log_buffer.append((ts, msg))
            
            layout["logs"].update(get_log_panel(log_buffer))
            layout["status"].update(get_status_panel())
            
            time.sleep(0.2)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        console.clear()
        console.print("[bold green]Connection Terminated.[/bold green]")
