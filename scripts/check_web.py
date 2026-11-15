#!/usr/bin/env python3
"""End-to-end checks against the actual exported game; debug fixtures require ?qa=1."""
import functools
import argparse
import base64
from datetime import datetime
import hashlib
import http.server
import html
import io
import json
import os
from pathlib import Path
import sys
import threading
from playwright.sync_api import sync_playwright
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
group = parser.add_mutually_exclusive_group()
group.add_argument('--workshop-only', action='store_true', help='Capture and validate the workshop visual slice')
group.add_argument('--sprites-only', action='store_true', help='Run only frozen-pose rendered sprite regressions')
group.add_argument('--ui-only', action='store_true', help='Run demo isolation and vibration UI regressions only')
group.add_argument('--game-over-only', action='store_true', help='Run score-only result screen regressions and capture screenshots')
group.add_argument('--statistics-only', action='store_true', help='Check Statistics and capture its rendered overview and history')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
SHOTS = BUILD / 'screenshots'
SHOTS.mkdir(exist_ok=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(BUILD / 'web')))
threading.Thread(target=server.serve_forever, daemon=True).start()
URL = f'http://127.0.0.1:{server.server_port}/index.html?qa=1'
AUDIO_PROBE = '''
(() => {
 const connect = AudioNode.prototype.connect;
 AudioNode.prototype.connect = function(destination, ...args) {
   if(destination === this.context.destination && !this.__qaAnalyser) {
     const analyser = this.context.createAnalyser(); analyser.fftSize = 2048;
     analyser.__qaAnalyser = true;
     connect.call(this, analyser); connect.call(analyser, destination);
     (window.qaAudioAnalysers ||= []).push(analyser); window.qaAudioAnalyser = analyser;
     return destination;
   }
   return connect.call(this, destination, ...args);
 };
})();
'''
results = []
all_errors = []
all_failed_requests = []


def state(page):
    return page.evaluate('window.stackAttackState')


def wait_screen(page, name):
    page.wait_for_function('value => window.stackAttackState?.screen === value', arg=name, timeout=15000)
    page.wait_for_timeout(150)


def point(page, rect):
    snapshot = state(page)
    canvas = page.locator('canvas').bounding_box()
    x, y, width, height = rect
    return (canvas['x'] + (x + width / 2) * canvas['width'] / snapshot['viewport'][0],
            canvas['y'] + (y + height / 2) * canvas['height'] / snapshot['viewport'][1])


def button(page, name, touch=False):
    snapshot = state(page)
    rect = snapshot['buttons'][name]
    x, y = point(page, rect)
    bounds = page.locator('canvas').bounding_box()
    assert 0 <= x < bounds['width'] and 0 <= y < bounds['height'], ('Button is outside the canvas', name, rect)
    if touch:
        page.touchscreen.tap(x, y)
    else:
        page.mouse.click(x, y)
    page.wait_for_timeout(160)


def scenario(page, name):
    page.evaluate('value => window.stackAttackQARequest = {scenario:value}', name)
    page.wait_for_timeout(200)


def slider(page, name, value):
    rect = state(page)['sliders'][name]
    x, y = point(page, rect)
    page.mouse.click(x, y)
    page.keyboard.press('Home')
    for _ in range(round(value / .05)):
        page.keyboard.press('ArrowRight')
    page.wait_for_function('expected => Math.abs(window.stackAttackState.profile[expected.name] - expected.value) < 0.001',
                           arg={'name': name, 'value': value})


def screenshot(page, name):
    path = SHOTS / name
    page.screenshot(path=str(path))
    return str(path.relative_to(ROOT))


def rms(page):
    return page.evaluate('''() => {
      const analysers = window.qaAudioAnalysers || []; if(!analysers.length) return -1;
      return Math.max(...analysers.map(analyser => {
        const data = new Float32Array(analyser.fftSize); analyser.getFloatTimeDomainData(data);
        return Math.sqrt(data.reduce((sum,value) => sum + value*value, 0)/data.length);
      }));
    }''')


def tab(page, backwards=False):
    previous = state(page)['panel']['focus']
    page.keyboard.press('Shift+Tab' if backwards else 'Tab')
    page.wait_for_function('previous => window.stackAttackState?.panel?.focus !== previous', arg=previous, timeout=5000)
    return state(page)['panel']['focus']


def fixed_panel(page, touch=True):
    snapshot = state(page)
    panel = snapshot['panel']
    width, height = snapshot['viewport']
    assert panel['scroll_containers'] == 0, 'Menus must not have scrolling containers'
    for item in [{'rect':panel['rect']}, *panel['items']]:
        x, y, w, h = item['rect']
        assert x >= -1 and y >= -1 and x+w <= width+1 and y+h <= height+1, ('Clipped menu content', snapshot['screen'], item)
    focusable = [item for item in panel['items'] if item['focusable']]
    assert panel['focus'] in [item['name'] for item in focusable]
    for item in focusable:
        if item['kind'] == 'Button':
            assert item['rect'][3] >= 48, ('Undersized menu button', item)
    for index, first in enumerate(focusable):
        ax, ay, aw, ah = first['rect']
        for second in focusable[index+1:]:
            bx, by, bw, bh = second['rect']
            assert min(ax+aw, bx+bw)-max(ax,bx) <= 1 or min(ay+ah,by+bh)-max(ay,by) <= 1, ('Overlapping menu controls', first, second)
    # Start over the heading, away from buttons and sliders.
    x, y, w, h = panel['rect']
    px, py = point(page, [x+16, y+12, 1, 1])
    page.mouse.move(px, py)
    page.mouse.wheel(0, 600)
    page.wait_for_timeout(120)
    page.mouse.wheel(0, -600)
    if touch:
        cdp = page.context.new_cdp_session(page)
        cdp.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[{'x':px, 'y':py, 'id':1}]})
        for offset in [10, 25, 40, 60]:
            cdp.send('Input.dispatchTouchEvent', {'type':'touchMove', 'touchPoints':[{'x':px, 'y':py+offset, 'id':1}]})
        cdp.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
        cdp.detach()
    page.wait_for_timeout(160)
    after = state(page)
    assert after['screen'] == snapshot['screen']
    assert after['panel']['rect'] == panel['rect'] and after['panel']['items'] == panel['items'], 'Wheel/swipe moved menu content'
    assert page.evaluate('[window.scrollX, window.scrollY]') == [0, 0]
    # Tab and Shift+Tab must wrap within the visible panel.
    names = {item['name'] for item in focusable}
    visited = set()
    start = after['panel']['focus']
    for _ in focusable:
        if len(focusable) == 1:
            page.keyboard.press('Tab')
            page.wait_for_timeout(180)
        else:
            tab(page)
        visited.add(state(page)['panel']['focus'])
    assert visited == names and state(page)['panel']['focus'] == start, ('Broken focus cycle', visited, names)
    if len(focusable) > 1:
        tab(page, True)
        tab(page)
    assert state(page)['panel']['focus'] == start


