"""Temporary capture of owned test descendants, including XCTest's separate process group."""
from dataclasses import dataclass
import os
import signal
import subprocess


@dataclass(frozen=True)
class Process:
    pid: int
    parent: int
    group: int
    started: str
    command: str


def snapshot():
    result = subprocess.run(['ps', '-axo', 'pid=,ppid=,pgid=,lstart=,comm='],
                            capture_output=True, text=True, timeout=10, check=True)
    processes = {}
    for line in result.stdout.splitlines():
        columns = line.split(None, 8)
        if len(columns) == 9:
            process = Process(int(columns[0]), int(columns[1]), int(columns[2]),
                              ' '.join(columns[3:8]), columns[8])
            processes[process.pid] = process
    return result.stdout + result.stderr, processes


def capture(root_pid, logs, prefix):
    text, processes = snapshot()
    (logs / f'{prefix}-processes.log').write_text(text)
    owned = {root_pid}
    while True:
        children = {value.pid for value in processes.values() if value.parent in owned}
        if children <= owned:
            break
        owned |= children
    descendants = [value for value in processes.values() if value.pid in owned]
    # Sample the SwiftPM parent as well as XCTest, so pipe/runtime stalls can be distinguished.
    for value in descendants:
        if value.pid != root_pid and 'xctest' not in value.command.lower():
            continue
        try:
            result = subprocess.run(['sample', str(value.pid), '3', '1'],
                                    capture_output=True, text=True, timeout=15)
            (logs / f'{prefix}-stack-{value.pid}.log').write_text(result.stdout + result.stderr)
        except (OSError, subprocess.SubprocessError) as error:
            (logs / f'{prefix}-stack-{value.pid}.log').write_text(str(error))
    return descendants


def terminate(process, descendants):
    def send(sig):
        try:
            _, current = snapshot()
        except (OSError, subprocess.SubprocessError):
            current = {}
        # Only captured descendants with the same start time/command may be signaled.
        for value in reversed(descendants):
            live = current.get(value.pid)
            if live is not None and live.started == value.started and live.command == value.command:
                try:
                    os.kill(value.pid, sig)
                except ProcessLookupError:
                    pass
        # The unreaped Popen PID still owns this original group; children can create other groups.
        if process.returncode is None:
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass

    send(signal.SIGTERM)
    try:
        output, _ = process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        send(signal.SIGKILL)
        output, _ = process.communicate()
    else:
        # A separate-group XCTest may outlive the SwiftPM parent even after its pipe closes.
        send(signal.SIGKILL)
    return output
