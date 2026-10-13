"""Private CPU build; consumes the already pinned, portability-patched source.

No download, plugin installation, SIMD substitution or warning suppression.
The separate media helper links this host's existing FFmpeg libraries. It is
not a redistributable bundle until dependencies and GPL packaging are resolved.
"""
from pathlib import Path
import argparse
import concurrent.futures
import json
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--asan', action='store_true')
parser.add_argument('--ubsan', action='store_true')
parser.add_argument('--deployment-target', default='27.0')
parser.add_argument('--sdk', type=Path)
args = parser.parse_args()
here = Path(__file__).resolve().parent
source = args.source.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
flags = ['-std=c++17', '-arch', 'arm64', '-Wall', '-Wextra', '-Werror', '-fPIC']
sdk = args.sdk or Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip())
flags += ['-mmacosx-version-min='+args.deployment_target, '-isysroot', str(sdk)]
flags += ['-O1', '-g', '-fsanitize=address', '-fno-omit-frame-pointer'] if args.asan else ['-O2']
if args.ubsan: flags += ['-g', '-fsanitize=undefined', '-fno-sanitize-recover=all', '-fno-omit-frame-pointer']
includes = ['-I'+str(here), '-I'+str(source/'src'), '-I/opt/homebrew/include']
paths = [source/'src'/p for p in ['core.cpp', 'random.cpp', 'process_plane_context.cpp',
         'flash3kyuu_deband_impl_c.cpp', 'impl_dispatch.cpp']]
paths += [here/'neo_adapter.cpp', here/'neo_media.cpp']
def compile_one(path):
    obj = output/(path.stem+'.o')
    command = ['xcrun', 'clang++', *flags, *includes, '-c', str(path), '-o', str(obj)]
    result = subprocess.run(command, text=True, capture_output=True, timeout=120)
    (output/(path.stem+'.log')).write_text(result.stdout+result.stderr)
    return {'command': command, 'exit': result.returncode, 'object': str(obj)}
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(compile_one, paths))
(output/'build.json').write_text(json.dumps(results, indent=2)+'\n')
for item in results:
    print(Path(item['object']).name, item['exit'])
    if item['exit']: print(Path(item['object']).with_suffix('.log').read_text())
if any(item['exit'] for item in results): raise SystemExit(1)
objects = [item['object'] for item in results[:-1]]
commands = [
    ['xcrun', 'clang++', *flags, '-Wl,-fatal_warnings', '-dynamiclib', *objects, '-o', str(output/'libup60p-neo.dylib')],
    ['xcrun', 'clang++', *flags, '-Wl,-fatal_warnings', *objects, results[-1]['object'], '-L/opt/homebrew/lib',
     '-lavformat', '-lavcodec', '-lavutil', '-o', str(output/'up60p-neo-media')],
]
for index, command in enumerate(commands):
    result = subprocess.run(command, text=True, capture_output=True, timeout=120)
    (output/f'link-{index}.log').write_text(result.stdout+result.stderr)
    print('link', index, result.returncode, result.stdout+result.stderr)
    if result.returncode: raise SystemExit(result.returncode)
(output/'link.json').write_text(json.dumps(commands, indent=2)+'\n')
