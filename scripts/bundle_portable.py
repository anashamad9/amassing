#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Bundle a local Apple-silicon beta without changing system installations."""
import hashlib,json,os,plistlib,re,shutil,subprocess,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'dist/Anasing.app'
APP=ROOT/'dist/portable/Anasing.app'
CONTENTS=APP/'Contents';RES=CONTENTS/'Resources'
CACHE=ROOT/'.release-cache/python-runtime/python'
LIBS=CONTENTS/'Frameworks/AnasingTools'
NOTICES=RES/'Licenses'
MACHO_MAGICS={b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf'}

def run(args,check=True):
    p=subprocess.run([str(x) for x in args],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    if check and p.returncode: raise RuntimeError(' '.join(str(x) for x in args)+'\n'+p.stderr[-4000:])
    return p.stdout

def macho(path):
    try:
        with path.open('rb') as f:return f.read(4) in MACHO_MAGICS
    except OSError:return False

def copytree(src,dst):
    shutil.copytree(src,dst,symlinks=True,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','.DS_Store','*.pyc'))

if not CACHE.exists():raise SystemExit('Run scripts/fetch_runtime.sh first')
OCR=ROOT/'.release-cache/ocr-macos26'
if not (OCR/'bin/tesseract').exists():run(['/bin/zsh',ROOT/'scripts/build_ocr.sh'])
if APP.exists():shutil.rmtree(APP)
copytree(SOURCE,APP)
if (RES/'runtime').exists():shutil.rmtree(RES/'runtime')
copytree(CACHE,RES/'python')
copytree(Path('/Applications/LibreOffice.app'),RES/'LibreOffice.app')
# Isolate bundled LibreOffice from any separately installed instance.
LIBS.mkdir(parents=True,exist_ok=True);NOTICES.mkdir(parents=True,exist_ok=True)
(RES/'tools/bin').mkdir(parents=True,exist_ok=True)
copytree(Path('/opt/homebrew/opt/tesseract/share/tessdata'),RES/'tools/share/tessdata')

copied={};kegs={};patches=[]
def remember_keg(path):
    parts=path.parts
    if 'Cellar' not in parts:return
    i=parts.index('Cellar')
    keg=Path(*parts[:i+3]);kegs[parts[i+1]]=keg

def dependencies(path):
    output=run(['/usr/bin/otool','-L',path])
    return [line.strip().split(' (compatibility',1)[0] for line in output.splitlines()[1:] if line.strip() and not line.endswith(':')]

def bundle_file(original,destination=None):
    original=original.resolve()
    if str(original) in copied:return copied[str(original)]
    target=destination or LIBS/original.name
    if target.exists() and hashlib.sha256(target.read_bytes()).digest()!=hashlib.sha256(original.read_bytes()).digest():
        raise RuntimeError('Different libraries have the same name: '+str(target))
    shutil.copy2(original,target);target.chmod(target.stat().st_mode|0o200)
    copied[str(original)]=target;remember_keg(original)
    links=dependencies(original)
    run(['/usr/bin/codesign','--remove-signature',target],check=False)
    for link in links:
        if link.startswith(('/opt/homebrew/','@rpath/','@loader_path/','@executable_path/')):
            if link.startswith('/opt/homebrew/'):
                resolved=Path(link).resolve()
            elif link.startswith('@loader_path/'):
                resolved=(original.parent/link[len('@loader_path/'):]).resolve()
            elif link.startswith('@executable_path/'):
                resolved=(original.parent/link[len('@executable_path/'):]).resolve()
            else:
                tail=link[len('@rpath/'):]
                candidates=[original.parent/tail]
                commands=run(['/usr/bin/otool','-l',original])
                for rpath in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset',commands):
                    expanded=rpath.replace('@loader_path',str(original.parent)).replace('@executable_path',str(original.parent))
                    candidates.append(Path(expanded)/tail)
                resolved=next((p.resolve() for p in candidates if p.exists()),None)
                if resolved is None:raise RuntimeError('Cannot resolve '+link+' in '+str(original))
            dependency=bundle_file(resolved)
            replacement='@loader_path/'+os.path.relpath(dependency,target.parent)
            run(['/usr/bin/install_name_tool','-change',link,replacement,target])
            patches.append({'file':str(target.relative_to(APP)),'from':link,'to':replacement})
        elif link.startswith('/') and not link.startswith(('/System/Library/','/usr/lib/')):
            raise RuntimeError('Non-system dependency: '+link)
    if target.suffix=='.dylib':run(['/usr/bin/install_name_tool','-id','@loader_path/'+target.name,target])
    return target

for name in ['ffmpeg','ffprobe','tesseract']:
    bundle_file(OCR/'bin/tesseract' if name=='tesseract' else Path('/opt/homebrew/bin')/name,RES/'tools/bin'/name)

manifest=[]
for name,keg in sorted(kegs.items()):
    folder=NOTICES/'homebrew'/name;folder.mkdir(parents=True,exist_ok=True)
    for p in keg.iterdir():
        if p.is_file() and (p.name.upper().startswith(('LICENSE','COPYING','NOTICE','AUTHORS')) or p.name=='INSTALL_RECEIPT.json'):
            shutil.copy2(p,folder/p.name)
    formula=list((keg/'.brew').glob('*.rb'))
    metadata={'name':name,'version':keg.name}
    if formula:
        shutil.copy2(formula[0],folder/formula[0].name)
        text=formula[0].read_text()
        for key,pattern in [('source_url',r'^  url "([^"]+)"'),('source_sha256',r'^  sha256 "([^"]+)"'),('revision',r'^\s+revision: "([^"]+)"'),('license',r'^  license "([^"]+)"')]:
            match=re.search(pattern,text,re.M)
            if match:metadata[key]=match.group(1)
    manifest.append(metadata)
manifest.append({'name':'tesseract','version':'5.5.3','source_url':'https://github.com/tesseract-ocr/tesseract/archive/refs/tags/5.5.3.tar.gz','source_sha256':'9218e62793116d42a9f6d14cd9348518b27f382096eea3d0f2d1a24616bb5884','license':'Apache-2.0','build_recipe':'scripts/build_ocr.sh','deployment_target':'26.0'})
(NOTICES/'tesseract').mkdir(exist_ok=True)
shutil.copy2(ROOT/'.release-cache/tesseract-5.5.3/LICENSE',NOTICES/'tesseract/LICENSE')
for name in ['LICENSE','NOTICE','LICENSE.html']:
    p=RES/'LibreOffice.app/Contents/Resources'/name
    if p.exists():
        (NOTICES/'LibreOffice').mkdir(exist_ok=True);shutil.copy2(p,NOTICES/'LibreOffice'/name)
shutil.copy2(ROOT/'LICENSE',NOTICES/'Anasing-AGPL-3.0.txt')
shutil.copy2(ROOT/'THIRD_PARTY_NOTICES.md',NOTICES/'THIRD_PARTY_NOTICES.md')
if (ROOT/'docs/THIRD_PARTY_SOURCES.json').exists():shutil.copy2(ROOT/'docs/THIRD_PARTY_SOURCES.json',NOTICES/'THIRD_PARTY_SOURCES.json')
(RES/'bundle-manifest.json').write_text(json.dumps({'python':'3.12.15+20261013','platform':'arm64-apple-macosx26.0','libreoffice':'26.8.1','homebrew_components':manifest,'relocations':patches},indent=2))
# The audit checks every bundled executable and library against the declared minimum.
info=plistlib.loads((CONTENTS/'Info.plist').read_bytes());info['LSMinimumSystemVersion']='26.0'
(CONTENTS/'Info.plist').write_bytes(plistlib.dumps(info))
# Remove cached development signatures; the containing app is re-signed after relocation.
for path in reversed(list(copied.values())):run(['/usr/bin/codesign','--force','--sign','-',path])
run(['/usr/bin/codesign','--force','--sign','-',APP])
print(APP)
print('Bundled %d relocated tool binaries/libraries' % len(copied))
