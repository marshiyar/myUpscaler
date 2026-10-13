"""Package a private helper with its existing local non-system dylib closure.

No installs/downloads. Relocation applies only to new copies inside the chosen
bundle; source libraries and their signatures are untouched. Signing remains
the enclosing build phase's responsibility. This is not shipping approval.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--executable',type=Path,required=True)
parser.add_argument('--macos',type=Path,required=True)
args=parser.parse_args()
macos=args.macos.resolve()
destination=macos/'ThirdParty/NeoF3kdb'
destination.mkdir(parents=True,exist_ok=True)
helper=macos/'up60p-neo-media'
helper.unlink(missing_ok=True)
shutil.copy2(args.executable,helper)
def dependencies(path):
    lines=subprocess.check_output(['xcrun','otool','-L',str(path)],text=True).splitlines()[1:]
    return [line.strip().split(' (compatibility version',1)[0] for line in lines]
closure={}
pending=[helper]
total=0
while pending:
    path=pending.pop()
    for dependency in dependencies(path):
        if dependency.startswith('/usr/lib/') or dependency.startswith('/System/Library/'): continue
        if not dependency.startswith('/opt/homebrew/'):
            raise RuntimeError('Unexpected private helper dependency: '+dependency)
        original=Path(dependency).resolve(strict=True)
        name=Path(dependency).name
        if name in closure:
            if closure[name]['original']!=str(original): raise RuntimeError('Dependency basename collision: '+name)
            continue
        total+=original.stat().st_size
        if total>128*1024*1024: raise RuntimeError('Private helper dylib closure exceeds128MiB')
        closure[name]={'original':str(original),'sha256':hashlib.sha256(original.read_bytes()).hexdigest()}
        copy=destination/name
        # Rebuild only our owned derived copy; prior source modes may be read-only.
        copy.unlink(missing_ok=True)
        shutil.copy2(original,copy)
        pending.append(copy)
for path in [helper,*[destination/name for name in closure]]:
    architecture=subprocess.check_output(['xcrun','lipo','-archs',str(path)],text=True).strip().split()
    if architecture!=['arm64']: raise RuntimeError('Private helper dependency must be arm64: '+str(path))
    changes=[]
    for dependency in dependencies(path):
        if dependency.startswith('/opt/homebrew/'):
            name=Path(dependency).name
            replacement=('@loader_path/ThirdParty/NeoF3kdb/' if path==helper else '@loader_path/')+name
            changes+=['-change',dependency,replacement]
    if path!=helper: changes+=['-id','@loader_path/'+path.name]
    subprocess.run(['xcrun','install_name_tool',*changes,str(path)],check=True)
    for dependency in dependencies(path):
        if dependency.startswith('/opt/homebrew/'): raise RuntimeError('Unrelocated dependency: '+dependency)
        if dependency.startswith('@loader_path/') and not (path.parent/dependency.removeprefix('@loader_path/')).is_file():
            raise RuntimeError('Missing bundled dependency: '+dependency)
    if path!=helper:
        closure[path.name]['bundled_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
resources=macos.parent/'Resources'/'NeoF3kdb'
resources.mkdir(parents=True,exist_ok=True)
# Non-code records belong in Resources so the outer app signature treats them
# as resources instead of unsigned code in Contents/MacOS.
(destination/'dependencies.json').unlink(missing_ok=True)
(resources/'dependencies.json').write_text(json.dumps({'total_bytes':total,'libraries':closure},indent=2)+'\n')
print(f'Private helper packaged: {len(closure)} existing libraries, {total} bytes')
