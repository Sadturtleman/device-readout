"""Bound the public sensor deadline/activity regression outside its process."""
import os
from pathlib import Path
import signal
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
configuration = os.environ.get('CONFIGURATION', 'debug')
if configuration not in ('debug', 'release'):
    sys.exit('Invalid configuration')
swift = os.environ.get('SWIFT_BIN', 'swift')
binary_dir = subprocess.check_output(
    [swift, 'build', '--package-path', str(root / 'tools/swift-native-consumer'),
     '--scratch-path', str(root / '.tools/swift-consumer-build'),
     '-c', configuration, '--show-bin-path'], cwd=root, text=True, timeout=30).strip()
binary = Path(binary_dir) / 'NativeConsumer'
if not binary.is_file():
    sys.exit('Build the separate SwiftPM consumer before the sensor regression.')
process = subprocess.Popen([str(binary), '--sensor-activity-consumer'], cwd=root,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, start_new_session=True)
expired = False
try:
    output, _ = process.communicate(timeout=90)
except subprocess.TimeoutExpired:
    expired = True
    # This standalone consumer launches no child processes; only its owned group is signalled.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        output, _ = process.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        output, _ = process.communicate()
print(output, end='', flush=True)
if expired:
    sys.exit('Sensor activity/deadline consumer exceeded its 90-second external watchdog.')
if process.returncode != 0:
    sys.exit(process.returncode)
if 'SWIFT_SENSOR_ACTIVITY_CONSUMER {"passed":true,"iterations":1000}' not in output:
    sys.exit('The public consumer did not complete all 1,000 activity/deadline races.')
