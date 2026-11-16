#!/usr/bin/env python3
"""One Library-ready PNG of real, exact-commit Web frames. Never synthesizes game pixels."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args],text=True).strip()
if git('status','--porcelain'):
    raise SystemExit('Commit source changes and run the full exact-commit Web check first.')
sha=git('rev-parse','HEAD')
build=ROOT/'build'
source=json.loads((build/'web/build-source.json').read_text())
report=json.loads((build/'web-check.json').read_text())
pck_hash=hashlib.sha256((build/'web/index.pck').read_bytes()).hexdigest()
assert source['commit']==sha and source['source_clean'] and report['status']=='PASS'
assert pck_hash==source['files']['index.pck']==report['pck_sha256']
views={tuple(view['viewport']):view for view in report['workshop']}
for view in views.values():
    for name,digest in view['screenshot_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,('Changed screenshot',name)
        assert (ROOT/name).stat().st_mtime>(build/'web/index.pck').stat().st_mtime
atlas=Image.open(ROOT/'art/workshop_font.png').convert('RGBA')
glyphs={}
for match in re.finditer(r'char id=(\d+) x=(\d+) y=(\d+) width=(\d+) height=(\d+) xoffset=0 yoffset=1 xadvance=(\d+)',(ROOT/'art/workshop_font.fnt').read_text()):
    code,x,y,w,h,advance=map(int,match.groups())
    glyphs[chr(code)]=(atlas.crop((x,y,x+w,y+h)),advance)
canvas=Image.new('RGB',(1668,1640),'#102733')
draw=ImageDraw.Draw(canvas)
def label(text,x,y,scale=2,color='#f4e3ba'):
    for char in text:
        glyph,advance=glyphs[char]
        glyph=glyph.resize((glyph.width*scale,glyph.height*scale),Image.Resampling.NEAREST)
        canvas.paste(color,(x,y,x+glyph.width,y+glyph.height),glyph.getchannel('A'))
        x+=advance*scale

def put(name,x,y):
    image=Image.open(ROOT/name).convert('RGB')
    draw.rectangle((x-1,y-1,x+image.width,y+image.height),outline='#617d83')
    canvas.paste(image,(x,y))

label('STACK ATTACK · МАСТЕРСКАЯ',24,18,3)
label('WEB / CHROMIUM · QA СЦЕНА · COMMIT '+sha[:12],24,62,2,'#8dc6ac')
portrait=views[(390,844)]
fold=views[(768,1004)]
landscape=views[(844,390)]
label('ПОРТРЕТ',24,90);put(portrait['screenshots'][1],24,116)
label('FOLD / VIEWPORT',438,90);put(fold['screenshots'][1],438,116)
label('МЕНЮ / AI',1230,90);put(portrait['screenshots'][0],1230,116)
label('АЛЬБОМ',24,1148);put(landscape['screenshots'][1],24,1180)
label('ГЕРОЙ · РЕАЛЬНЫЕ КАДРЫ X4',902,1148)
poses=report['sprite_poses'][0]['poses']
for index,equipped in enumerate([True,False]):
    pose=next(p for p in poses if p['pose']=='idle' and p['facing']==1 and p['boots_equipped']==equipped)
    image=Image.open(ROOT/pose['screenshot']).convert('RGB').crop(pose['crop_bounds'])
    assert hashlib.sha256(image.tobytes()).hexdigest()==pose['crop_sha256']
    image=image.resize((image.width*4,image.height*4),Image.Resampling.NEAREST)
    x=902+index*360
    label('БОТИНКИ-РАКЕТЫ' if equipped else 'ОБЫЧНАЯ ОБУВЬ',x,1200)
    canvas.paste(image,(x,1236))
label('БОТИНКИ-РАКЕТЫ · ДОПОЛНИТЕЛЬНЫЙ ПРЫЖОК В ВОЗДУХЕ',24,1596,2,'#8dc6ac')
out=build/'showcase'
out.mkdir(exist_ok=True)
path=out/f'stack-attack-workshop-{sha[:12]}.png'
canvas.save(path)
manifest={'commit':sha,'pck_sha256':pck_hash,'origin':'Web / Chromium / SwiftShader','library_deliverable':str(path),
          'image_size':canvas.size,'size_bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
          'frames':{name:digest for v in views.values() for name,digest in v['screenshot_sha256'].items()},
          'compositing':'Unscaled original views plus integer 4x native frame crops; captions outside the game.'}
(path.with_suffix('.json')).write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(manifest,ensure_ascii=False,indent=2))
