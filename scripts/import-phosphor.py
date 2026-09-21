#!/usr/bin/env python3
"""Rebuild native vector assets from the same pinned package as desktop (MIT)."""
import hashlib, io, json, re, tarfile, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
URL = 'https://registry.npmjs.org/phosphor-svelte/-/phosphor-svelte-3.1.0.tgz'
# The lockfile version is deliberate. Review artwork changes before updating it.
blob = urllib.request.urlopen(URL).read()
assert hashlib.sha256(blob).hexdigest() == '308250185e5ad1439f65d0929ae718e6f026b6fb8f176e2439743abbd7aee16d', 'Pinned package checksum mismatch'
archive = tarfile.open(fileobj=io.BytesIO(blob), mode='r:gz')
available = {Path(n).stem for n in archive.getnames() if n.startswith('package/lib/') and n.endswith('.svelte')}
sources = '\n'.join(p.read_text() for p in (ROOT/'Moku').rglob('*.swift'))
used = {v.removesuffix('.fill') for v in re.findall(r'"([A-Z][A-Za-z]*(?:\.fill)?)"', sources)} & available
assets = ROOT/'Moku/Resources/Assets.xcassets/Phosphor'
assets.mkdir(parents=True, exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info': {'author':'xcode', 'version':1}}, indent=2)+'\n')
for name in sorted(used):
    source = archive.extractfile('package/lib/'+name+'.svelte').read().decode()
    for weight in (('regular','light','fill','bold') if name in ('MagnifyingGlass', 'DownloadSimple') else ('regular','light','fill')):
        match = re.search(r'(?:if|else if) weight === "'+weight+r'"}\s*(.*?)\s*{:', source, re.S)
        if not match: raise ValueError((name, weight))
        folder = assets/(name+'-'+weight+'.imageset')
        folder.mkdir(exist_ok=True)
        (folder/'icon.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" fill="#000000">'+match.group(1)+'</svg>\n')
        (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'icon.svg','idiom':'universal'}], 'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}}, indent=2)+'\n')
(ROOT/'Moku/Resources/Phosphor-LICENSE.txt').write_bytes(archive.extractfile('package/LICENSE').read())
(ROOT/'Moku/Shared/Theme/phosphor-manifest.json').write_text(json.dumps({'package':'phosphor-svelte','version':'3.1.0','sha256':hashlib.sha256(blob).hexdigest(),'icons':sorted(used),'weights':['regular','light','fill'],'additionalWeights':{'MagnifyingGlass':['bold'],'DownloadSimple':['bold']}}, indent=2)+'\n')
print(f'Imported {len(used)} icon names, regular/light/fill; SHA256 {hashlib.sha256(blob).hexdigest()}')