def sprite_comparison(browser, check):
    width, height = check['viewport']
    commit = json.loads((BUILD/'web/build-source.json').read_text())['commit']
    cells = []
    for pose, label in [('idle','Покой'), ('walk_stride','Шаг'), ('walk_recover','Возврат'), ('jump','Прыжок'), ('push','Толкание')]:
        for facing, direction in [(1,'Вправо'), (-1,'Влево')]:
            sample = next(p for p in check['poses'] if p['pose'] == pose and p['facing'] == facing and p['magnet'])
            left, top, right, bottom = sample['crop_bounds']
            raw = (ROOT/sample['screenshot']).read_bytes()
            src = 'data:image/png;base64,' + base64.b64encode(raw).decode()
            cells.append(f'<section><h2>{label} · {direction}</h2><div class="crop" style="width:{(right-left)*4}px;height:{(bottom-top)*4}px">'
                         f'<img src="{src}" style="width:{width*4}px;height:{height*4}px;left:{-left*4}px;top:{-top*4}px"></div></section>')
    page = browser.new_page(viewport={'width':700,'height':400}, device_scale_factor=1)
    page.set_content('<html lang="ru"><meta charset="utf-8"><style>'
        'body{margin:0;padding:24px;background:#172333;color:#f4e3ba;font:16px sans-serif}h1{font-size:23px;margin:0 0 10px}'
        'p{color:#9eafa5;font-size:13px;margin:6px 0}main{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-top:18px}'
        'h2{font-size:16px;margin:0 0 8px}section{min-width:0}.crop{position:relative;overflow:hidden;outline:1px solid #617b7b}'
        'img{position:absolute;max-width:none;image-rendering:pixelated}</style>'
        f'<h1>Одна позиция · {width}×{height}</h1><p>Web / Chromium · реальные кадры, увеличение 4×</p>'
        f'<p>Позиция коллизии: (4.3, 10.12) · commit {html.escape(commit[:12])}</p>'
        '<p>Одинаковая область кадра для всех направлений и фаз.</p><main>'+''.join(cells)+'</main></html>')
    page.wait_for_function('Array.from(document.images).every(image => image.complete && image.naturalWidth > 0)')
    path = SHOTS/f'hero-comparison-{width}x{height}.png'
    page.screenshot(path=str(path), full_page=True)
    page.close()
    return str(path.relative_to(ROOT))


def sprite_poses(browser):
    checks = []
    failures = []
    source = Image.open(ROOT / 'art/hero_idle.png').convert('RGBA')
    marker = source.getpixel((9, 23))[:3]  # Symmetric scarf band, fixed to the torso in both frames.
    alpha = {}
    for frame in ['idle','walk','jump','push','idle_bare','walk_bare','jump_bare','push_bare']:
        with Image.open(ROOT / f'art/hero_{frame}.png') as image:
            alpha[frame] = {'canvas':image.size, 'used':image.getbbox()}
            assert image.size == (32,48) and image.getpixel((0,0))[3] == 0, 'Workshop sprite canvas/padding changed; recheck reflection axis'
            band = [x for y in [23,24] for x in range(image.width) if image.getpixel((x,y)) == (*marker,255)]
            assert band and (min(band)+max(band)+1)/2 == image.width/2, 'Torso band is not centered in the sprite canvas'
    for dimensions in [(390,844), (844,390)]:
        context = browser.new_context(viewport={'width':dimensions[0], 'height':dimensions[1]}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page, 'menu')
        button(page, 'play')
        wait_screen(page, 'playing')
        poses = []
        for pose,magnet in [(p,m) for m in [True,False] for p in ['idle','walk_stride','walk_recover','jump','push']]:
            for facing in [1, -1]:
                page.evaluate('value => window.stackAttackQARequest = value', {'scenario':'hero_pose', 'pose':pose, 'facing':facing, 'magnet':magnet})
                page.wait_for_function('value => window.stackAttackState.hero_pose && window.stackAttackState.facing === value', arg=facing)
                page.wait_for_timeout(180)
                snapshot = state(page)
                frame = {'walk_stride':'walk','jump':'jump','push':'push'}.get(pose,'idle')
                assert snapshot['hero_frame'] == frame
                path = SHOTS / f'hero-{pose}-{"magnet" if magnet else "bare"}-{"right" if facing == 1 else "left"}-{dimensions[0]}x{dimensions[1]}.png'
                raw = page.screenshot(path=str(path))
                image = Image.open(io.BytesIO(raw)).convert('RGB')
                fx, fy, fw, fh = snapshot['field']
                cell = fw / snapshot['columns']
                scale = page.locator('canvas').bounding_box()['width'] / snapshot['viewport'][0]
                px, py = snapshot['player']
                left, top = round((fx+(px-.5)*cell)*scale), round((fy+(py-.1)*cell)*scale)
                right, bottom = round((fx+(px+1.5)*cell)*scale), round((fy+(py+1)*cell)*scale)
                points = [(x,y) for y in range(top,bottom) for x in range(left,right) if image.getpixel((x,y)) == marker]
                assert points, ('Torso marker was not rendered', dimensions, pose, facing)
                xs, ys = zip(*points)
                center = (min(xs)+max(xs)+1)/2
                expected_center = (fx+(px+snapshot['player_size'][0]/2)*cell)*scale
                crop_hash = hashlib.sha256(image.crop((left,top,right,bottom)).tobytes()).hexdigest()
                red = sum(image.getpixel((x,y)) == (215,67,56) for y in range(top,bottom) for x in range(left,right))
                assert (red > 0) == magnet, ('Cosmetic magnet is not readable/isolated',dimensions,pose,facing,magnet,red)
                assert snapshot['cosmetic_magnet'] == magnet
                poses.append({'pose':pose,'magnet':magnet,'magnet_pixels':red,'facing':facing,'frame':frame,'player':snapshot['player'],
                              'torso_center_x':center,'marker_bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1],
                              'expected_center_x':expected_center,'crop_sha256':crop_hash,'crop_bounds':[left,top,right,bottom],
                              'screenshot':str(path.relative_to(ROOT))})
                assert abs(center-expected_center) <= max(1,cell*scale/24), ('Torso is not centered on the collision body', dimensions, pose, facing, center, expected_center)
        fixed_player = poses[0]['player']
        for sample in poses:
            assert sample['player'] == fixed_player, 'Direction or animation changed the fixture collision position'
            assert sample['marker_bounds'][1::2] == poses[0]['marker_bounds'][1::2], 'Turning or animation moved the torso vertically'
            if abs(sample['torso_center_x']-poses[0]['torso_center_x']) > 1:
                failures.append({'viewport':dimensions, 'pose':sample['pose'], 'facing':sample['facing'],
                                 'drift_pixels':sample['torso_center_x']-poses[0]['torso_center_x']})
        for facing in [1,-1]:
            samples = {sample['pose']:sample for sample in poses if sample['facing'] == facing and sample['magnet']}
            assert samples['idle']['crop_sha256'] != samples['walk_stride']['crop_sha256'], 'Walking did not render its second animation frame'
            assert samples['idle']['crop_sha256'] == samples['walk_recover']['crop_sha256'], 'Walking recovery did not return to the centered idle frame'
        assert not errors, errors
        checks.append({'viewport':list(dimensions),'alpha':alpha,'poses':poses})
        print('SPRITE_POSES', json.dumps(checks[-1]), flush=True)
        context.close()
    assert not failures, ('Turning or animation displaced the rendered torso', failures)
    for check in checks:
        check['comparison'] = sprite_comparison(browser, check)
    return checks


