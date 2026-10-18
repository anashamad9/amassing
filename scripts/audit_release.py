#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Inspect the actual app bundle; never alter Gatekeeper or system tools."""
import argparse,json,os,plistlib,re,struct,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,default=ROOT/'dist/portable/Anasing.app');parser.add_argument('--output',type=Path)
args=parser.parse_args();app=args.app.resolve();resources=app/'Contents/Resources'

def run(argv):
 p=subprocess.run([str(x) for x in argv],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);return p.returncode,p.stdout.strip()
def macho(path):
 try:
  with path.open('rb') as f:return f.read(4) in {b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf'}
 except OSError:return False

def build_versions(path):
 versions=[]
 with path.open('rb') as f:
  magic=f.read(4)
  offsets=[0]
  if magic==b'\xca\xfe\xba\xbe':
   count=struct.unpack('>I',f.read(4))[0];offsets=[]
   for _ in range(count):
    cpu,sub,offset,size,align=struct.unpack('>IIIII',f.read(20));offsets.append(offset)
  for offset in offsets:
   f.seek(offset);header=f.read(32)
   if header[:4]!=b'\xcf\xfa\xed\xfe':continue
   cpu,sub,kind,ncmds,sizecmds,flags,reserved=struct.unpack('<IIIIIII',header[4:])
   for _ in range(ncmds):
    command=f.read(8)
    if len(command)!=8:break
    cmd,size=struct.unpack('<II',command);body=f.read(size-8)
    version=struct.unpack('<II',body[:8])[1] if cmd==0x32 else struct.unpack('<I',body[:4])[0] if cmd==0x24 else None
    if version and cpu==0x100000c:versions.append((version>>16,(version>>8)&255,version&255))
 return versions

external=[];escaped=[];codefiles=[];minimum=(14,0,0);highest=[]
for path in app.rglob('*'):
 if path.is_symlink():
  if not path.resolve().is_relative_to(app):escaped.append(str(path.relative_to(app)))
  continue
 if not path.is_file() or not macho(path):continue
 codefiles.append(path)
 _,output=run(['/usr/bin/otool','-l',path])
 for link in re.findall(r'cmd LC_(?:LOAD_DYLIB|LOAD_WEAK_DYLIB|REEXPORT_DYLIB|LOAD_UPWARD_DYLIB)\s+cmdsize \d+\s+name (.+?) \(offset',output):
  if link.startswith('/') and not link.startswith(('/usr/lib/','/System/Library/')):external.append({'file':str(path.relative_to(app)),'dependency':link})
 for version in build_versions(path):
  if version>minimum:minimum=version;highest=[str(path.relative_to(app))]
  elif version==minimum:highest.append(str(path.relative_to(app)))
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
required=['python/bin/python3','tools/bin/ffmpeg','tools/bin/ffprobe','tools/bin/tesseract','tools/share/tessdata/eng.traineddata','LibreOffice.app/Contents/MacOS/soffice','engine/anasing_engine.py','Licenses/Anasing-AGPL-3.0.txt']
missing=[name for name in required if not (resources/name).exists()]
sig_code,sig_output=run(['/usr/bin/codesign','--verify','--deep','--strict',app])
_,identity=run(['/usr/bin/codesign','-d','--verbose=4',app])
declared=tuple(int(n) for n in info["LSMinimumSystemVersion"].split("."));declared=declared+(0,)*(3-len(declared))
portable=not external and not escaped and not missing and sig_code==0 and declared>=minimum
signed='Signature=adhoc' not in identity and 'TeamIdentifier=not set' not in identity
report={'version':info.get('AnasingReleaseVersion',info['CFBundleShortVersionString']),'architecture':'arm64','minimum_macos':'.'.join(map(str,minimum)),'declared_minimum_macos':info['LSMinimumSystemVersion'],'self_contained_dependency_audit_passed':portable,'mach_o_files_inspected':len(codefiles),'external_non_system_dependencies':external,'escaping_symlinks':escaped,'missing_bundle_components':missing,'signature_valid':sig_code==0,'signature_details':sig_output,'developer_id_signed':signed,'notarized':False,'public_release_ready':False,'remaining_release_steps':['Developer ID signing and Apple notarization','Independent test on a clean Apple silicon Mac','Publish the source and corresponding-source materials alongside binary release'],'minimum_os_drivers':highest[:12]}
text=json.dumps(report,indent=2)
if args.output:args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(text+'\n')
print(text)
raise SystemExit(0 if portable else 1)
