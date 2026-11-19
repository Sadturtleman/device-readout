"""Temporary bounded repetition of the whole suite around the stalled permission test."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'permission-probe'
logs.mkdir(parents=True, exist_ok=True)
swift = os.environ.get('SWIFT_BIN', 'swift')
common = ['--package-path', str(root / 'swift'), '--scratch-path', str(root / '.tools/swift-build'),
          '--cache-path', str(root / '.tools/swift-cache'), '-c', 'release',
          '-Xswiftc', '-module-cache-path', '-Xswiftc', str(root / '.tools/swift-module-cache'),
          '-Xswiftc', '-warnings-as-errors']


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


run([swift, 'build', '--build-tests', *common], 'build', 300)
method = 'testCoordinatorErrorsReplacementAndSynchronousPublicationHaveExplicitRequestSemantics'
for attempt in range(1, 31):
    output = run([swift, 'test', '--skip-build', *common],
                 f'permission-{attempt}', 60)
    if 'Executed 92 tests, with 0 failures' not in output or not any(method in line and 'passed' in line for line in output.splitlines()):
        print(output, flush=True)
        sys.exit('The complete 92-test suite did not execute successfully.')
    print(f'[DEBUG-permission-probe] passed {attempt}/30 whole-suite repetitions', flush=True)