def score_only_result(page):
    snapshot = state(page)
    assert snapshot['screen'] == 'over'
    labels = [item['text'] for item in snapshot['panel']['items'] if item['kind'] == 'Label']
    assert labels == ['Смена окончена', f"Счёт: {snapshot['score']}"], ('Unexpected game-over details', labels)
    assert {'again','home'} <= snapshot['buttons'].keys()
    label = next(item for item in snapshot['panel']['items'] if item['name'] == 'result_score')
    assert label['alignment'] == 1
    image = Image.open(io.BytesIO(page.screenshot())).convert('RGB')
    scale = page.locator('canvas').bounding_box()['width']/snapshot['viewport'][0]
    x,y,w,h = label['rect']
    bounds = (round(x*scale),round(y*scale),round((x+w)*scale),round((y+h)*scale))
    points = [(px,py) for py in range(bounds[1],bounds[3]) for px in range(bounds[0],bounds[2])
              if max(abs(a-b) for a,b in zip(image.getpixel((px,py)),(215,164,90))) <= 5]
    assert points, 'Score text did not render'
    center = (min(p[0] for p in points)+max(p[0] for p in points)+1)/2
    assert abs(center-image.width/2) <= max(3,scale*2), ('Score pixels are not centered',snapshot['score'],center,image.width/2)
    return center


def readable_action_button(page, name):
    snapshot = state(page)
    item = next(item for item in snapshot['panel']['items'] if item['name'] == name)
    for key in ['normal','hover','pressed','hover_pressed','disabled']:
        assert .7 <= item['styles'][key]['alpha'] <= .9 and item['styles'][key]['border'] == 1
    image = Image.open(io.BytesIO(page.screenshot())).convert('RGB')
    scale = page.locator('canvas').bounding_box()['width']/snapshot['viewport'][0]
    x,y,w,h = item['rect']
    region = image.crop((round((x+3)*scale),round((y+3)*scale),round((x+w-3)*scale),round((y+h-3)*scale)))
    raw = region.tobytes()
    bright = sum(r>150 and g>120 for r,g in zip(raw[0::3],raw[1::3]))
    assert bright > 20, ('Button text is not visible',name)
    padding = image.getpixel((round((x+4)*scale),round((y+h/2)*scale)))
    assert max(padding) < 110, ('Button backing does not protect text from the background',name,padding)


