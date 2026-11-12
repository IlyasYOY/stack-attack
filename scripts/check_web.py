#!/usr/bin/env python3
"""End-to-end checks against the actual exported game; debug fixtures require ?qa=1."""
import functools
import argparse
import base64
import hashlib
import http.server
import html
import io
import json
import os
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
group = parser.add_mutually_exclusive_group()
group.add_argument('--sprites-only', action='store_true', help='Run only frozen-pose rendered sprite regressions')
group.add_argument('--ui-only', action='store_true', help='Run demo isolation and vibration UI regressions only')
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
        page.keyboard.press('Tab')
        page.wait_for_timeout(100)
        visited.add(state(page)['panel']['focus'])
    assert visited == names and state(page)['panel']['focus'] == start, ('Broken focus cycle', visited, names)
    page.keyboard.press('Shift+Tab')
    page.keyboard.press('Tab')
    page.wait_for_timeout(120)
    assert state(page)['panel']['focus'] == start


def sprite_comparison(browser, check):
    width, height = check['viewport']
    commit = json.loads((BUILD/'web/build-source.json').read_text())['commit']
    cells = []
    for pose, label in [('idle','Покой'), ('walk_stride','Шаг'), ('walk_recover','Возврат')]:
        for facing, direction in [(1,'Вправо'), (-1,'Влево')]:
            sample = next(p for p in check['poses'] if p['pose'] == pose and p['facing'] == facing)
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
    marker = source.getpixel((3, 9))[:3]  # Symmetric scarf band, fixed to the torso in both frames.
    alpha = {}
    for frame in ['idle', 'walk']:
        with Image.open(ROOT / f'art/hero_{frame}.png') as image:
            alpha[frame] = {'canvas':image.size, 'used':image.getbbox()}
            assert image.size == (14,22) and image.getbbox() == (0,0,13,22), 'Sprite canvas/padding changed; recheck its reflection axis'
            band = [x for y in [9,10] for x in range(image.width) if image.getpixel((x,y)) == (*marker,255)]
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
        for pose in ['idle', 'walk_stride', 'walk_recover']:
            for facing in [1, -1]:
                page.evaluate('value => window.stackAttackQARequest = value', {'scenario':'hero_pose', 'pose':pose, 'facing':facing})
                page.wait_for_function('value => window.stackAttackState.hero_pose && window.stackAttackState.facing === value', arg=facing)
                page.wait_for_timeout(180)
                snapshot = state(page)
                frame = 'walk' if pose == 'walk_stride' else 'idle'
                assert snapshot['hero_frame'] == frame
                path = SHOTS / f'hero-{pose}-{"right" if facing == 1 else "left"}-{dimensions[0]}x{dimensions[1]}.png'
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
                poses.append({'pose':pose,'facing':facing,'frame':frame,'player':snapshot['player'],
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
            samples = {sample['pose']:sample for sample in poses if sample['facing'] == facing}
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
    records = first['profile']['records']
    positions = []
    for _ in range(16):
        page.wait_for_timeout(250)
        positions.append(state(page)['demo']['player'][0])
    moving = state(page)
    assert max(positions)-min(positions) > .5 and moving['demo']['jumps'] > 0 and moving['demo']['drops'] > 0
    assert moving['ticks'] == first['ticks'] == 0 and moving['session'] == 0 and moving['score'] == 0
    assert moving['profile']['records'] == records
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
    assert after_loss['session'] == 0 and after_loss['ticks'] == 0 and after_loss['profile']['records'] == records
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
    assert state(page)['demo']['ticks'] > stopped_demo and state(page)['profile']['records'] == records
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
    assert all(value == 0 for value in enabled['vibration_styles'].values())
    toggle = next(item for item in enabled['panel']['items'] if item['name'] == 'vibration')
    assert toggle['text'] == 'Виброотклик: Вкл'
    on = page.screenshot()
    x,y,w,h = enabled['buttons']['vibration']
    a,b = point(page,[x+2,y+8,1,1]),point(page,[x+6,y+h-8,1,1])
    bounds = (round(a[0]),round(a[1]),round(b[0]),round(b[1]))
    # The clear padding must keep the same background immediately after toggling,
    # while the control still owns focus/hover; black pressed fallbacks fail here.
    assert Image.open(io.BytesIO(off)).crop(bounds).tobytes() == Image.open(io.BytesIO(on)).crop(bounds).tobytes()
    toggle_shot = screenshot(page, 'android-vibration-on-web-qa-390x844.png')
    page.keyboard.press('Tab')
    page.wait_for_timeout(150)
    blurred = page.screenshot()
    assert Image.open(io.BytesIO(on)).crop(bounds).tobytes() == Image.open(io.BytesIO(blurred)).crop(bounds).tobytes()
    page.reload()
    wait_screen(page, 'menu')
    assert state(page)['profile']['records'] == records and state(page)['profile']['vibration']
    assert not errors, errors
    context.close()
    result = {'demo_motion':'PASS','real_loss_restart':'PASS','personal_game_and_records_isolation':'PASS',
              'repeated_settings':'PASS','vibration_pixels_and_focus':'PASS','web_vibration_hidden':'PASS',
              'screenshots':[menu_shot,toggle_shot]}
    print('UI_BATCH',json.dumps(result),flush=True)
    return result


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
            page.keyboard.press('Tab')
            page.wait_for_timeout(100)
        page.keyboard.press('Enter')
        wait_screen(page, 'settings')
        fixed_panel(page)
        shots.append(screenshot(page, f'fixed-settings-{dimensions[0]}x{dimensions[1]}.png'))
        button(page, 'back', True)
        wait_screen(page, 'menu')
        scenario(page, 'records_menu')
        wait_screen(page, 'records')
        assert len(state(page)['profile']['records']) == 10
        fixed_panel(page)
        shots.append(screenshot(page, f'fixed-records-{dimensions[0]}x{dimensions[1]}.png'))
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
        results.append({'viewport':list(dimensions), 'fixed_panels':'PASS', 'wheel_and_swipe':'PASS', 'focus_and_transitions':'PASS', 'ten_records':'PASS', 'screenshots':shots})
        print('MENU_LAYOUT', json.dumps(results[-1]), flush=True)
    assert not errors, errors
    context.close()
    return results


try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM_BIN', '/usr/bin/chromium'),
            headless=True, args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
                                 '--autoplay-policy=no-user-gesture-required'])
        ui_batch = ui_batch_checks(browser) if not args.sprites_only else {}
        if args.ui_only:
            (BUILD/'ui-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'checks':ui_batch,
                'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        sprites = sprite_poses(browser)
        if args.sprites_only:
            (BUILD/'sprite-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),'checks':sprites},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
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
            assert state(page)['profile']['records'][0]['score'] == 200
            previous_session = state(page)['session']
            button(page, 'again', touch)
            wait_screen(page, 'playing')
            assert state(page)['score'] == 0 and state(page)['session'] == previous_session + 1
            scenario(page, 'overflow')
            wait_screen(page, 'over')
            button(page, 'home', touch)
            wait_screen(page, 'menu')
            button(page, 'records', touch)
            wait_screen(page, 'records')
            assert state(page)['profile']['records'][0]['score'] == 200
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
            assert saved['records'][0]['score']==200, saved
            assert not errors, errors
            assert not failed, failed
            assert not console_errors, console_errors
            all_errors.extend(errors)
            all_failed_requests.extend(failed)
            result = {'viewport':list(dimensions), 'rotated':list(other),
                      'input':'multitouch' if touch else 'keyboard + mouse',
                      'menu_glyphs':'PASS', 'pause':'PASS', 'line_chain':'PASS', 'both_losses':'PASS', 'restart':'PASS',
                      'settings_and_records_reload':'PASS', 'muted_rms':silent_rms, 'audible_rms':audible_rms, 'effects_rms':max(effect_samples),
                      'screenshots':[menu_shot,game_shot]}
            results.append(result)
            print(json.dumps(result), flush=True)
            context.close()
        report = {'status':'PASS','browser':browser.version,'renderer':'SwiftShader', 'menu_layouts':menus, 'sprite_poses':sprites, 'ui_batch':ui_batch,
                  'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),
                  'page_errors':all_errors,'failed_requests':all_failed_requests,'checks':results}
        (BUILD/'web-check.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
        browser.close()
finally:
    server.shutdown()
    server.server_close()
