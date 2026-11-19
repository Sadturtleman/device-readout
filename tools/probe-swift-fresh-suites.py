"""Temporary fresh full-suite experiment without phase output, preserving stalled stacks."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'permission-probe'
logs.mkdir(parents=True, exist_ok=True)
swift = os.environ.get('SWIFT_BIN', 'swift')


def capture(group, iteration):
    table = subprocess.run(['ps', '-axo', 'pid=,ppid=,pgid=,comm='],
                           capture_output=True, text=True, timeout=10)
    (logs / f'fresh-{iteration}-processes.log').write_text(table.stdout + table.stderr)
    for line in table.stdout.splitlines():
        parts = line.split(None, 3)
        if len(parts) != 4 or parts[2] != str(group):
            continue
        if 'xctest' not in parts[3].lower() and 'DeviceReadoutPackageTests' not in parts[3]:
            continue
        sample = subprocess.run(['sample', parts[0], '3', '1'],
                                capture_output=True, text=True, timeout=15)
        (logs / f'fresh-{iteration}-stack-{parts[0]}.log').write_text(sample.stdout + sample.stderr)


for iteration in range(1, 11):
    scratch = logs / f'fresh-untraced-{iteration}'
    command = [swift, 'test', '--package-path', str(root / 'swift'),
               '--scratch-path', str(scratch / 'build'), '--cache-path', str(scratch / 'cache'),
               '-c', 'release', '-Xswiftc', '-module-cache-path', '-Xswiftc', str(scratch / 'modules'),
               '-Xswiftc', '-warnings-as-errors']
    process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    expired = False
    try:
        output, _ = process.communicate(timeout=180)
    except subprocess.TimeoutExpired:
        expired = True
        try:
            capture(process.pid, iteration)
        except (OSError, subprocess.SubprocessError) as error:
            (logs / f'fresh-{iteration}-capture-error.log').write_text(str(error))
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
    (logs / f'fresh-{iteration}.log').write_text(output)
    if expired or process.returncode != 0:
        print(f'[DEBUG-fresh-suite] iteration={iteration} timeout={expired} exit={process.returncode}', flush=True)
        print('\n'.join(output.splitlines()[-35:]), flush=True)
        sys.exit(124 if expired else process.returncode)
    if '[DEBUG-permission-phase]' in output or 'Executed 92 tests, with 0 failures' not in output:
        sys.exit(f'Unexpected tracing or test count in fresh run {iteration}')
    print(f'[DEBUG-fresh-suite] untraced fresh full suite {iteration}/10 passed', flush=True)