def uniform_action_buttons(browser, viewports=((390,844),(844,390),(768,1004))):
    checks = []
    for width,height in viewports:
        context = browser.new_context(viewport={'width':width,'height':height}, has_touch=True, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror',lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page,'menu')
        page.evaluate('window.stackAttackQARequest={scenario:"result_preview",score:200}')
        wait_screen(page,'over')
        reference = next(item['styles'] for item in state(page)['panel']['items'] if item['name'] == 'again')
        button(page,'home',True)
        wait_screen(page,'menu')
        screens = []
        shots = []

        def inspect_actions():
            before = state(page)
            names = [item['name'] for item in before['panel']['items'] if item['kind'] == 'Button']
            for name in names:
                item = next(item for item in state(page)['panel']['items'] if item['name'] == name)
                assert item['styles'] == reference, ('Action style diverged from game over',before['screen'],name)
                readable_action_button(page,name)
                for _ in before['panel']['items']:
                    if state(page)['panel']['focus'] == name:
                        break
                    tab(page)
                assert state(page)['panel']['focus'] == name
                readable_action_button(page,name)
                if name == 'vibration':
                    # A toggle's latched mode is also its pressed appearance.
                    # Exercise real on/off taps rather than treating it as a navigation action.
                    for expected in [not before['profile']['vibration'],before['profile']['vibration']]:
                        button(page,name,True)
                        page.wait_for_function('value => window.stackAttackState.profile.vibration === value',arg=expected)
                        readable_action_button(page,name)
                    continue
                x,y = point(page,state(page)['buttons'][name])
                page.mouse.move(x,y)
                page.wait_for_function('name => [2,4].includes(window.stackAttackState.button_modes[name])',arg=name)
                readable_action_button(page,name)
                page.mouse.down()
                try:
                    page.wait_for_function('name => [1,4].includes(window.stackAttackState.button_modes[name])',arg=name,timeout=5000)
                except Exception:
                    print('BUTTON_STATE_FAILURE',json.dumps({'viewport':[width,height],'screen':before['screen'],'button':name,'state':state(page)}),flush=True)
                    screenshot(page,f'button-state-failure-{width}x{height}.png')
                    raise
                readable_action_button(page,name)
                # Cancel outside: inspect pressed pixels without activating navigation/toggles.
                x,y,_,_ = state(page)['panel']['rect']
                page.mouse.move(*point(page,[x+16,y+12,1,1]))
                page.mouse.up()
                page.wait_for_timeout(150)
                after = state(page)
                assert after['screen'] == before['screen'] and after['profile'] == before['profile']
            fixed_panel(page)
            android_qa = before['screen'] == 'settings' and before['profile']['vibration_visible']
            tag = 'android-settings-web-qa' if android_qa else before['screen']
            screens.append({'screen':before['screen'],'android_qa':android_qa,'buttons':names,'rendered_focus_hover_pressed':'PASS','matches_game_over_all_styles':'PASS'})
            shots.append(screenshot(page,f'unified-{tag}-{width}x{height}.png'))

        inspect_actions()
        button(page,'statistics',True)
        wait_screen(page,'statistics')
        inspect_actions()
        button(page,'back',True)
        wait_screen(page,'menu')
        button(page,'settings',True)
        wait_screen(page,'settings')
        inspect_actions()
        scenario(page,'android_settings')
        wait_screen(page,'settings')
        inspect_actions()
        button(page,'back',True)
        wait_screen(page,'menu')
        button(page,'play',True)
        wait_screen(page,'playing')
        button(page,'pause',True)
        wait_screen(page,'paused')
        inspect_actions()
        button(page,'resume',True)
        wait_screen(page,'playing')
        scenario(page,'crush')
        wait_screen(page,'over')
        inspect_actions()
        button(page,'again',True)
        wait_screen(page,'playing')
        assert state(page)['score'] == 0
        assert not errors, errors
        checks.append({'viewport':[width,height],'screens':screens,'screenshots':shots})
        print('UNIFIED_BUTTONS',json.dumps(checks[-1]),flush=True)
        context.close()
    return checks


def game_over_screens(browser):
    checks = []
    for dimensions in [(390,844),(844,390),(768,1004)]:
        context = browser.new_context(viewport={'width':dimensions[0],'height':dimensions[1]}, has_touch=True, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page, 'menu')
        button(page, 'play', True)
        wait_screen(page, 'playing')
        scenario(page, 'chain')
        page.wait_for_function('window.stackAttackState.score === 200 && window.stackAttackState.state === "playing"')
        shots = []
        for reason, fixture in [('crushed','crush'),('overflow','overflow')]:
            scenario(page, fixture)
            wait_screen(page, 'over')
            score_only_result(page)
            snapshot = state(page)
            assert snapshot['loss_reason'] == reason
            assert snapshot['lines'] == (2 if reason == 'crushed' else 0)
            fixed_panel(page)
            shots.append(screenshot(page, f'game-over-{reason}-{dimensions[0]}x{dimensions[1]}.png'))
            button(page, 'again' if reason == 'crushed' else 'home', True)
            wait_screen(page, 'playing' if reason == 'crushed' else 'menu')
        centers = []
        for score in [0,200,100000000]:
            page.evaluate('value => window.stackAttackQARequest={scenario:"result_preview",score:value}', score)
            wait_screen(page, 'over')
            page.wait_for_function('value => window.stackAttackState.score === value',arg=score)
            before = state(page)['demo']['ticks']
            page.wait_for_timeout(220)
            assert state(page)['demo']['ticks'] > before, 'Readability stress background must actually move'
            centers.append(score_only_result(page))
            fixed_panel(page)
            readable_action_button(page,'again')
            readable_action_button(page,'home')
            shots.append(screenshot(page, f'result-centered-{score}-{dimensions[0]}x{dimensions[1]}.png'))
        for name in ['again','home']:
            page.evaluate('window.stackAttackQARequest={scenario:"result_preview",score:200}')
            page.wait_for_function('window.stackAttackState.score === 200')
            page.wait_for_timeout(180)
            while state(page)['panel']['focus'] != name:
                tab(page)
            readable_action_button(page,name)
            x,y = point(page,state(page)['buttons'][name])
            page.mouse.move(x,y)
            page.wait_for_timeout(180)
            readable_action_button(page,name)
            page.mouse.down()
            page.wait_for_function('name => [1,4].includes(window.stackAttackState.button_modes[name])',arg=name)
            readable_action_button(page,name)
            shots.append(screenshot(page,f'result-{name}-pressed-{dimensions[0]}x{dimensions[1]}.png'))
            page.mouse.up()
            wait_screen(page,'playing' if name == 'again' else 'menu')
            if name == 'again':
                assert state(page)['score'] == 0
                button(page,'pause',True)
                wait_screen(page,'paused')
                button(page,'home',True)
                wait_screen(page,'menu')
        assert not errors, errors
        checks.append({'viewport':list(dimensions),'both_loss_screens':'PASS','model_details_retained':'PASS',
                       'touch_focus_no_scroll':'PASS','restart_and_home':'PASS','score_pixels_centered':'PASS',
                       'button_states_readable':'PASS','moving_demo_background':'PASS','score_centers':centers,'screenshots':shots})
        context.close()
    print('GAME_OVER',json.dumps(checks),flush=True)
    return checks


def ui_batch_checks(browser):
    context = browser.new_context(viewport={'width':390,'height':844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    first = state(page)
    labels = [item['text'] for item in first['panel']['items'] if item['kind'] == 'Label']
    assert labels == ['Stack Attack'], ('Unexpected menu description/subtitle', labels)
    assert first['demo']['active'] and first['demo']['separate_model']
    initial_statistics = personal_statistics(first)
    positions = []
    for _ in range(16):
        page.wait_for_timeout(250)
        positions.append(state(page)['demo']['player'][0])
    moving = state(page)
    assert max(positions)-min(positions) > .5 and moving['demo']['jumps'] > 0 and moving['demo']['drops'] > 0
    assert moving['ticks'] == first['ticks'] == 0 and moving['session'] == 0 and moving['score'] == 0
    assert personal_statistics(moving) == initial_statistics
    menu_shot = screenshot(page, 'live-menu-390x844.png')
    for _ in range(3):
        button(page, 'settings', True)
        wait_screen(page, 'settings')
        assert 'sound_test' not in state(page)['buttons']
        assert not state(page)['profile']['vibration_visible']
        button(page, 'back', True)
        wait_screen(page, 'menu')
    before_loss = state(page)
    scenario(page, 'demo_crush')
    page.wait_for_function('value => window.stackAttackState.demo.losses > value', arg=before_loss['demo']['losses'])
    page.wait_for_function('value => window.stackAttackState.demo.rounds > value', arg=before_loss['demo']['rounds'])
    after_loss = state(page)
    assert after_loss['session'] == 0 and after_loss['ticks'] == 0
    assert personal_statistics(after_loss) == initial_statistics
    button(page, 'play', True)
    wait_screen(page, 'playing')
    stopped_demo = state(page)['demo']['ticks']
    page.wait_for_timeout(350)
    assert state(page)['ticks'] > 0 and state(page)['demo']['ticks'] == stopped_demo
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    paused = state(page)
    button(page, 'home', True)
    wait_screen(page, 'menu')
    page.wait_for_timeout(350)
    assert state(page)['ticks'] == paused['ticks'] and state(page)['player'] == paused['player']
    assert state(page)['demo']['ticks'] > stopped_demo and personal_statistics(state(page)) == initial_statistics
    # Exercise the exact Android-only control in an explicit Web QA fixture.
    # This verifies pixels/input, not Android hardware or haptic strength.
    scenario(page, 'android_settings')
    wait_screen(page, 'settings')
    assert state(page)['profile']['vibration_visible']
    fixed_panel(page)
    button(page, 'vibration', True)
    page.wait_for_timeout(150)
    assert not state(page)['profile']['vibration']
    off = page.screenshot()
    button(page, 'vibration', True)
    page.wait_for_timeout(150)
    enabled = state(page)
    assert enabled['profile']['vibration']
    assert enabled['vibration_styles']['focus'] == 0
    assert all(.7 <= value <= .9 for key,value in enabled['vibration_styles'].items() if key != 'focus')
    toggle = next(item for item in enabled['panel']['items'] if item['name'] == 'vibration')
    assert toggle['text'] == 'Виброотклик: Вкл'
    on = page.screenshot()
    x,y,w,h = enabled['buttons']['vibration']
    a,b = point(page,[x+2,y+8,1,1]),point(page,[x+6,y+h-8,1,1])
    bounds = (round(a[0]),round(a[1]),round(b[0]),round(b[1]))
    # The shared translucent padding must remain stable immediately after toggling,
    # while the control still owns focus/hover; black pressed fallbacks fail here.
    assert Image.open(io.BytesIO(off)).crop(bounds).tobytes() == Image.open(io.BytesIO(on)).crop(bounds).tobytes()
    toggle_shot = screenshot(page, 'android-vibration-on-web-qa-390x844.png')
    tab(page)
    blurred = page.screenshot()
    assert Image.open(io.BytesIO(on)).crop(bounds).tobytes() == Image.open(io.BytesIO(blurred)).crop(bounds).tobytes()
    page.reload()
    wait_screen(page, 'menu')
    assert personal_statistics(state(page)) == initial_statistics and state(page)['profile']['vibration']
    assert not errors, errors
    context.close()
    result = {'demo_motion':'PASS','real_loss_restart':'PASS','personal_game_and_statistics_isolation':'PASS',
              'repeated_settings':'PASS','vibration_pixels_and_focus':'PASS','web_vibration_hidden':'PASS',
              'screenshots':[menu_shot,toggle_shot]}
    print('UI_BATCH',json.dumps(result),flush=True)
    return result


def personal_statistics(snapshot):
    profile = snapshot['profile']
    return {name: profile[name] for name in ('matches', 'statistics', 'records')}


def statistics_items(page):
    return {item['name']: item['text'] for item in state(page)['panel']['items']}


def focus_button(page, name):
    panel = state(page)['panel']
    assert name in {item['name'] for item in panel['items'] if item['focusable']}
    for _ in panel['items']:
        if state(page)['panel']['focus'] == name:
            return
        tab(page)
    raise AssertionError(f'No keyboard focus for {name}')


def wait_expanded_match(page, index):
    page.wait_for_function('index => window.stackAttackState.statistics_view?.expanded_match === index', arg=index)


def visible_match_indexes(page):
    return sorted(int(name.removeprefix('match_')) for name in state(page)['buttons'] if name.startswith('match_'))


def statistics_preview(browser):
    context = browser.new_context(viewport={'width':390, 'height':844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    original = personal_statistics(state(page))
    scenario(page, 'statistics_menu')
    wait_screen(page, 'statistics')
    assert state(page)['statistics_view']['preview']
    shots = [screenshot(page, 'statistics-overview-390x844.png')]
    collapsed_count = len(visible_match_indexes(page))
    button(page, 'match_0', True)
    wait_expanded_match(page, 0)
    shots.append(screenshot(page, 'statistics-history-390x844.png'))
    print('STATISTICS_SCREENSHOTS', json.dumps(shots), flush=True)
    assert collapsed_count >= 4, 'Tall portrait leaves room for multiple visible matches'
    fixed_panel(page)
    assert personal_statistics(state(page)) == original

    for width, height in [(320,568), (568,320), (844,390), (390,844)]:
        page.set_viewport_size({'width':width, 'height':height})
        page.wait_for_timeout(400)
        assert state(page)['statistics_view']['expanded_match'] == 0
        assert state(page)['panel']['focus'] == 'match_0', 'Resize lost expanded match focus'
        assert 'match_0_duration' in statistics_items(page)
        fixed_panel(page)
        if (width, height) == (568, 320):
            shots.append(screenshot(page, 'statistics-history-568x320.png'))

    page.keyboard.press('Enter')
    wait_expanded_match(page, -1)
    assert 'match_0_duration' not in statistics_items(page)
    page.set_viewport_size({'width':320, 'height':568})
    page.wait_for_timeout(400)
    first_page = visible_match_indexes(page)
    button(page, 'match_0', True)
    wait_expanded_match(page, 0)
    assert visible_match_indexes(page) == first_page, 'Expanding a match changed the page boundaries'
    focus_button(page, 'history_next')
    page.keyboard.press('Enter')
    page.wait_for_function('window.stackAttackState.statistics_view.first_match > 0')
    second_page = visible_match_indexes(page)
    assert second_page[0] == first_page[-1] + 1
    assert state(page)['statistics_view']['expanded_match'] == -1
    fixed_panel(page)
    button(page, 'history_previous', True)
    page.wait_for_function('window.stackAttackState.statistics_view.first_match === 0')
    viewed = visible_match_indexes(page)
    assert viewed == first_page
    while 'history_next' in state(page)['buttons']:
        button(page, 'history_next', True)
        next_page = visible_match_indexes(page)
        assert next_page[0] > viewed[-1], 'History pagination did not advance'
        viewed.extend(next_page)
    assert viewed == list(range(8)), 'Some preview history rows cannot be reached'
    button(page, 'back', True)
    wait_screen(page, 'menu')
    button(page, 'statistics', True)
    wait_screen(page, 'statistics')
    assert not state(page)['statistics_view']['preview']
    assert statistics_items(page)['empty_history'] == 'Партий пока нет'
    assert personal_statistics(state(page)) == original
    assert not errors, errors
    context.close()
    return {'responsive_expanded_history':'PASS', 'keyboard_and_touch_navigation':'PASS',
            'fixture_isolation':'PASS', 'screenshots':shots}


def match_duration(duration_ms):
    minutes, seconds = divmod(duration_ms // 1000, 60)
    hours, minutes = divmod(minutes, 60)
    return (f'{hours}:' if hours else '') + f'{minutes:02d}:{seconds:02d}'


def check_match_details(page, index, match):
    items = statistics_items(page)
    prefix = f'match_{index}_'
    ended_at = datetime.fromisoformat(match['ended_at'])
    assert ended_at.strftime('%d.%m.%Y %H:%M:%S') in items[prefix+'date']
    assert str(match['score']) in items[prefix+'score']
    assert items[prefix+'duration'] == f"Длительность {match_duration(match['duration_ms'])}"
    assert items[prefix+'reason'] == {'crushed':'Придавило ящиком', 'overflow':'Склад переполнен'}[match['reason']]
    assert items[prefix+'lines'] == f"Ряды {match['lines']}"
    assert items[prefix+'crates'] == f"Ящики {match['crates']}"
    assert items[prefix+'combo'] == f"Лучшее комбо x{match['best_combo']}"


def statistics_match_flow(browser):
    context = browser.new_context(viewport={'width':390, 'height':844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    initial = personal_statistics(state(page))
    assert initial['matches'] == initial['records'] == []
    assert all(value == 0 for value in initial['statistics'].values())

    button(page, 'play', True)
    wait_screen(page, 'playing')
    scenario(page, 'chain')
    page.wait_for_function('window.stackAttackState.score === 200 && window.stackAttackState.state === "playing"')
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    paused = state(page)
    assert paused['active_duration_ms'] > 0
    page.wait_for_timeout(1250)
    still_paused = state(page)
    assert still_paused['ticks'] == paused['ticks']
    assert still_paused['active_duration_ms'] == paused['active_duration_ms'], 'Paused wall time was added to play time'
    assert personal_statistics(still_paused) == initial
    button(page, 'resume', True)
    wait_screen(page, 'playing')
    scenario(page, 'crush')
    wait_screen(page, 'over')
    result = state(page)
    scored, = result['profile']['matches']
    assert {key:scored[key] for key in ('score', 'lines', 'crates', 'best_combo', 'reason')} == {
        'score':200, 'lines':2, 'crates':20, 'best_combo':2, 'reason':'crushed'}
    assert scored['duration_ms'] > paused['active_duration_ms']
    assert scored['duration_ms'] == result['active_duration_ms']
    assert abs(scored['duration_ms'] - result['ticks'] * 1000 / 120) <= 0.5 + 1e-9
    score_only_result(page)

    button(page, 'again', True)
    wait_screen(page, 'playing')
    scenario(page, 'line')
    page.wait_for_function('window.stackAttackState.score === 100 && window.stackAttackState.state === "playing"')
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    button(page, 'restart', True)
    wait_screen(page, 'playing')
    assert state(page)['score'] == 0 and state(page)['profile']['matches'] == [scored]
    scenario(page, 'overflow')
    wait_screen(page, 'over')
    result = state(page)
    overflow, previous = result['profile']['matches']
    assert previous == scored and overflow['ended_at'] >= scored['ended_at']
    assert {key:overflow[key] for key in ('score', 'lines', 'crates', 'best_combo', 'reason')} == {
        'score':0, 'lines':0, 'crates':0, 'best_combo':0, 'reason':'overflow'}
    assert overflow['duration_ms'] == result['active_duration_ms']
    assert overflow['duration_ms'] > 0
    score_only_result(page)
    saved_statistics = personal_statistics(result)
    total_duration = scored['duration_ms'] + overflow['duration_ms']
    assert saved_statistics['statistics'] == {
        'played':2, 'best_score':200, 'total_lines':2, 'total_crates':20,
        'max_lines':2, 'best_combo':2, 'crushed':1, 'overflow':1,
        'average_duration_ms':(total_duration+1)//2, 'max_duration_ms':max(scored['duration_ms'], overflow['duration_ms'])}

    button(page, 'home', True)
    wait_screen(page, 'menu')
    button(page, 'play', True)
    wait_screen(page, 'playing')
    scenario(page, 'line')
    page.wait_for_function('window.stackAttackState.score === 100 && window.stackAttackState.state === "playing"')
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    button(page, 'home', True)
    wait_screen(page, 'menu')
    assert personal_statistics(state(page)) == saved_statistics, 'Abandoned match changed statistics'
    button(page, 'statistics', True)
    wait_screen(page, 'statistics')
    assert not state(page)['statistics_view']['preview']
    items = statistics_items(page)
    assert items['match_0_score'] == '0' and items['match_1_score'] == '200'
    assert items['match_0_status'] == 'Склад переполнен' and items['match_1_status'] == 'Придавило ящиком'
    stats = saved_statistics['statistics']
    expected_items = {
        'played':'Сыграно', 'played_value':'2', 'best_score_value':'200', 'lines_crates_value':'2 / 20',
        'max_lines_value':'2', 'best_combo_value':'x2', 'crushed':'Придавило ящиком 1', 'overflow':'Склад переполнен 1',
        'duration_value':f"{match_duration(stats['average_duration_ms'])} / {match_duration(stats['max_duration_ms'])}",
    }
    assert {name:items[name] for name in expected_items} == expected_items
    assert all('поражения' not in label.lower() for label in items.values())
    button(page, 'match_0', True)
    wait_expanded_match(page, 0)
    check_match_details(page, 0, overflow)
    button(page, 'match_0', True)
    wait_expanded_match(page, -1)
    focus_button(page, 'match_1')
    page.keyboard.press('Enter')
    wait_expanded_match(page, 1)
    check_match_details(page, 1, scored)
    completed_shot = screenshot(page, 'statistics-completed-matches-390x844.png')
    before_demo = state(page)['demo']['losses']
    scenario(page, 'demo_crush')
    page.wait_for_function('count => window.stackAttackState.demo.losses > count', arg=before_demo)
    assert personal_statistics(state(page)) == saved_statistics, 'Demo loss changed statistics'

    button(page, 'back', True)
    wait_screen(page, 'menu')
    button(page, 'settings', True)
    wait_screen(page, 'settings')
    slider(page, 'music', .2)
    slider(page, 'effects', .3)
    page.wait_for_timeout(2800)  # Godot synchronizes user:// to IndexedDB asynchronously.
    page.reload()
    wait_screen(page, 'menu')
    loaded = state(page)
    assert personal_statistics(loaded) == saved_statistics
    assert abs(loaded['profile']['music']-.2) < .001 and abs(loaded['profile']['effects']-.3) < .001
    assert not errors, errors
    context.close()
    return {'both_losses':'PASS', 'newest_first':'PASS', 'aggregates_and_match_details':'PASS',
            'pause_excluded':'PASS', 'abandoned_restart_and_demo_isolation':'PASS',
            'settings_and_statistics_reload':'PASS', 'screenshots':[completed_shot]}


def seed_legacy_profile(page, payload):
    # Replace the save in this disposable context after the engine has shut down.
    page.goto(URL.rsplit('/', 1)[0] + '/build-source.json')
    page.evaluate('''payload => new Promise((resolve, reject) => {
        const open = indexedDB.open('/userfs');
        open.onerror = () => reject(open.error);
        open.onsuccess = () => {
            const db = open.result;
            const tx = db.transaction('FILE_DATA', 'readwrite');
            const entries = tx.objectStore('FILE_DATA').openCursor();
            let found = false;
            let normalSave = false;
            entries.onsuccess = () => {
                const cursor = entries.result;
                if (!cursor) return;
                if (cursor.key.endsWith('/stack-attack-profile-v1.json')) normalSave = true;
                if (cursor.key.endsWith('/stack-attack-profile-v1.json.qa')) {
                    const contents = new TextEncoder().encode(JSON.stringify(payload));
                    cursor.update({...cursor.value, contents, timestamp: new Date()});
                    found = true;
                }
                cursor.continue();
            };
            tx.oncomplete = () => {
                db.close();
                if (normalSave) reject(new Error('QA Web wrote the normal Godot profile'));
                else if (!found) reject(new Error('QA Web profile missing in IndexedDB'));
                else resolve();
            };
            tx.onerror = () => reject(tx.error);
        };
    })''', payload)


def statistics_legacy_profile(browser):
    context = browser.new_context(viewport={'width':390, 'height':844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    button(page, 'settings', True)
    wait_screen(page, 'settings')
    slider(page, 'music', .35)
    page.wait_for_timeout(2800)  # Wait for a real Godot save entry to replace.
    old_records = [{'score':1800, 'date':'12.11.2026'}]
    seed_legacy_profile(page, {'version':1, 'music':.25, 'effects':.8, 'vibration':False, 'records':old_records})
    page.goto(URL)
    wait_screen(page, 'menu')
    initial = state(page)['profile']
    assert initial['records'] == old_records and initial['matches'] == []
    assert initial['statistics']['best_score'] == 1800
    assert all(value == 0 for key, value in initial['statistics'].items() if key != 'best_score')
    assert abs(initial['music']-.25) < .001 and abs(initial['effects']-.8) < .001 and not initial['vibration']

    button(page, 'play', True)
    wait_screen(page, 'playing')
    scenario(page, 'overflow')
    wait_screen(page, 'over')
    button(page, 'home', True)
    wait_screen(page, 'menu')
    button(page, 'statistics', True)
    wait_screen(page, 'statistics')
    loaded = state(page)['profile']
    assert loaded['records'] == old_records and len(loaded['matches']) == 1
    assert loaded['statistics']['played'] == loaded['statistics']['overflow'] == 1
    assert loaded['statistics']['best_score'] == 1800
    button(page, 'match_1', True)
    wait_expanded_match(page, 1)
    items = statistics_items(page)
    assert items['match_1_date'] == old_records[0]['date'] and items['match_1_score'] == '1800'
    assert items['match_1_legacy'] == 'Старый рекорд'
    assert 'Сохранены дата и счёт' in items['match_1_legacy_details']
    assert not {'match_1_duration', 'match_1_reason', 'match_1_lines', 'match_1_crates', 'match_1_combo'} & items.keys()
    assert not errors, errors
    context.close()
    return {'real_version_one_save':'PASS', 'qa_save_isolation':'PASS', 'only_known_legacy_details':'PASS',
            'new_match_with_legacy_best':'PASS'}


def wooden_crates(browser):
    context = browser.new_context(viewport={'width':360,'height':800},has_touch=True,device_scale_factor=1)
    page = context.new_page()
    page.goto(URL)
    wait_screen(page,'menu')
    checks = []
    for screen in ['menu','playing']:
        if screen == 'playing':
            button(page,'play',True)
            wait_screen(page,'playing')
        scenario(page,'crate_appearance')
        page.wait_for_function('window.stackAttackState.visible_crates.map(c => c.color).join() === "0,1,2"')
        snapshot = state(page)
        image = Image.open(io.BytesIO(page.screenshot())).convert('RGB')
        fx,fy,fw,_ = snapshot['field']
        cell = fw/snapshot['columns']
        assert cell == 32 and snapshot['viewport'] == [360,800]
        crops = [image.crop((round(fx+c['x']*cell),round(fy+c['y']*cell),round(fx+(c['x']+1)*cell),round(fy+(c['y']+1)*cell)))
                 for c in snapshot['visible_crates']]
        hashes = [hashlib.sha256(crop.tobytes()).hexdigest() for crop in crops]
        assert len(set(hashes)) == 1, ('Legacy color tags changed the crate appearance',screen,hashes)
        if screen == 'playing':
            raw = crops[0].tobytes()
            orange = sum(r>150 and r>g>b for r,g,b in zip(raw[0::3],raw[1::3],raw[2::3]))
            assert orange > cell*cell/3, 'The shared appearance must be wood'
        checks.append({'screen':screen,'legacy_color_tags':[0,1,2],'identical_crate_pixels':'PASS',
                       'screenshot':screenshot(page,f'wood-crates-{screen}-360x800.png')})
    context.close()
    print('WOODEN_CRATES',json.dumps(checks),flush=True)
    return checks


def workshop_screens(browser):
    checks = []
    for width,height in [(390,844),(844,390),(768,1004)]:
        context = browser.new_context(viewport={'width':width,'height':height},has_touch=True,device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror',lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page,'menu')
        assert state(page)['missing_menu_glyphs'] == ''
        ticks = state(page)['demo']['ticks']
        page.wait_for_timeout(350)
        assert state(page)['demo']['ticks'] > ticks
        page.mouse.move(2,2)
        menu = screenshot(page,f'workshop-menu-{width}x{height}.png')
        button(page,'play',True)
        wait_screen(page,'playing')
        scenario(page,'showcase')
        page.wait_for_timeout(350)
        snapshot = state(page)
        assert snapshot['columns'] == 10 and snapshot['rows'] == 11
        assert set(snapshot['buttons']) == {'pause'}, 'Visual slice must not add tool/ability UI'
        assert snapshot['cosmetic_magnet']
        raw = page.screenshot()
        image = Image.open(io.BytesIO(raw)).convert('RGB')
        fx,fy,fw,_ = snapshot['field'];px,py=snapshot['player']
        cell=fw/snapshot['columns'];scale=page.locator('canvas').bounding_box()['width']/snapshot['viewport'][0]
        area=(round((fx+(px-.25)*cell)*scale),round((fy+(py-.15)*cell)*scale),round((fx+(px+1)*cell)*scale),round((fy+(py+1)*cell)*scale))
        red=sum(image.getpixel((x,y)) == (215,67,56) for y in range(area[1],area[3]) for x in range(area[0],area[2]))
        assert red >= 2, ('Cosmetic U magnet must be visible at real game scale',width,height,red)
        game = screenshot(page,f'workshop-game-{width}x{height}.png')
        hero_crop = [round((fx+(px-1/24)*cell)*scale)-2,round((fy+(py-2/24)*cell)*scale)-2,
                     round((fx+(px+15/24)*cell)*scale)+2,round((fy+(py+22/24)*cell)*scale)+2]
        button(page,'pause',True)
        wait_screen(page,'paused')
        fixed_panel(page)
        page.mouse.move(2,2)
        paused = screenshot(page,f'workshop-paused-{width}x{height}.png')
        button(page,'home',True)
        wait_screen(page,'menu')
        assert not errors,errors
        checks.append({'viewport':[width,height],'reference_style':'workshop','cosmetic_magnet_pixels':red,'unchanged_grid':[10,11],
                       'no_tool_slots':'PASS','live_menu':'PASS','pause_home':'PASS','hero_crop':hero_crop,'screenshots':[menu,game,paused],
                       'screenshot_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in [menu,game,paused]}})
        print('WORKSHOP',json.dumps(checks[-1]),flush=True)
        context.close()
    return checks


def menu_layouts(browser):
    context = browser.new_context(viewport={'width':390, 'height':844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    results = []
    for dimensions in [(320,568), (568,320), (390,844), (844,390), (344,882), (882,344), (768,1004), (1004,768), (360,360)]:
        previous_focus = state(page)['panel']['focus']
        page.set_viewport_size({'width':dimensions[0], 'height':dimensions[1]})
        page.wait_for_timeout(400)
        assert state(page)['panel']['focus'] == previous_focus, 'Resize lost menu focus'
        shots = []
        fixed_panel(page)
        shots.append(screenshot(page, f'fixed-menu-{dimensions[0]}x{dimensions[1]}.png'))
        # Keyboard activation of the settings button, then touch navigation.
        for _ in range(3):
            if state(page)['panel']['focus'] == 'settings':
                break
            tab(page)
        page.keyboard.press('Enter')
        wait_screen(page, 'settings')
        fixed_panel(page)
        shots.append(screenshot(page, f'fixed-settings-{dimensions[0]}x{dimensions[1]}.png'))
        button(page, 'back', True)
        wait_screen(page, 'menu')
        original = personal_statistics(state(page))
        scenario(page, 'statistics_menu')
        wait_screen(page, 'statistics')
        assert state(page)['statistics_view']['preview'] and 'match_0' in state(page)['buttons']
        assert personal_statistics(state(page)) == original
        fixed_panel(page)
        shots.append(screenshot(page, f'fixed-statistics-{dimensions[0]}x{dimensions[1]}.png'))
        button(page, 'back', True)
        wait_screen(page, 'menu')
        button(page, 'play', True)
        wait_screen(page, 'playing')
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        fixed_panel(page)
        button(page, 'resume', True)
        wait_screen(page, 'playing')
        scenario(page, 'crush')
        wait_screen(page, 'over')
        fixed_panel(page)
        button(page, 'home', True)
        wait_screen(page, 'menu')
        results.append({'viewport':list(dimensions), 'fixed_panels':'PASS', 'wheel_and_swipe':'PASS', 'focus_and_transitions':'PASS', 'statistics_preview':'PASS', 'screenshots':shots})
        print('MENU_LAYOUT', json.dumps(results[-1]), flush=True)
    assert not errors, errors
    context.close()
    return results


try:
    with sync_playwright() as p:
        browser_options = {}
        if os.environ.get("CHROMIUM_BIN"):
            browser_options["executable_path"] = os.environ["CHROMIUM_BIN"]
        elif sys.platform == "darwin":
            browser_options["channel"] = "chrome"
        else:
            browser_options["executable_path"] = "/usr/bin/chromium"
        browser = p.chromium.launch(**browser_options,
            headless=True, args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
                                 '--autoplay-policy=no-user-gesture-required'])
        statistics = {}
        if args.statistics_only or not (args.workshop_only or args.game_over_only or args.ui_only or args.sprites_only):
            statistics = {'preview':statistics_preview(browser), 'match_flow':statistics_match_flow(browser),
                          'legacy_profile':statistics_legacy_profile(browser)}
            print('STATISTICS', json.dumps(statistics), flush=True)
        if args.statistics_only:
            (BUILD/'statistics-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':statistics,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        if args.workshop_only:
            crates = wooden_crates(browser)
            checks = workshop_screens(browser)
            (BUILD/'workshop-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader','checks':checks,'wooden_crates':crates,
                'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        results_over = game_over_screens(browser) if args.game_over_only or not (args.ui_only or args.sprites_only) else []
        if args.game_over_only:
            (BUILD/'game-over-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':results_over,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        button_styles = uniform_action_buttons(browser) if not args.sprites_only else []
        ui_batch = ui_batch_checks(browser) if not args.sprites_only else {}
        if args.ui_only:
            (BUILD/'ui-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'checks':ui_batch,'button_styles':button_styles,
                'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        sprites = sprite_poses(browser)
        if args.sprites_only:
            (BUILD/'sprite-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),'checks':sprites},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        crates = wooden_crates(browser)
        workshop = workshop_screens(browser)
        menus = menu_layouts(browser)
        for touch, dimensions in [(False, (1280, 720)), (True, (390, 844)), (True, (320, 568))]:
            context = browser.new_context(viewport={'width': dimensions[0], 'height': dimensions[1]},
                                          has_touch=touch, device_scale_factor=1)
            page = context.new_page()
            errors = []
            failed = []
            console_errors = []
            page.on('pageerror', lambda value: errors.append(str(value)))
            page.on('requestfailed', lambda request: failed.append(request.url))
            page.on('console', lambda message: console_errors.append(message.text) if message.type == 'error' else None)
            page.add_init_script(AUDIO_PROBE)
            response = page.goto(URL)
            assert response.status == 200
            wait_screen(page, 'menu')
            assert state(page)['missing_menu_glyphs'] == '', ('Menu font is missing glyphs', state(page)['missing_menu_glyphs'])
            menu_shot = screenshot(page, f'menu-{dimensions[0]}x{dimensions[1]}.png')
            button(page, 'play', touch)
            wait_screen(page, 'playing')
            scenario(page, 'push')
            snapshot = state(page)
            player_x = snapshot['player'][0]
            if touch:
                move = point(page, snapshot['controls']['right'])
                jump = point(page, snapshot['controls']['jump'])
                cdp = context.new_cdp_session(page)
                cdp.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[
                    {'x':move[0], 'y':move[1], 'id':1}, {'x':jump[0], 'y':jump[1], 'id':2}]})
                page.wait_for_timeout(220)
                during = state(page)
                cdp.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
                assert during['player'][0] > player_x + .1
                assert during['player'][1] < snapshot['player'][1] - .3
            else:
                page.keyboard.down('ArrowRight')
                page.keyboard.press('Space')
                page.wait_for_timeout(220)
                during = state(page)
                page.keyboard.up('ArrowRight')
                assert during['player'][0] > player_x + .1
                assert during['player'][1] < snapshot['player'][1] - .3
            page.wait_for_timeout(150)
            released_x = state(page)['player'][0]
            page.wait_for_timeout(200)
            assert abs(state(page)['player'][0] - released_x) < .03, 'A released movement control stayed active'
            button(page, 'pause', touch)
            wait_screen(page, 'paused')
            paused = state(page)
            page.wait_for_timeout(300)
            assert state(page)['ticks'] == paused['ticks'], 'Pause did not freeze the model'
            other = (dimensions[1], dimensions[0])
            page.set_viewport_size({'width':other[0], 'height':other[1]})
            expected = 'landscape' if other[0] > other[1] else 'portrait'
            page.wait_for_function('value => window.stackAttackState.layout === value', arg=expected)
            page.wait_for_timeout(250)
            rotated = state(page)
            assert rotated['ticks'] == paused['ticks']
            assert rotated['player'] == paused['player'] and rotated['score'] == paused['score']
            assert rotated['columns'] == 10 and rotated['rows'] == 11
            for rect in rotated['controls'].values():
                x,y,w,h = rect
                assert x>=0 and y>=0 and x+w<=rotated['viewport'][0]+1 and y+h<=rotated['viewport'][1]+1
                fx,fy,fw,fh = rotated['field']
                assert x+w<=fx or x>=fx+fw or y+h<=fy or y>=fy+fh, 'A touch control overlaps the field'
            button(page, 'resume', touch)
            wait_screen(page, 'playing')
            before_restart = state(page)['session']
            button(page, 'pause', touch)
            wait_screen(page, 'paused')
            button(page, 'restart', touch)
            wait_screen(page, 'playing')
            assert state(page)['session'] == before_restart + 1 and state(page)['score'] == 0
            scenario(page, 'chain')
            page.wait_for_function('window.stackAttackState.score === 200 && window.stackAttackState.state === "playing"', timeout=15000)
            scenario(page, 'showcase')
            game_shot = screenshot(page, f'game-{other[0]}x{other[1]}.png')
            scenario(page, 'crush')
            wait_screen(page, 'over')
            assert state(page)['profile']['matches'][0]['score'] == 200
            previous_session = state(page)['session']
            button(page, 'again', touch)
            wait_screen(page, 'playing')
            assert state(page)['score'] == 0 and state(page)['session'] == previous_session + 1
            scenario(page, 'overflow')
            wait_screen(page, 'over')
            button(page, 'home', touch)
            wait_screen(page, 'menu')
            button(page, 'statistics', touch)
            wait_screen(page, 'statistics')
            assert [match['score'] for match in state(page)['profile']['matches']] == [0, 200]
            assert state(page)['profile']['statistics']['best_score'] == 200
            button(page, 'back', touch)
            wait_screen(page, 'menu')
            button(page, 'play', touch)
            wait_screen(page, 'playing')
            button(page, 'pause', touch)
            wait_screen(page, 'paused')
            button(page, 'home', touch)
            wait_screen(page, 'menu')
            button(page, 'settings', touch)
            wait_screen(page, 'settings')
            assert not state(page)['profile']['vibration_visible']
            slider(page, 'music', 0)
            slider(page, 'effects', 0)
            page.wait_for_timeout(650)
            silent_rms = rms(page)
            slider(page, 'music', .5)
            samples = []
            for _ in range(6):
                page.wait_for_timeout(120)
                samples.append(rms(page))
            audible_rms = max(samples)
            assert state(page)['audio']['unlocked'] and state(page)['audio']['music_playing']
            assert silent_rms >= 0 and silent_rms < .001, ('Muted buses produced audio', silent_rms)
            if audible_rms <= .001:
                print('AUDIO_DEBUG', json.dumps(page.evaluate('''() => ({state:window.stackAttackState.audio, analysers:(window.qaAudioAnalysers||[]).map(a=>({state:a.context.state,time:a.context.currentTime,rms:(()=>{const d=new Float32Array(a.fftSize);a.getFloatTimeDomainData(d);return Math.sqrt(d.reduce((s,v)=>s+v*v,0)/d.length)})()}))})''')), flush=True)
            assert audible_rms > .001, ('No actual audio samples detected', samples)
            slider(page, 'music', 0)
            slider(page, 'effects', .5)
            effect_samples = []
            for _ in range(60):
                page.wait_for_timeout(100)
                effect_samples.append(rms(page))
                if effect_samples[-1] > .001:
                    break
            assert max(effect_samples) > .001, ('Effects bus is silent', effect_samples)
            slider(page, 'music', .2)
            slider(page, 'effects', .3)
            page.wait_for_timeout(2800)  # Godot synchronizes user:// to IndexedDB asynchronously.
            page.reload()
            wait_screen(page, 'menu')
            saved = state(page)['profile']
            assert abs(saved['music']-.2)<.001 and abs(saved['effects']-.3)<.001, saved
            assert [match['score'] for match in saved['matches']] == [0, 200], saved
            assert saved['statistics']['best_score'] == 200, saved
            assert not errors, errors
            assert not failed, failed
            assert not console_errors, console_errors
            all_errors.extend(errors)
            all_failed_requests.extend(failed)
            result = {'viewport':list(dimensions), 'rotated':list(other),
                      'input':'multitouch' if touch else 'keyboard + mouse',
                      'menu_glyphs':'PASS', 'pause':'PASS', 'line_chain':'PASS', 'both_losses':'PASS', 'restart':'PASS',
                      'settings_and_statistics_reload':'PASS', 'muted_rms':silent_rms, 'audible_rms':audible_rms, 'effects_rms':max(effect_samples),
                      'screenshots':[menu_shot,game_shot]}
            results.append(result)
            print(json.dumps(result), flush=True)
            context.close()
        report = {'status':'PASS','browser':browser.version,'renderer':'SwiftShader', 'statistics':statistics, 'wooden_crates':crates,'workshop':workshop,'menu_layouts':menus, 'sprite_poses':sprites, 'ui_batch':ui_batch, 'game_over':results_over,'button_styles':button_styles,
                  'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),
                  'page_errors':all_errors,'failed_requests':all_failed_requests,'checks':results}
        (BUILD/'web-check.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
        browser.close()
finally:
    server.shutdown()
    server.server_close()
