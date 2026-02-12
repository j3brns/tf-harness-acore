#!/usr/bin/env python3
import sys
import time
import subprocess
import argparse
from pathlib import Path
from datetime import datetime

try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
except ImportError:
    print("Error: 'watchdog' library is required. Install it via: pip install watchdog")
    sys.exit(1)


class AgentCodeHandler(FileSystemEventHandler):
    def __init__(self, project_dir, target_module="module.agentcore_runtime"):
        self.project_dir = Path(project_dir)
        self.terraform_dir = self.project_dir / "terraform"
        self.target_module = target_module
        self.last_trigger = 0
        self.debounce_seconds = 2.0

    def on_modified(self, event):
        if event.is_directory:
            return
        if not event.src_path.endswith(".py"):
            return

        # Debounce
        current_time = time.time()
        if current_time - self.last_trigger < self.debounce_seconds:
            return
        self.last_trigger = current_time

        print(f"\n[HOT-RELOAD] Detected change in {event.src_path} at {datetime.now().strftime('%H:%M:%S')}")
        self.trigger_apply()

    def trigger_apply(self):
        print(f"[HOT-RELOAD] Applying changes to {self.target_module}...")

        cmd = ["terraform", "apply", "-auto-approve", "-input=false", f"-target={self.target_module}"]

        try:
            # We run this in the terraform directory
            subprocess.run(cmd, cwd=self.terraform_dir, check=True)
            print("[HOT-RELOAD] Success! Agent updated.")
        except subprocess.CalledProcessError as e:
            print(f"[HOT-RELOAD] Error applying changes: {e}")
        except FileNotFoundError:
            print("[HOT-RELOAD] Error: 'terraform' executable not found in PATH.")


def main():
    parser = argparse.ArgumentParser(description="Watch agent-code directory and hot-reload Terraform.")
    parser.add_argument("project_dir", nargs="?", default=".", help="Root directory of the agent project")
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    agent_code_dir = project_dir / "agent-code"
    terraform_dir = project_dir / "terraform"

    if not agent_code_dir.exists():
        print(f"Error: Directory not found: {agent_code_dir}")
        sys.exit(1)

    if not terraform_dir.exists():
        print(f"Error: Directory not found: {terraform_dir}")
        sys.exit(1)

    print("[HOT-RELOAD] Watching {agent_code_dir} for Python changes...")
    print("[HOT-RELOAD] Press Ctrl+C to stop.")

    event_handler = AgentCodeHandler(project_dir)
    observer = Observer()
    observer.schedule(event_handler, str(agent_code_dir), recursive=True)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
