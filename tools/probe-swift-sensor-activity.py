"""Run the isolated public sensor lifecycle against a bounded external watchdog."""
import os
from pathlib import Path
import subprocess
import sys
from probe_swift_processes import capture, terminate

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'permission-probe'
logs.mkdir(parents=True, exist_ok=True)
swift = os.environ.get('SWIFT_BIN', 'swift')
common = ['--package-path', str(root / 'tools/swift-native-consumer'),
          '--scratch-path', str(logs / 'sensor-build'), '-c', 'release', '-Xswiftc', '-warnings-as-errors']
build = subprocess.run([swift, 'build', *common], cwd=root, capture_output=True, text=True, timeout=300)
(logs / 'sensor-build.log').write_text(build.stdout + build.stderr)
if build.returncode != 0:
    print(build.stdout + build.stderr)
    sys.exit(build.returncode)
binary_dir = subprocess.check_output([swift, 'build', *common, '--show-bin-path'], cwd=root, text=True).strip()
process = subprocess.Popen([str(Path(binary_dir) / 'NativeConsumer'), '--sensor-activity-replay'],
                           cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, start_new_session=True)
expired = False
try:
    output, _ = process.communicate(timeout=90)
except subprocess.TimeoutExpired:
    expired = True
    descendants = capture(process.pid, logs, 'sensor-activity')
    output = terminate(process, descendants)
(logs / 'sensor-activity.log').write_text(output)
print(output, flush=True)
print(f'[DEBUG-sensor-activity] timeout={expired} exit={process.returncode}', flush=True)
if expired or process.returncode != 0:
    sys.exit(124 if expired else process.returncode)
if 'SWIFT_SENSOR_ACTIVITY_REPLAY {"passed":true,"iterations":1000}' not in output:
    sys.exit('The public sensor consumer did not finish all deadline/activity races.')
