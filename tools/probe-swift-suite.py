"""Temporary CI watchdog: preserve public-test progress and native stacks on a stall."""
import os
from pathlib import Path
import subprocess
import sys
from probe_swift_processes import capture, terminate

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'apple-ci-logs'
logs.mkdir(parents=True, exist_ok=True)
configuration = os.environ.get('CONFIGURATION', 'debug')
if configuration not in ('debug', 'release'):
    sys.exit('Invalid configuration')


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
    descendants = []
    try:
        descendants = capture(process.pid, logs, 'stalled')
    except (OSError, subprocess.SubprocessError) as error:
        (logs / 'stack-capture-error.log').write_text(str(error))
    output = terminate(process, descendants)

(logs / 'tests.log').write_text(output)
print(output, end='', flush=True)
print(f'[DEBUG-permission-suite] timeout={expired}, exit={process.returncode}', flush=True)
sys.exit(124 if expired else process.returncode)
