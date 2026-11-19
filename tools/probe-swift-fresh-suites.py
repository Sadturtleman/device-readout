"""Temporary fresh full-suite experiment without phase output, preserving stalled stacks."""
import os
from pathlib import Path
import subprocess
import sys
from probe_swift_processes import capture, terminate

root = Path(__file__).resolve().parent.parent
logs = root / '.tools' / 'permission-probe'
logs.mkdir(parents=True, exist_ok=True)
swift = os.environ.get('SWIFT_BIN', 'swift')


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
        descendants = []
        try:
            descendants = capture(process.pid, logs, f'fresh-{iteration}')
        except (OSError, subprocess.SubprocessError) as error:
            (logs / f'fresh-{iteration}-capture-error.log').write_text(str(error))
        output = terminate(process, descendants)
    (logs / f'fresh-{iteration}.log').write_text(output)
    if expired or process.returncode != 0:
        print(f'[DEBUG-fresh-suite] iteration={iteration} timeout={expired} exit={process.returncode}', flush=True)
        print('\n'.join(output.splitlines()[-35:]), flush=True)
        sys.exit(124 if expired else process.returncode)
    if '[DEBUG-permission-phase]' in output or 'Executed 92 tests, with 0 failures' not in output:
        sys.exit(f'Unexpected tracing or test count in fresh run {iteration}')
    print(f'[DEBUG-fresh-suite] untraced fresh full suite {iteration}/10 passed', flush=True)
