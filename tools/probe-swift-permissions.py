"""Temporary bounded fresh-build repetitions of the suite that stalled in Apple CI."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'permission-probe'
logs.mkdir(parents=True, exist_ok=True)
swift = os.environ.get('SWIFT_BIN', 'swift')


def run(command, label, timeout):
    process = subprocess.Popen(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    expired = False
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        expired = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
    (logs / (label + '.log')).write_text(output)
    if expired or process.returncode != 0:
        print(f'[DEBUG-permission-probe] {label}: timeout={expired}, exit={process.returncode}', flush=True)
        print('\n'.join(output.splitlines()[-30:]), flush=True)
        raise SystemExit(124 if expired else process.returncode)
    return output


method = 'testCoordinatorErrorsReplacementAndSynchronousPublicationHaveExplicitRequestSemantics'
for attempt in range(1, 11):
    scratch = logs / f'fresh-{attempt}'
    if scratch.exists():
        sys.exit('Fresh-build probe refuses to reuse an existing build directory.')
    common = ['--package-path', str(root / 'swift'), '--scratch-path', str(scratch / 'build'),
              '--cache-path', str(scratch / 'cache'), '-c', 'release',
              '-Xswiftc', '-module-cache-path', '-Xswiftc', str(scratch / 'modules'),
              '-Xswiftc', '-warnings-as-errors']
    output = run([swift, 'test', *common], f'permission-{attempt}', 180)
    if 'Executed 92 tests, with 0 failures' not in output or not any(method in line and 'passed' in line for line in output.splitlines()):
        print(output, flush=True)
        sys.exit('The complete 92-test suite did not execute successfully.')
    print(f'[DEBUG-permission-probe] passed {attempt}/10 fresh-build suite repetitions', flush=True)
