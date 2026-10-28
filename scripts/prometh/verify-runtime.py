#!/usr/bin/env python3
"""Import the real worker dependencies from the prepared, signed app.

Uses the same package-target precedence and isolation as PromethPython. No
models or host installations are consulted. The optional report contains only
module origins, versions and process output, never environment credentials.
"""
from pathlib import Path
import argparse
import concurrent.futures
import json
import os
import subprocess

MODULES={
    'base':['mlx_vlm.server','mlx_vlm.models.flux2','mlx.core','torch','mlx_audio.tts.models.kokoro','onnxruntime','misaki.en','en_core_web_sm'],
    'reader':['trafilatura','lxml.etree'],
    'searxng':['searx','granian','flask'],
    'composio_mcp':['mcp','httpx2','pydantic'],
    'media':['fastvideo','torch','diffusers','mlx.core','transformers','accelerate','imageio_ffmpeg'],
}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    root=args.bundle.resolve()
    python=root/'Contents/Frameworks/NativServerKit.framework/Resources/mlx-vlm-server/python/bin/python3'
    assert python.resolve().is_relative_to(root)
    runtime=root/'Contents/Resources/PromethRuntime'
    def check(name):
        code='''import importlib,json,sys
from pathlib import Path
root=Path(sys.argv[1])
origins={}
for name in json.loads(sys.argv[2]):
    module=importlib.import_module(name)
    file=Path(module.__file__).resolve()
    assert file.is_relative_to(root), f"host import: {name}: {file}"
    origins[name]={'file':str(file),'version':str(getattr(module,'__version__',''))}
if sys.argv[3]=='media':
    from diffusers import AutoencoderKLWan
    from transformers import UMT5EncoderModel
    sys.path.insert(0,str(root/'Contents/Resources/PromethRuntime/media'))
    import bounded_video
    bounded_video.install()
    import imageio_ffmpeg
    assert Path(imageio_ffmpeg.get_ffmpeg_exe()).resolve().is_relative_to(root)
print('__PROMETH_ORIGINS__'+json.dumps(origins))
'''
        env={'HOME':str(Path.home()),'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LANG':'en_US.UTF-8',
             'TMPDIR':'/tmp','PYTHONNOUSERSITE':'1','PYTHONDONTWRITEBYTECODE':'1','HF_HUB_OFFLINE':'1'}
        if name!='base':env['PYTHONPATH']=str(runtime/name/'site-packages')
        command=[str(python),'-B','-c',code,str(root),json.dumps(MODULES[name]),name]
        result=subprocess.run(command,cwd='/tmp',env=env,capture_output=True,text=True,timeout=180)
        marker='__PROMETH_ORIGINS__'
        origins=json.loads(result.stdout.split(marker)[-1]) if marker in result.stdout else {}
        return {'runtime':name,'passed':result.returncode==0,'exit':result.returncode,'command':command,
                'launch_environment':env,'origins':origins,'stdout':result.stdout.split(marker)[0], 'stderr':result.stderr}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        results=list(pool.map(check,MODULES))
    if args.report:args.report.write_text(json.dumps(results,indent=2)+'\n')
    for row in results:
        print(row['runtime'],'PASS' if row['passed'] else 'FAIL')
        if not row['passed']:print(row['stderr'])
        else:
            for module,origin in row['origins'].items():print(module,origin['file'])
    if not all(row['passed'] for row in results):raise SystemExit('Runtime import verification failed')


if __name__=='__main__':main()
