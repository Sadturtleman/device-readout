"""Temporary bounded public-consumer replay of the permission lifecycle."""
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


scratch = logs / 'consumer'
common = ['--package-path', str(root / 'tools/swift-native-consumer'), '--scratch-path', str(scratch / 'build'),
          '--cache-path', str(scratch / 'cache'), '-c', 'release',
          '-Xswiftc', '-module-cache-path', '-Xswiftc', str(scratch / 'modules'),
          '-Xswiftc', '-warnings-as-errors']
run([swift, 'build', *common], 'build', 300)
binary_directory = run([swift, 'build', *common, '--show-bin-path'], 'binary-path', 30).strip()
binary = Path(binary_directory) / 'NativeConsumer'
if not binary.is_file():
    sys.exit('The separate permission replay executable was not built.')
output = run([str(binary), '--permission-replay'], 'replay', 120)
if 'SWIFT_PERMISSION_REPLAY {"passed":true,"iterations":1000}' not in output:
    sys.exit('The separate consumer did not complete all 1000 permission lifecycles.')
print('[DEBUG-permission-probe] public consumer passed 1000 permission lifecycles', flush=True)
