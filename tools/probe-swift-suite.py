"""Temporary CI watchdog: preserve public-test progress and native stacks on a stall."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'apple-ci-logs'
logs.mkdir(parents=True, exist_ok=True)
configuration = os.environ.get('CONFIGURATION', 'debug')
if configuration not in ('debug', 'release'):
    sys.exit('Invalid configuration')


def stacks(group):
    processes = subprocess.run(['ps', '-axo', 'pid=,ppid=,pgid=,comm='],
                               capture_output=True, text=True, timeout=10)
    (logs / 'stalled-processes.log').write_text(processes.stdout + processes.stderr)
    for line in processes.stdout.splitlines():
        columns = line.split(None, 3)
        if len(columns) != 4 or columns[2] != str(group):
            continue
        pid, _, _, command = columns
        if 'xctest' not in command.lower() and 'DeviceReadoutPackageTests' not in command:
            continue
        try:
            sample = subprocess.run(['sample', pid, '3', '1'], capture_output=True, text=True, timeout=15)
            (logs / f'stalled-stack-{pid}.log').write_text(sample.stdout + sample.stderr)
        except subprocess.TimeoutExpired as error:
            (logs / f'stalled-stack-{pid}.log').write_text(str(error))


command = ['sh', 'tools/test-swift.sh', '-c', configuration, '-Xswiftc', '-warnings-as-errors']
if os.environ.get('DEVICE_READOUT_PERMISSION_TRACE') == '1':
    command.extend(['-Xswiftc', '-DDEVICE_READOUT_PERMISSION_TRACE'])
process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, start_new_session=True)
expired = False
try:
    output, _ = process.communicate(timeout=300)
except subprocess.TimeoutExpired:
    expired = True
    try:
        stacks(process.pid)
    except (OSError, subprocess.SubprocessError) as error:
        (logs / 'stack-capture-error.log').write_text(str(error))
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        output, _ = process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()

(logs / 'tests.log').write_text(output)
print(output, end='', flush=True)
print(f'[DEBUG-permission-suite] timeout={expired}, exit={process.returncode}', flush=True)
sys.exit(124 if expired else process.returncode)
