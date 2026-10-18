#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
import plistlib,tarfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
info=plistlib.loads((root/'Info.plist').read_bytes());version=info.get('AnasingReleaseVersion',info['CFBundleShortVersionString'])
paths=['Sources','landing','engine','tests','scripts','assets','docs','.github','Package.swift','Info.plist','README.md','LICENSE','THIRD_PARTY_NOTICES.md','CONTRIBUTING.md','SECURITY.md','CHANGELOG.md','RELEASING.md','requirements.txt','requirements-release.lock','.gitignore','.gitattributes']
release=root/'release';release.mkdir(exist_ok=True)
def keep(info):
 return None if any(part in {'__pycache__','node_modules','.next','out'} for part in Path(info.name).parts) or info.name.endswith(('.pyc','.DS_Store','.tsbuildinfo')) else info
with tarfile.open(release/('Anasing-'+version+'-source.tar.gz'),'w:gz') as archive:
 for name in paths:
  if not (root/name).exists():raise SystemExit('Missing source file: '+name)
  archive.add(root/name,arcname='Anasing-'+version+'/'+name,filter=keep)
print(release/('Anasing-'+version+'-source.tar.gz'))
