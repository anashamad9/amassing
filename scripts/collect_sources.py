#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Collect upstream source archives and provenance for release alongside the DMG."""
import argparse,concurrent.futures,hashlib,json,plistlib,re,shutil,subprocess,tarfile,time,urllib.parse,urllib.request
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--offline',action='store_true',help='Verify and reuse the previous source manifest and cached archives');args=parser.parse_args()
ROOT=Path(__file__).resolve().parents[1]
RES=ROOT/'dist/portable/Anasing.app/Contents/Resources'
INFO=plistlib.loads((RES.parent/'Info.plist').read_bytes());VERSION=INFO.get('AnasingReleaseVersion',INFO['CFBundleShortVersionString'])
CACHE=ROOT/'.release-cache/corresponding-sources';CACHE.mkdir(parents=True,exist_ok=True)
RELEASE=ROOT/'release';RELEASE.mkdir(exist_ok=True)
manifest=json.loads((RES/'bundle-manifest.json').read_text())
jobs=[]
for component in manifest['homebrew_components']:
    item=dict(component);url=item.get('source_url','')
    if url.endswith('.git') and item.get('revision'):
        name=url.rsplit('/',1)[1][:-4];revision=item['revision']
        url=url[:-4]+'/-/archive/'+revision+'/'+name+'-'+revision+'.tar.gz'
    if url:jobs.append({'name':item['name'],'version':item['version'],'url':url,'expected_sha256':item.get('source_sha256')})
# Package sdists include the Python bindings' corresponding source and build logic.
lock=(ROOT/'requirements-release.lock').read_text()
for name,version in re.findall(r'^([^=\s]+)==([^\s]+)',lock,re.M):
    jobs.append({'name':name,'version':version,'pypi':True})
jobs += [
 {'name':'CPython-standalone-build-recipes','version':'20261013','url':'https://github.com/astral-sh/python-build-standalone/archive/refs/tags/20261013.tar.gz'},
 {'name':'CPython','version':'3.12.15','url':'https://www.python.org/ftp/python/3.12.15/Python-3.12.15.tar.xz'},
 {'name':'MuPDF','version':'1.26.10','url':'https://mupdf.com/downloads/archive/mupdf-1.26.10-source.tar.gz'},
 {'name':'Pandoc','version':'3.9','url':'https://github.com/jgm/pandoc/archive/refs/tags/3.9.tar.gz'},
 {'name':'libheif-wheel','version':'1.20.2','url':'https://github.com/strukturag/libheif/archive/refs/tags/v1.20.2.tar.gz'},
 {'name':'libde265-wheel','version':'1.0.16','url':'https://github.com/strukturag/libde265/archive/refs/tags/v1.0.16.tar.gz'},
 {'name':'x265-wheel','version':'4.1+1-1d117be','url':'https://github.com/Multicorewareinc/x265/archive/1d117be.tar.gz'},
 {'name':'LibreOffice-core','version':'26.8.1.1','url':'https://download.documentfoundation.org/libreoffice/src/26.8.1/libreoffice-26.8.1.1.tar.xz'},
 {'name':'LibreOffice-translations','version':'26.8.1.1','url':'https://download.documentfoundation.org/libreoffice/src/26.8.1/libreoffice-translations-26.8.1.1.tar.xz'},
]

def get(url):
    request=urllib.request.Request(url,headers={'User-Agent':'Anasing-source-bundler/0.6'})
    return urllib.request.urlopen(request,timeout=60)

def fetch(item):
    item=dict(item)
    try:
        if item.get('pypi'):
            with get('https://pypi.org/pypi/'+item['name']+'/'+item['version']+'/json') as response:data=json.load(response)
            sdists=[a for a in data['urls'] if a['packagetype']=='sdist']
            if not sdists:
                if item['name'].lower().replace('_','-')=='pypandoc-binary':
                    item['url']='https://github.com/JessicaTegner/pypandoc/archive/refs/tags/v'+item['version']+'.tar.gz'
                else:raise ValueError('No upstream sdist for this package')
            else:
                item['url']=sdists[0]['url'];item['expected_sha256']=sdists[0]['digests']['sha256']
        url=item['url'];basename=urllib.parse.unquote(url.split('/')[-1].split('?')[0])
        name=item['name']+'-'+item['version']+'--'+basename
        path=CACHE/name
        if not path.exists():
            temporary=path.with_name(path.name+'.part')
            with get(url) as response,temporary.open('wb') as output:shutil.copyfileobj(response,output)
            temporary.replace(path)
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if item.get('expected_sha256') and digest!=item['expected_sha256']:raise ValueError('Upstream source checksum mismatch')
        item.update({'archive':name,'sha256':digest,'status':'downloaded'})
        print('Source: '+item['name']+' '+item['version'],flush=True)
    except Exception as error:
        item.update({'status':'unavailable','error':str(error)})
        print('Source unavailable: '+item['name']+' — '+str(error),flush=True)
    return item

if args.offline:
    results=json.loads((ROOT/'docs/THIRD_PARTY_SOURCES.json').read_text())['sources']
    for item in results:
        path=CACHE/item['archive']
        if item['status']!='downloaded' or not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=item['sha256']:
            raise SystemExit('Cached source verification failed: '+item['name'])
    print('Verified %d cached corresponding-source archives' % len(results),flush=True)
else:
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(fetch,jobs))
recipes=CACHE/'build-recipes';recipes.mkdir(exist_ok=True)
legacy=recipes/'doer-scripts'
if legacy.exists():shutil.rmtree(legacy)
shutil.copytree(RES/'Licenses/homebrew',recipes/'homebrew',dirs_exist_ok=True)
shutil.copytree(ROOT/'scripts',recipes/'anasing-scripts',dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__'))
for filename in ['requirements.txt','requirements-release.lock','LICENSE']:shutil.copy2(ROOT/filename,recipes/filename)
report={'anasing_version':VERSION,'sources':results,'unavailable_sources':[r['name'] for r in results if r['status']!='downloaded'],'note':'Anasing is AGPL-3.0-only; each upstream component retains its own license. Source provenance and build recipes are provided for the actual bundled versions.'}
(ROOT/'docs/THIRD_PARTY_SOURCES.json').write_text(json.dumps(report,indent=2)+'\n')
(CACHE/'SOURCE_MANIFEST.json').write_text(json.dumps(report,indent=2)+'\n')
(CACHE/'SHA256SUMS.txt').write_text('\n'.join(r['sha256']+'  '+r['archive'] for r in results if r['status']=='downloaded')+'\n')
with tarfile.open(RELEASE/('Anasing-'+VERSION+'-third-party-sources.tar.gz'),'w:gz',compresslevel=4) as archive:
    archive.add(CACHE,arcname='Anasing-third-party-sources',filter=lambda info:None if info.name.endswith('.part') else info)
print('Source archive prepared; unavailable upstream sources: '+str(len(report['unavailable_sources'])))
