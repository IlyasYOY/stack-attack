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
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError, sync_playwright
from PIL import Image, ImageChops, ImageStat

parser = argparse.ArgumentParser(description=__doc__)
group = parser.add_mutually_exclusive_group()
group.add_argument('--workshop-only', action='store_true', help='Capture and validate the workshop visual slice')
group.add_argument('--sprites-only', action='store_true', help='Run only frozen-pose rendered sprite regressions')
group.add_argument('--ui-only', action='store_true', help='Run demo isolation and vibration UI regressions only')
group.add_argument('--game-over-only', action='store_true', help='Run score-only result screen regressions and capture screenshots')
group.add_argument('--statistics-only', action='store_true', help='Check Statistics and capture its rendered overview and history')
group.add_argument('--cranes-only', action='store_true', help='Check crane passes and capture both playing layouts')
group.add_argument('--animations-only', action='store_true', help='Check row clear and crush transitions and capture their rendered phases')
group.add_argument('--keyboard-only', action='store_true', help='Check jump keys and menu keyboard isolation')
group.add_argument('--boots-only', action='store_true', help='Check equipment offers, air jumps and responsive boots UI')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
SHOTS = BUILD / 'screenshots'
WEB_LAYOUT_VIEWPORTS = (
    (390, 844), (844, 390), (320, 568), (568, 320), (344, 882), (882, 344),
    (768, 1004), (1004, 768), (360, 360),
)
HERO_FRAMES = ('idle', 'walk', 'jump', 'push')
HERO_FRAME_SIZE = (32, 48)
FORMER_MAGNET_COLORS = {(215, 67, 56), (168, 46, 51), (255, 129, 96)}
NOZZLE_COLORS = {(227, 154, 83), (176, 101, 67)}
ROCKET_BOOT_COLORS = {(98, 167, 157), (217, 228, 202)} | NOZZLE_COLORS
JUMP_NOZZLES = (7.5, 21.5)
EXHAUST_FLAME = (255, 128, 63)
EXHAUST_CORE = (255, 230, 160)
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


def check_touch_control_layout(snapshot):
    width, height = snapshot['viewport']
    field_x, field_y, field_width, field_height = snapshot['field']
    assert snapshot['controls'].keys() == {'left', 'right', 'jump'}
    for action, rect in snapshot['controls'].items():
        x, y, w, h = rect
        assert 0 <= x and 0 <= y and x + w <= width + 1 and y + h <= height + 1, (
            'Touch control is outside the viewport', action, rect, snapshot['viewport'])
        assert x + w <= field_x or x >= field_x + field_width or y + h <= field_y or y >= field_y + field_height, (
            'Touch control overlaps the field', action, rect, snapshot['field'], snapshot['viewport'])


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


def hero_sprite_crop(image, snapshot, player, facing, bounds):
    """Project source sprite pixels onto the actual rendered hero."""
    fx, fy, fw, _ = snapshot['field']
    cell = fw / snapshot['columns']
    scale = image.width / snapshot['viewport'][0]
    px, py = player
    origin_x = fx + (int(px * 24 + .5) - 1) * cell / 24
    origin_y = fy + (int(py * 24 + .5) - 2) * cell / 24
    left, top, right, bottom = bounds
    if facing < 0:
        left, right = HERO_FRAME_SIZE[0] - right, HERO_FRAME_SIZE[0] - left
    return image.crop((round((origin_x + left * cell / 48) * scale),
                       round((origin_y + top * cell / 48) * scale),
                       round((origin_x + right * cell / 48) * scale),
                       round((origin_y + bottom * cell / 48) * scale)))


def color_pixels(image, colors, tolerance=0):
    return sum(count for count, rgb in image.getcolors(image.width * image.height)
               if any(max(abs(actual - expected) for actual, expected in zip(rgb, color)) <= tolerance
                      for color in colors))


def menu_shaded_colors(colors):
    shade = (.02, .06, .09)
    opacity = .38
    return {tuple(round(component * (1 - opacity) + tint * 255 * opacity)
                  for component, tint in zip(color, shade)) for color in colors}


def check_hero_hand(image, snapshot, player, facing):
    hand = hero_sprite_crop(image, snapshot, player, facing, (0, 28, 13, 43))
    glove_colors, magnet_colors = {(242, 190, 136)}, FORMER_MAGNET_COLORS
    tolerance = 0
    if snapshot['screen'] == 'menu':
        glove_colors = menu_shaded_colors(glove_colors)
        magnet_colors = menu_shaded_colors(magnet_colors)
        tolerance = 1  # The full-screen shade is alpha-composited before the menu controls.
    assert color_pixels(hand, glove_colors, tolerance) > 0, (
        'The rendered hand is obscured', snapshot['screen'], snapshot['viewport'], facing, player)
    red = color_pixels(hand, magnet_colors, tolerance)
    assert red == 0, ('Former U magnet pixel rendered at the hand', snapshot['screen'], snapshot['viewport'], facing, red)
    return red


def check_menu_hero(page, dimensions):
    checks = []
    layout = state(page)
    right_edge = layout['columns'] - layout['player_size'][0]
    # Keep the relevant hand left or right of the buttons in each orientation.
    for facing, direction, player_x in [(1, 'right', 0), (-1, 'left', right_edge)]:
        snapshot = animation_request(page, 'crate_appearance', facing=facing, player_x=player_x)
        assert snapshot['demo']['facing'] == facing
        path = SHOTS / f'hero-menu-{direction}-{dimensions[0]}x{dimensions[1]}.png'
        image = Image.open(io.BytesIO(page.screenshot(path=str(path)))).convert('RGB')
        red = check_hero_hand(image, snapshot, snapshot['demo']['player'], facing)
        checks.append({'facing':facing, 'magnet_pixels':red, 'screenshot':str(path.relative_to(ROOT))})
    return checks


def sprite_comparison(browser, check):
    width, height = check['viewport']
    source = json.loads((BUILD/'web/build-source.json').read_text())
    commit = html.escape(source['commit'][:12])
    revision = f'commit {commit}' if source['source_clean'] else f'рабочие изменения поверх {commit}'
    cells = []
    for pose, label in [('idle','Покой'), ('walk_stride','Шаг'), ('walk_recover','Возврат'), ('jump','Прыжок'), ('push','Толкание')]:
        for facing, direction in [(1,'Вправо'), (-1,'Влево')]:
            sample = next(p for p in check['poses'] if p['pose'] == pose and p['facing'] == facing and p['boots_equipped'])
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
        f'<h1>Ботинки-ракеты · {width}×{height}</h1><p>Web / Chromium · реальные кадры, увеличение 4×</p>'
        f'<p>Позиция коллизии: (4.3, 10.12) · {revision}</p>'
        '<p>Одинаковая область кадра для всех направлений и фаз.</p><main>'+''.join(cells)+'</main></html>')
    page.wait_for_function('Array.from(document.images).every(image => image.complete && image.naturalWidth > 0)')
    path = SHOTS/f'hero-comparison-{width}x{height}.png'
    page.screenshot(path=str(path), full_page=True)
    page.close()
    return str(path.relative_to(ROOT))


def sprite_poses(browser):
    checks = []
    failures = []
    marker = Image.open(ROOT / 'art/hero_idle.png').convert('RGB').getpixel((9, 23))
    frame_width, frame_height = HERO_FRAME_SIZE
    alpha = {}
    with Image.open(ROOT / 'art/hero_rocket_boots.png') as atlas:
        assert atlas.size == (frame_width * len(HERO_FRAMES), frame_height)
        for column, frame in enumerate(HERO_FRAMES):
            with Image.open(ROOT / f'art/hero_{frame}.png') as image:
                normal = image.convert('RGBA')
            rocket = atlas.crop((column * frame_width, 0, (column + 1) * frame_width, frame_height)).convert('RGBA')
            changed = ImageChops.difference(normal, rocket).getbbox(alpha_only=False)
            assert changed and changed[1] >= 32, ('Rocket boots changed pixels above the lower legs', frame, changed)
            for label, image in [(frame, normal), (f'{frame}_rocket', rocket)]:
                alpha[label] = {'canvas':image.size, 'used':image.getbbox()}
                assert image.size == HERO_FRAME_SIZE and image.getpixel((0,0))[3] == 0, (
                    'Workshop sprite canvas/padding changed; recheck reflection axis', label)
                band = [x for y in (23,24) for x in range(image.width) if image.getpixel((x,y)) == (*marker,255)]
                assert band and (min(band)+max(band)+1)/2 == image.width/2, 'Torso band is not centered in the sprite canvas'
    for dimensions in [(390,844), (844,390)]:
        context = browser.new_context(viewport={'width':dimensions[0], 'height':dimensions[1]}, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page, 'menu')
        menu = check_menu_hero(page, dimensions)
        button(page, 'play')
        wait_screen(page, 'playing')
        poses = []
        for equipped in (True, False):
            for pose in ('idle', 'walk_stride', 'walk_recover', 'jump', 'push'):
                for facing, direction in [(1, 'right'), (-1, 'left')]:
                    snapshot = animation_request(page, 'hero_pose', pose=pose, facing=facing, boots=equipped)
                    frame = {'walk_stride':'walk','jump':'jump','push':'push'}.get(pose,'idle')
                    assert snapshot['hero_pose'] and snapshot['facing'] == facing and snapshot['hero_frame'] == frame
                    assert snapshot['boots_equipped'] == equipped
                    gear = 'rocket-boots' if equipped else 'regular-boots'
                    path = SHOTS / f'hero-{pose}-{gear}-{direction}-{dimensions[0]}x{dimensions[1]}.png'
                    image = Image.open(io.BytesIO(page.screenshot(path=str(path)))).convert('RGB')
                    fx, fy, fw, _ = snapshot['field']
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
                    red = check_hero_hand(image, snapshot, snapshot['player'], facing)
                    feet = hero_sprite_crop(image, snapshot, snapshot['player'], facing, (0, 32, 32, 48))
                    rocket_pixels = color_pixels(feet, ROCKET_BOOT_COLORS)
                    assert (rocket_pixels > 0) == equipped, (
                        'Rocket boots did not render at the feet as expected', dimensions, pose, facing, equipped, rocket_pixels)
                    poses.append({'pose':pose,'boots_equipped':equipped,'magnet_pixels':red,'rocket_boot_pixels':rocket_pixels,
                                  'facing':facing,'frame':frame,'player':snapshot['player'],
                                  'torso_center_x':center,'marker_bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1],
                                  'expected_center_x':expected_center,'crop_sha256':crop_hash,'crop_bounds':[left,top,right,bottom],
                                  'screenshot':str(path.relative_to(ROOT))})
                    assert abs(center-expected_center) <= max(1,cell*scale/24), ('Torso is not centered on the collision body', dimensions, pose, facing, center, expected_center)
        fixed_player = poses[0]['player']
        floor_position = (4.3, snapshot['rows'] - snapshot['player_size'][1])
        assert all(abs(actual - expected) < 1e-5 for actual, expected in zip(fixed_player, floor_position))
        for sample in poses:
            assert sample['player'] == fixed_player, 'Direction or animation changed the fixture collision position'
            assert sample['marker_bounds'][1::2] == poses[0]['marker_bounds'][1::2], 'Turning or animation moved the torso vertically'
            if abs(sample['torso_center_x']-poses[0]['torso_center_x']) > 1:
                failures.append({'viewport':dimensions, 'pose':sample['pose'], 'facing':sample['facing'],
                                 'drift_pixels':sample['torso_center_x']-poses[0]['torso_center_x']})
        for facing in (1, -1):
            for equipped in (True, False):
                samples = {sample['pose']:sample for sample in poses
                           if sample['facing'] == facing and sample['boots_equipped'] == equipped}
                assert samples['idle']['crop_sha256'] != samples['walk_stride']['crop_sha256'], 'Walking did not render its second animation frame'
                assert samples['idle']['crop_sha256'] == samples['walk_recover']['crop_sha256'], 'Walking recovery did not return to the centered idle frame'
        assert not errors, errors
        checks.append({'viewport':list(dimensions),'alpha':alpha,'menu':menu,'poses':poses})
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


def start_crane_preview(page):
    page.evaluate('window.stackAttackQARequest = {scenario:"cranes"}')
    page.wait_for_function('''() => window.stackAttackQARequest == null
        && window.stackAttackState?.crane_preview && window.stackAttackState.ticks < 30''')


def crane_image(page, name, snapshot, dimensions):
    width, height = dimensions
    path = SHOTS / f'cranes-{name}-{width}x{height}.png'
    image = Image.open(io.BytesIO(page.screenshot(path=str(path)))).convert('RGB')
    assert image.size == dimensions
    viewport_width, viewport_height = snapshot['viewport']
    canvas = page.locator('canvas').bounding_box()
    scale_x = canvas['width'] / viewport_width
    scale_y = canvas['height'] / viewport_height
    x, y, rail_width, rail_height = snapshot['crane_rail']
    assert 0 <= x < x + rail_width <= viewport_width and 0 <= y < y + rail_height <= viewport_height, snapshot['crane_rail']
    assert y + rail_height <= snapshot['field'][1], ('Rail crosses the playfield', snapshot['crane_rail'])
    pause_x, pause_y, pause_width, pause_height = snapshot['buttons']['pause']
    if x < pause_x + pause_width and pause_x < x + rail_width:
        assert y >= pause_y + pause_height, ('Rail overlaps the top HUD', dimensions, snapshot['crane_rail'])
    cell = snapshot['field'][2] / snapshot['columns']
    for (center_x, center_y), color in zip(snapshot['crane_trolleys'], [(101,154,154), (218,148,79)]):
        # The engine can advance by a few ticks while Chromium reads back the frame.
        bounds = (round(canvas['x'] + (center_x-cell)*scale_x), round(canvas['y'] + (center_y-cell/3)*scale_y),
                  round(canvas['x'] + (center_x+cell)*scale_x), round(canvas['y'] + (center_y+cell/3)*scale_y))
        assert color in image.crop(bounds).get_flattened_data(), ('A trolley was not rendered', name, dimensions, center_x, center_y)
    return str(path.relative_to(ROOT))


def crane_release_frame(page):
    for attempt in range(2):
        try:
            return page.wait_for_function('''() => {
                const current = window.stackAttackState;
                const release = current.crane_releases[0];
                if (!release || current.ticks < release.tick + 16) return false;
                const crate = current.visible_crates.find(crate => crate.id === release.crate_id);
                return crate && crate.y > -.85 && crate.y < 0 && current.cranes[release.crane].open_time > 0
                    && current.cranes[1 - release.crane].loaded ? current : false;
            }''', timeout=5000).json_value()
        except PlaywrightTimeoutError:
            if attempt:
                raise
            # A slow frame can skip the short opening window between QA samples.
            start_crane_preview(page)


def crane_cycle(page, snapshot):
    settings = snapshot['crane_settings']
    columns = snapshot['columns']
    margin = settings['margin']
    speed = settings['speed']
    releases = []
    first_waits = [None, None]
    released_this_pass = [False, False]
    reentries = [0, 0]
    opposite_sides = [(columns + margin, -margin), (-margin, columns + margin)]
    while len(releases) < 4 or min(reentries) < 1:
        previous = snapshot
        snapshot = page.wait_for_function('''tick => {
            const current = window.stackAttackState;
            return current.ticks > tick || current.screen !== "playing" ? current : false;
        }''', arg=previous['ticks'], timeout=5000).json_value()
        assert snapshot['screen'] == 'playing' and snapshot['ticks'] < 2400, ('Crane cycle did not finish', snapshot)
        elapsed = (snapshot['ticks'] - previous['ticks']) / 120
        assert [crane['direction'] for crane in snapshot['cranes']] == [1, -1]
        for index, (before, after) in enumerate(zip(previous['cranes'], snapshot['cranes'])):
            exit_x, entry_x = opposite_sides[index]
            if after['waiting']:
                assert abs(after['x'] - exit_x) < 1e-5, ('Crane waited inside its route', after)
                assert not after['loaded'] and 0 < after['wait_remaining'] <= settings['wait_max'] + 1e-5
                if not before['waiting']:
                    assert after['wait_remaining'] + elapsed >= settings['wait_min'] - 1e-5
                    if first_waits[index] is None:
                        first_waits[index] = snapshot['ticks'] / 120 + after['wait_remaining']
                else:
                    assert abs(before['wait_remaining'] - after['wait_remaining'] - elapsed) < 1e-5
            elif before['waiting']:
                assert after['loaded'] and abs(after['x'] - entry_x) <= speed * elapsed + 1e-5
                released_this_pass[index] = False
                reentries[index] += 1
            elif elapsed < settings['wait_min']:
                assert abs(after['x'] - before['x'] - after['direction'] * speed * elapsed) < 1e-5, (
                    'Crane changed speed or stopped while crossing the field', before, after)
        for release in snapshot['crane_releases'][len(releases):]:
            index = release['crane']
            crane = snapshot['cranes'][index]
            column = release['column']
            assert not released_this_pass[index], ('Crane released twice on one pass', release)
            assert 0 <= column < columns and not crane['loaded'] and not crane['waiting']
            assert not any((other['tick'], other['column']) == (release['tick'], column) for other in releases)
            crates = [crate for crate in snapshot['visible_crates'] if crate['id'] == release['crate_id']]
            assert len(crates) == 1 and abs(crates[0]['x'] - column) < 1e-5, ('Claw did not release the board crate', release, crates)
            forward_travel = crane['direction'] * speed * (snapshot['ticks'] - release['tick']) / 120
            assert abs(crane['x'] - (column + .5) - forward_travel) <= speed / 120 + 1e-5, (
                'Claw position did not line up with the released crate', release, crane)
            releases.append(release)
            released_this_pass[index] = True
    assert {index: sum(release['crane'] == index for release in releases) for index in range(2)} == {0:2, 1:2}
    assert all(wait is not None for wait in first_waits) and abs(first_waits[0] - first_waits[1]) > 1 / 120
    return releases


def crane_checks(browser):
    context = browser.new_context(viewport={'width':390, 'height':844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    initial_statistics = personal_statistics(state(page))
    button(page, 'play', True)
    wait_screen(page, 'playing')
    shots = []
    for dimensions in [(390,844), (320,568), (844,390)]:
        width, height = dimensions
        page.set_viewport_size({'width':width, 'height':height})
        layout = 'landscape' if width > height else 'portrait'
        page.wait_for_function('layout => window.stackAttackState.layout === layout', arg=layout)
        start_crane_preview(page)
        crossing = page.wait_for_function('''() => {
            const current = window.stackAttackState;
            const [right, left] = current.cranes;
            return right.loaded && left.loaded && Math.abs(right.x - left.x) < .6 ? current : false;
        }''', timeout=12000).json_value()
        shots.append(crane_image(page, 'crossing', crossing, dimensions))
        if dimensions == (320,568):
            print('CRANE_SCREENSHOTS', json.dumps(shots[-1:]), flush=True)
            continue
        release = crane_release_frame(page)
        shots.append(crane_image(page, 'release', release, dimensions))
        print('CRANE_SCREENSHOTS', json.dumps(shots[-2:]), flush=True)

    button(page, 'pause', True)
    wait_screen(page, 'paused')
    paused = state(page)
    page.set_viewport_size({'width':390, 'height':844})
    page.wait_for_function('window.stackAttackState.layout === "portrait"')
    page.wait_for_timeout(300)
    rotated = state(page)
    for key in ['ticks', 'session', 'cranes', 'crane_releases', 'visible_crates']:
        assert rotated[key] == paused[key], ('Pause or rotation changed the game', key)
    assert rotated['crane_trolleys'] != paused['crane_trolleys']
    button(page, 'resume', True)
    wait_screen(page, 'playing')
    start_crane_preview(page)
    releases = crane_cycle(page, state(page))
    assert personal_statistics(state(page)) == initial_statistics, 'Ordinary crate releases changed the match history'
    assert not errors, errors
    context.close()
    return {'constant_speed_and_directions':'PASS', 'independent_waits_and_reentry':'PASS',
            'one_crate_per_pass':'PASS', 'pause_and_resize':'PASS',
            'releases':releases, 'screenshots':shots}


def animation_request(page, name, **options):
    page.evaluate('request => window.stackAttackQARequest = request', {'scenario':name, **options})
    page.wait_for_function('window.stackAttackQARequest === null', timeout=5000)
    return state(page)


def animation_step(page, frames, **options):
    return animation_request(page, 'animation_step', frames=frames, **options)


def animation_image(page, dimensions, shots, phase=None):
    path = None
    if phase is not None:
        path = SHOTS / f'animation-{phase}-{dimensions[0]}x{dimensions[1]}.png'
    image = Image.open(io.BytesIO(page.screenshot(path=str(path) if path else None))).convert('RGB')
    assert image.size == dimensions
    if path:
        shots.append(str(path.relative_to(ROOT)))
    return image


def field_crop(image, snapshot, x, y, width, height):
    left, top, field_width, _ = snapshot['field']
    cell = field_width / snapshot['columns']
    scale_x = image.width / snapshot['viewport'][0]
    scale_y = image.height / snapshot['viewport'][1]
    return image.crop((round((left + x * cell) * scale_x), round((top + y * cell) * scale_y),
                       round((left + (x + width) * cell) * scale_x), round((top + (y + height) * cell) * scale_y)))


def wood_fraction(image):
    return sum(r > 120 and r > g * 1.15 and g > b * 1.1 for r, g, b in image.get_flattened_data()) / (image.width * image.height)


def warm_pixels(image):
    return sum(r >= 231 and 160 <= g <= 215 and 90 <= b <= 142 for r, g, b in image.get_flattened_data())


def hero_height(image, snapshot):
    x, y = snapshot['player']
    region = field_crop(image, snapshot, x - .48, y - .15, 1.52, 1.05)
    colors = {(240,186,132), (39,123,130), (94,169,163), (215,67,56), (241,187,131), (121,88,60)}
    # The glove and boot strokes are still slightly translucent at the squash frame.
    rows = []
    for line in range(region.height):
        scanline = region.crop((0, line, region.width, line + 1)).get_flattened_data()
        if any(max(abs(channel - target) for channel, target in zip(pixel, marker)) <= 5
               for pixel in scanline for marker in colors):
            rows.append(line)
    assert rows, ('No workshop hero pixels found', image.size)
    return max(rows) - min(rows) + 1


def assert_frozen_animation(before, after, phase=True):
    keys = ['ticks', 'active_duration_ms', 'state', 'loss_reason', 'score', 'lines', 'player',
            'visible_crates', 'cranes', 'crane_releases']
    if phase:
        keys.extend(['clear_animation', 'crush_animation'])
    for key in keys:
        assert before[key] == after[key], ('Frozen match state changed', key, before[key], after[key])
    assert personal_statistics(before) == personal_statistics(after)


def pause_animation_and_rotate(page, before, dimensions):
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    unheld = animation_step(page, 0, animation_hold=False)
    assert not unheld['animation_held']
    rotated = dimensions[::-1] if dimensions[0] != dimensions[1] else (844, 390)
    for width, height in (rotated, dimensions):
        page.set_viewport_size({'width':width, 'height':height})
        page.wait_for_function('layout => window.stackAttackState.layout === layout',
                               arg='landscape' if width > height else 'portrait', timeout=5000)
        page.wait_for_timeout(180)
        after = state(page)
        assert after['screen'] == 'paused'
        assert_frozen_animation(before, after)
        if (width, height) == rotated:
            assert before['field'] != after['field']
        else:
            assert before['field'] == after['field']
    held = animation_step(page, 0, animation_hold=True)
    assert held['animation_held']
    button(page, 'resume', True)
    wait_screen(page, 'playing')
    assert_frozen_animation(before, state(page))


def clear_animation_check(page, dimensions, shots):
    loaded = animation_request(page, 'chain', animation_hold=True)
    assert loaded['animation_held'] and loaded['clear_animation']['phase'] == 'none'
    still = animation_image(page, dimensions, shots)
    began = animation_step(page, 1)
    assert began['state'] == 'clearing' and began['clear_animation']['phase'] == 'glow'
    glow = animation_step(page, 5)
    assert glow['clear_animation']['phase'] == 'glow' and 0 < glow['clear_animation']['elapsed'] < .08
    assert glow['lines'] == 1 and glow['score'] == 100
    glow_image = animation_image(page, dimensions, shots, 'glow')

    retreat = animation_step(page, 14)
    assert retreat['clear_animation']['phase'] == 'retreat' and .08 < retreat['clear_animation']['elapsed'] < .22
    for key in ['player', 'visible_crates', 'cranes', 'crane_releases', 'lines', 'score']:
        assert glow[key] == retreat[key], ('The departing row moved physics before collapse', key)
    assert glow['clear_animation']['ids'] == retreat['clear_animation']['ids']
    retreat_image = animation_image(page, dimensions, shots, 'retreat')
    rows = retreat['rows']
    columns = retreat['columns']
    row_middle = (.1, rows - .8, columns - .2, .6)
    lower_before = field_crop(still, loaded, *row_middle).convert('L')
    lower_glow = field_crop(glow_image, glow, *row_middle).convert('L')
    assert ImageStat.Stat(lower_glow).mean[0] > ImageStat.Stat(lower_before).mean[0] + 8, (
        'The retiring row did not brighten', dimensions)
    stroke_widths = []
    for edge in (rows - 1, rows):
        # At some scales only one horizontal edge lands on a pixel center.
        band = field_crop(glow_image, glow, .1, edge - .15, columns - .2, .3)
        for y in range(band.height):
            stroke = band.crop((0, y, band.width, y + 1)).get_flattened_data()
            stroke_widths.append(stroke.count((255,194,118)) / band.width)
    assert max(stroke_widths) >= .75, ('The retiring row did not render a continuous amber outline', dimensions)
    lip = field_crop(retreat_image, retreat, .12, rows - .17, columns - .24, .17)
    # Either surface of the lip can be the one sampled on the smallest canvases.
    lip_colors = {(25,47,57), (98,120,116)}
    assert sum(pixel in lip_colors for pixel in lip.get_flattened_data()) > lip.width / 2, (
        'The receiving slot lip did not render', dimensions)
    for x in (.1, columns - .8):
        ceiling = (x, rows - 1.9, .7, .75)
        assert field_crop(glow_image, glow, *ceiling).tobytes() == field_crop(retreat_image, retreat, *ceiling).tobytes(), (
            'The upper row changed during the retreat', dimensions, x)
        side = (x, rows - .92, .7, .65)
        assert wood_fraction(field_crop(retreat_image, retreat, *side)) < wood_fraction(field_crop(still, loaded, *side)) / 2, (
            'The retreat did not pull the row in from the sides', dimensions, x)

    collapse = animation_step(page, 22)
    assert collapse['clear_animation']['phase'] == 'collapse' and .22 < collapse['clear_animation']['elapsed'] < .47
    departing_ids = set(retreat['clear_animation']['ids'])
    assert len(departing_ids) == columns
    assert {crate['id'] for crate in retreat['visible_crates'] if crate['y'] == rows - 1} == departing_ids
    remaining = {crate['id']:crate for crate in retreat['visible_crates'] if crate['id'] not in departing_ids}
    assert {crate['id'] for crate in collapse['visible_crates']} == remaining.keys()
    descent = collapse['player'][1] - retreat['player'][1]
    assert .25 < descent < .75 and collapse['player'][0] == retreat['player'][0]
    for crate in collapse['visible_crates']:
        origin = remaining[crate['id']]
        assert abs(crate['y'] - origin['y'] - descent) < 1e-5 and crate['x'] == origin['x']
    collapse_image = animation_image(page, dimensions, shots, 'collapse')
    former_top = (.15, rows - 1.9, .65, .25)
    assert wood_fraction(field_crop(collapse_image, collapse, *former_top)) < .1
    assert wood_fraction(field_crop(still, loaded, *former_top)) > .25
    pause_animation_and_rotate(page, collapse, dimensions)

    second = animation_step(page, 16)
    assert second['state'] == 'clearing' and second['clear_animation']['phase'] == 'glow'
    assert set(second['clear_animation']['ids']) == remaining.keys()
    assert second['score'] == 200 and second['lines'] == 2
    assert abs(second['player'][1] - began['player'][1] - 1) < 1e-5
    finished = animation_step(page, 57)
    assert finished['state'] == 'playing' and finished['clear_animation']['phase'] == 'none'
    assert finished['score'] == 200 and finished['lines'] == 2 and not finished['visible_crates']
    assert abs(finished['player'][1] - began['player'][1] - 2) < 1e-5
    assert not finished['profile']['matches']
    return {name: snapshot['clear_animation']['elapsed'] for name, snapshot in
            [('glow',glow), ('retreat',retreat), ('collapse',collapse)]}


def loss_animation_check(page, dimensions, shots):
    loaded = animation_request(page, 'crush', animation_hold=True)
    assert loaded['animation_held'] and loaded['state'] == 'playing'
    standing_height = hero_height(animation_image(page, dimensions, shots), loaded)
    for _ in range(24):
        hit = animation_step(page, 6)
        if hit['state'] == 'over':
            break
    assert hit['crush_animation']['active'] and hit['screen'] == 'playing' and hit['loss_reason'] == 'crushed'
    assert 0 <= hit['crush_animation']['progress'] < .15
    assert hit['crush_animation']['impact_crate'] in {crate['id'] for crate in hit['visible_crates']}
    assert 'again' not in hit['buttons'] and 'home' not in hit['buttons']
    crushed, = hit['profile']['matches']
    assert {key:crushed[key] for key in ('reason', 'score', 'lines', 'crates', 'best_combo')} == {
        'reason':'crushed', 'score':200, 'lines':2, 'crates':20, 'best_combo':2}
    assert crushed['duration_ms'] == hit['active_duration_ms']
    assert abs(crushed['duration_ms'] - hit['ticks'] * 1000 / 120) <= .5 + 1e-9
    animation_image(page, dimensions, shots, 'crush-impact')

    page.keyboard.down('ArrowRight')
    page.keyboard.press('Space')
    try:
        squash = animation_step(page, 15)
    finally:
        page.keyboard.up('ArrowRight')
    assert squash['crush_animation']['active'] and squash['screen'] == 'playing'
    assert hit['crush_animation']['progress'] < squash['crush_animation']['progress'] < 1
    assert_frozen_animation(hit, squash, phase=False)
    squash_image = animation_image(page, dimensions, shots, 'crush')
    squash_height = hero_height(squash_image, squash)
    assert squash_height < standing_height * .7, ('The hero sprite did not squash', dimensions, standing_height, squash_height)
    pause_animation_and_rotate(page, squash, dimensions)

    settled = animation_step(page, 17)
    assert settled['screen'] == 'playing' and settled['crush_animation']['active']
    assert .62 < settled['crush_animation']['progress'] < .9
    assert_frozen_animation(hit, settled, phase=False)
    settled_image = animation_image(page, dimensions, shots, 'crush-settled')
    impact_x = next(crate['x'] for crate in hit['visible_crates'] if crate['id'] == hit['crush_animation']['impact_crate'])
    for offset in (0, 1/3, 2/3):
        star = field_crop(settled_image, settled, impact_x + offset, settled['rows'] - 1.7, 1/3, .47)
        assert warm_pixels(star) >= 3, ('A crush star did not render above the crate', dimensions, offset)
    animation_step(page, 0, animation_hold=False)
    wait_screen(page, 'over')
    result = state(page)
    assert not result['crush_animation']['active']
    assert_frozen_animation(hit, result, phase=False)
    score_only_result(page)
    animation_image(page, dimensions, shots, 'crushed-result')

    button(page, 'again', True)
    wait_screen(page, 'playing')
    restarted = state(page)
    assert restarted['session'] == hit['session'] + 1 and restarted['score'] == 0
    assert not restarted['animation_held'] and not restarted['crush_animation']['active']
    animation_request(page, 'overflow', animation_hold=True)
    overflow = animation_step(page, 1)
    assert overflow['screen'] == overflow['state'] == 'over' and overflow['loss_reason'] == 'overflow'
    assert not overflow['crush_animation']['active']
    assert [match['reason'] for match in overflow['profile']['matches']] == ['overflow', 'crushed']
    assert overflow['profile']['matches'][1] == crushed
    lost_to_stack = overflow['profile']['matches'][0]
    assert {key:lost_to_stack[key] for key in ('score', 'lines', 'crates', 'best_combo', 'duration_ms')} == {
        'score':0, 'lines':0, 'crates':0, 'best_combo':0, 'duration_ms':overflow['active_duration_ms']}
    wait_screen(page, 'over')
    score_only_result(page)
    animation_image(page, dimensions, shots, 'overflow-result')
    return {'crush_progress':squash['crush_animation']['progress'], 'duration_ms':crushed['duration_ms'],
            'standing_hero_pixels':standing_height, 'squashed_hero_pixels':squash_height}


def animation_checks(browser):
    checks = []
    for dimensions in WEB_LAYOUT_VIEWPORTS:
        width, height = dimensions
        context = browser.new_context(viewport={'width':width, 'height':height}, has_touch=True, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page, 'menu')
        button(page, 'play', True)
        wait_screen(page, 'playing')
        check_touch_control_layout(state(page))
        page.mouse.move(2, 2)
        shots = []
        clear = clear_animation_check(page, dimensions, shots)
        crush = loss_animation_check(page, dimensions, shots)
        assert not errors, errors
        check = {'viewport':list(dimensions), 'clear_elapsed':clear, **crush, 'pause_and_resize':'PASS', 'touch_controls_clear':'PASS',
                 'chain_and_match_statistics':'PASS', 'overflow_immediate':'PASS', 'screenshots':shots,
                 'screenshot_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in shots}}
        checks.append(check)
        print('ANIMATIONS', json.dumps(check), flush=True)
        context.close()
    return checks


def keyboard_jump_checks(browser):
    context = browser.new_context(viewport={'width':844, 'height':390}, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    menu = state(page)
    page.keyboard.press('ArrowUp')
    after_menu = animation_step(page, 0)
    assert after_menu['screen'] == 'menu' and after_menu['panel']['focus'] in after_menu['buttons']
    assert not after_menu['jump_pending'], 'ArrowUp queued a jump in the main menu'
    for key in ('session', 'ticks', 'player', 'score'):
        assert after_menu[key] == menu[key], ('ArrowUp changed the match from the main menu', key)
    assert personal_statistics(after_menu) == personal_statistics(menu)

    button(page, 'play')
    wait_screen(page, 'playing')
    animation_request(page, 'push', animation_hold=True)
    grounded = animation_step(page, 1)
    assert grounded['grounded'], 'The jump fixture must start on the floor'
    page.keyboard.press('Escape')
    wait_screen(page, 'paused')
    page.keyboard.press('ArrowUp')
    paused = animation_step(page, 0)
    assert paused['screen'] == 'paused' and paused['panel']['focus'] in paused['buttons']
    assert not paused['jump_pending'], 'ArrowUp queued a jump while paused'
    assert_frozen_animation(grounded, paused)
    page.keyboard.press('Escape')
    wait_screen(page, 'playing')
    resumed = animation_step(page, 12)
    assert resumed['grounded'] and resumed['player'] == grounded['player']

    jumps = {}
    for key in ('ArrowUp', 'Space'):
        animation_request(page, 'push', animation_hold=True)
        grounded = animation_step(page, 1)
        assert grounded['grounded'] and not grounded['jump_pending']
        page.keyboard.press(key)
        queued = animation_step(page, 0)
        assert queued['jump_pending'], ('The jump key did not reach the game', key)
        airborne = animation_step(page, 12)
        rise = grounded['player'][1] - airborne['player'][1]
        assert airborne['screen'] == 'playing' and not airborne['grounded'] and rise > .35, (
            'The hero did not jump', key, rise)
        assert airborne['player'][0] == grounded['player'][0], ('The jump key moved the hero sideways', key)
        jumps[key] = rise
    assert personal_statistics(airborne) == personal_statistics(menu)
    assert not errors, errors
    context.close()
    return {'menu_isolation':'PASS', 'pause_isolation':'PASS', 'jump_rise_cells':jumps}


def assert_boots(snapshot, equipped, charges, rows=0, pending=False):
    expected = (equipped, charges, rows, pending)
    actual = tuple(snapshot[key] for key in
                   ('boots_equipped', 'boots_charges', 'equipment_rows', 'equipment_pending'))
    assert actual == expected, ('Unexpected equipment state', snapshot['screen'], snapshot['lines'], actual, expected)


def clear_boots_rows(page, count, expect_offer):
    before = state(page)
    seeded = animation_request(page, 'boots_rows', count=count, animation_hold=True)
    assert seeded['animation_held'] and seeded['lines'] == before['lines']
    current = animation_step(page, 1)
    assert current['lines'] == before['lines'] + 1 and current['state'] == 'clearing'
    assert current['screen'] == 'playing', 'Equipment interrupted the clear animation'
    for _ in range(count):
        if current['state'] != 'clearing':
            break
        current = animation_step(page, 60)
    assert current['lines'] == before['lines'] + count, 'Equipment interrupted a combo'
    assert current['score'] == before['score'] + 100 * count and current['state'] == 'playing'
    assert current['clear_animation']['phase'] == 'none'
    assert current['screen'] == ('equipment' if expect_offer else 'playing')
    if expect_offer:
        wait_screen(page, 'equipment')
    return state(page)


def check_boots_rect(snapshot, rect):
    width, height = snapshot['viewport']
    x, y, w, h = rect
    assert -1 <= x and -1 <= y and w > 0 and h > 0 and x + w <= width + 1 and y + h <= height + 1, (
        'Equipment content is outside the viewport', snapshot['screen'], snapshot['viewport'], rect)


def check_boots_panel(snapshot, actions):
    panel = snapshot['panel']
    check_boots_rect(snapshot, panel['rect'])
    assert panel['scroll_containers'] == 0
    assert {item['name'] for item in panel['items'] if item['focusable']} == actions
    assert panel['focus'] in actions
    button_rects = []
    for item in panel['items']:
        check_boots_rect(snapshot, item['rect'])
        if item['name'] in actions:
            x, y, w, h = item['rect']
            assert w >= 48 and h >= 48, ('Undersized equipment action', item)
            for ax, ay, aw, ah in button_rects:
                assert x + w <= ax or ax + aw <= x or y + h <= ay or ay + ah <= y, (
                    'Equipment actions overlap', item)
            button_rects.append(item['rect'])
    labels = {item['name']: item['text'] for item in panel['items']}
    if 'equip' in actions:
        assert labels['equipment_title'] == 'Ботинки-ракеты' and snapshot['missing_menu_glyphs'] == '', labels
    return labels


def check_boots_hud(snapshot, charges):
    hud = snapshot['boots_hud']
    if charges is None:
        assert not hud, ('Unequipped boots showing in HUD', hud)
        return
    assert hud['text'] == str(charges), ('Incorrect charge counter', hud, charges)
    check_boots_rect(snapshot, hud['rect'])
    if 'pause' in snapshot['buttons']:
        assert hud['rect'][0] + hud['rect'][2] <= snapshot['buttons']['pause'][0], (
            'Boots HUD overlaps pause', hud, snapshot['buttons']['pause'])


def check_boots_pause(snapshot, charges):
    slots = check_boots_panel(snapshot, {'resume', 'restart', 'home'})
    assert slots['slot_head'] == slots['slot_hands'] == '—', slots
    assert slots['slot_feet'] == f'{charges} / 10', slots
    check_boots_hud(snapshot, charges)


def resize_boots_view(page, dimensions):
    width, height = dimensions
    page.set_viewport_size({'width':width, 'height':height})
    page.wait_for_function('([w, h]) => { const [x, y] = window.stackAttackState.viewport; '
                           'return Math.abs(x * h - y * w) < 2 * Math.max(w, h); }',
                           arg=dimensions)
    page.wait_for_timeout(160)
    return state(page)


def boots_shot(page, phase, shots):
    size = page.viewport_size
    name = f'boots-{phase}-{size["width"]}x{size["height"]}.png'
    shot = screenshot(page, name)
    shots.append(shot)
    return shot


def check_boots_exhaust(image, snapshot, emitting):
    for nozzle_x in JUMP_NOZZLES:
        nozzle = hero_sprite_crop(image, snapshot, snapshot['player'], snapshot['facing'],
                                  (nozzle_x - 5, 38, nozzle_x + 5, 47))
        exhaust = hero_sprite_crop(image, snapshot, snapshot['player'], snapshot['facing'],
                                   (nozzle_x - 5, 46, nozzle_x + 5, 62))
        assert color_pixels(nozzle, NOZZLE_COLORS) > 0, (
            'Jump nozzle was not rendered', snapshot['viewport'], snapshot['facing'], nozzle_x)
        core = color_pixels(exhaust, {EXHAUST_CORE})
        flame = color_pixels(exhaust, {EXHAUST_FLAME})
        assert (core > 0) == (flame > 0) == emitting, (
            'Incorrect rocket exhaust at the jump nozzle', snapshot['viewport'], snapshot['facing'], nozzle_x, core, flame)


def select_boots_action(page, action, touch):
    if touch:
        button(page, action, True)
    else:
        focus_button(page, action)
        page.keyboard.press('Enter')
    wait_screen(page, 'playing')
    return state(page)


def press_boots_jump(page, touch):
    if touch:
        page.touchscreen.tap(*point(page, state(page)['controls']['jump']))
    else:
        page.keyboard.press('ArrowUp')


def hold_boots_jump(page, touch):
    if touch:
        controls = state(page)['controls']
        x, y = point(page, controls['jump'])
        left_x, left_y = point(page, controls['left'])
        cdp = page.context.new_cdp_session(page)
        try:
            cdp.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[{'x':x, 'y':y, 'id':1}]})
            first = animation_step(page, 34)
            cdp.send('Input.dispatchTouchEvent',
                     {'type':'touchMove', 'touchPoints':[{'x':left_x, 'y':left_y, 'id':1}]})
            dragged = animation_step(page, 1)
            assert dragged['player'][0] < first['player'][0], 'Dragging onto Left did not move the hero'
            cdp.send('Input.dispatchTouchEvent', {'type':'touchMove', 'touchPoints':[{'x':x, 'y':y, 'id':1}]})
            return animation_step(page, 1)
        finally:
            cdp.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
            cdp.detach()
    page.keyboard.down('Space')
    try:
        animation_step(page, 17)
        page.keyboard.down('Space')  # Playwright sends an auto-repeat for a key already held down.
        return animation_step(page, 17)
    finally:
        page.keyboard.up('Space')


def use_air_jump(page, touch, shots, *, held=False, capture=False):
    before = state(page)
    charges = before['boots_charges']
    rows = before['equipment_rows']
    assert before['grounded'] and charges > 0
    if held:
        first = hold_boots_jump(page, touch)
    else:
        press_boots_jump(page, touch)
        first = animation_step(page, 34)
    assert_boots(first, True, charges, rows)
    assert not first['grounded'] and first['player'][1] < before['player'][1] - .5
    if capture:
        shot = boots_shot(page, 'first-jump' if charges > 1 else 'last-first-jump', shots)
        check_boots_exhaust(Image.open(ROOT / shot).convert('RGB'), first, False)
    press_boots_jump(page, touch)
    boosted = animation_step(page, 1)
    assert_boots(boosted, True, charges - 1, rows)
    assert not boosted['grounded'] and boosted['player_velocity'][1] < first['player_velocity'][1] - 2
    check_boots_hud(boosted, charges - 1)
    if capture:
        airborne = animation_step(page, 5)
        phase = 'last-air-jump' if charges == 1 else 'air-jump'
        shot = boots_shot(page, phase, shots)
        check_boots_exhaust(Image.open(ROOT / shot).convert('RGB'), airborne, True)
        if charges == 1:
            size = page.viewport_size
            original = (size['width'], size['height'])
            rotated = resize_boots_view(page, original[::-1])
            assert_frozen_animation(airborne, rotated)
            assert rotated['player_velocity'] == airborne['player_velocity']
            assert_boots(rotated, True, 0, rows)
            check_touch_control_layout(rotated)
            check_boots_hud(rotated, 0)
            shot = boots_shot(page, phase, shots)
            check_boots_exhaust(Image.open(ROOT / shot).convert('RGB'), rotated, True)
            resize_boots_view(page, original)
    press_boots_jump(page, touch)
    again = animation_step(page, 1)
    assert_boots(again, True, charges - 1, rows)
    assert again['player_velocity'][1] > boosted['player_velocity'][1], 'A third press granted another air jump'
    if charges == 1:
        descending = animation_step(page, 48)
        assert not descending['grounded'] and descending['player_velocity'][1] > 0
        assert_boots(descending, True, 0, rows)
        check_boots_hud(descending, 0)
        if capture:
            check_boots_exhaust(Image.open(io.BytesIO(page.screenshot())).convert('RGB'), descending, False)
    landed = animation_step(page, 180)
    assert landed['grounded'] and landed['player'] == [first['player'][0], before['player'][1]]
    assert_boots(landed, charges > 1, charges - 1, rows)
    check_boots_hud(landed, charges - 1 if charges > 1 else None)
    if capture and charges == 1:
        boots_shot(page, 'last-landing', shots)


def open_boots_game(browser, dimensions, errors):
    width, height = dimensions
    context = browser.new_context(viewport={'width':width, 'height':height}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.on('requestfailed', lambda request: errors.append(request.url))
    page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
    page.goto(URL)
    wait_screen(page, 'menu')
    button(page, 'play', True)
    wait_screen(page, 'playing')
    assert_boots(state(page), False, 0)
    check_boots_hud(state(page), None)
    check_touch_control_layout(state(page))
    return context, page


def boots_checks(browser):
    portrait, landscape = (390, 844), (844, 390)
    shots, errors = [], []
    context, page = open_boots_game(browser, portrait, errors)
    initial_stats = personal_statistics(state(page))
    assert_boots(clear_boots_rows(page, 4, False), False, 0, 4)
    choice = clear_boots_rows(page, 2, True)
    assert_boots(choice, False, 0, 1, True)
    check_boots_panel(choice, {'equip', 'skip'})
    boots_shot(page, 'choice', shots)
    animation_step(page, 0, animation_hold=False)
    page.keyboard.press('ArrowRight')
    page.keyboard.press('ArrowUp')
    still_open = animation_step(page, 0)
    assert still_open['screen'] == 'equipment' and not still_open['jump_pending']
    assert_frozen_animation(choice, still_open)
    rotated = resize_boots_view(page, landscape)
    assert_frozen_animation(choice, rotated)
    assert_boots(rotated, False, 0, 1, True)
    assert not rotated['jump_pending']
    check_boots_panel(rotated, {'equip', 'skip'})
    boots_shot(page, 'choice', shots)
    animation_step(page, 0, animation_hold=True)
    equipped = select_boots_action(page, 'equip', False)
    assert_boots(equipped, True, 10, 1)
    check_boots_hud(equipped, 10)
    check_touch_control_layout(equipped)
    boots_shot(page, 'hud', shots)

    assert_boots(clear_boots_rows(page, 4, False), True, 10)
    animation_request(page, 'boots_jump', animation_hold=True)
    animation_step(page, 1)
    use_air_jump(page, False, shots, held=True, capture=True)
    use_air_jump(page, True, shots, held=True)
    use_air_jump(page, False, shots)
    before_pause = state(page)
    assert_boots(before_pause, True, 7)
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    animation_step(page, 0, animation_hold=False)
    for dimensions in (landscape, portrait):
        paused = resize_boots_view(page, dimensions)
        assert paused['screen'] == 'paused'
        assert_frozen_animation(before_pause, paused)
        assert_boots(paused, True, 7)
        check_boots_pause(paused, 7)
        boots_shot(page, 'pause', shots)
    animation_step(page, 0, animation_hold=True)
    button(page, 'resume', True)
    wait_screen(page, 'playing')
    assert_frozen_animation(before_pause, state(page))
    boots_shot(page, 'hud', shots)

    offered = clear_boots_rows(page, 5, True)
    assert_boots(offered, True, 7, pending=True)
    labels = check_boots_panel(offered, {'equip', 'skip'})
    assert labels['equipment_old_charges'] == '7' and labels['equipment_new_charges'] == '10', labels
    boots_shot(page, 'replacement', shots)
    assert_boots(select_boots_action(page, 'skip', True), True, 7)
    offered = clear_boots_rows(page, 5, True)
    assert_boots(offered, True, 7, pending=True)
    offered = resize_boots_view(page, landscape)
    check_boots_panel(offered, {'equip', 'skip'})
    boots_shot(page, 'replacement', shots)
    assert_boots(select_boots_action(page, 'equip', True), True, 10)

    animation_request(page, 'boots_jump', animation_hold=True)
    animation_step(page, 1)
    page.keyboard.down('ArrowLeft')
    try:
        assert animation_step(page, 1)['facing'] == -1
    finally:
        page.keyboard.up('ArrowLeft')
    for remaining in range(10, 0, -1):
        use_air_jump(page, False, shots, capture=remaining == 1)
    choice = clear_boots_rows(page, 6, True)
    assert_boots(choice, False, 0, 1, True)
    equipped = select_boots_action(page, 'equip', False)
    assert_boots(equipped, True, 10, 1)
    page.keyboard.press('Escape')
    wait_screen(page, 'paused')
    button(page, 'restart', True)
    wait_screen(page, 'playing')
    restarted = state(page)
    assert restarted['session'] == equipped['session'] + 1 and restarted['score'] == restarted['lines'] == 0
    assert_boots(restarted, False, 0)
    check_boots_hud(restarted, None)
    assert personal_statistics(restarted) == initial_stats
    context.close()

    for dimensions in ((320, 568), (568, 320), (360, 360)):
        context, page = open_boots_game(browser, dimensions, errors)
        choice = clear_boots_rows(page, 5, True)
        assert_boots(choice, False, 0, pending=True)
        check_boots_panel(choice, {'equip', 'skip'})
        boots_shot(page, 'choice', shots)
        equipped = select_boots_action(page, 'equip', True)
        assert_boots(equipped, True, 10)
        check_boots_hud(equipped, 10)
        check_touch_control_layout(equipped)
        boots_shot(page, 'hud', shots)
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        paused = state(page)
        assert_frozen_animation(equipped, paused)
        check_boots_pause(paused, 10)
        boots_shot(page, 'pause', shots)
        context.close()
    assert not errors, errors
    return {'offer_after_five_and_combo_surplus':'PASS', 'full_charge_suppression':'PASS',
            'pause_and_offer_resize':'PASS', 'skip_and_replacement':'PASS', 'keyboard_and_touch':'PASS',
            'separate_press_and_one_air_jump_per_landing':'PASS', 'last_charge_and_restart':'PASS',
            'rocket_exhaust_on_second_jump':'PASS',
            'screenshots':shots, 'screenshot_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in shots}}


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
        assert not snapshot['boots_equipped']
        game = screenshot(page,f'workshop-game-{width}x{height}.png')
        image = Image.open(ROOT / game).convert('RGB')
        red = check_hero_hand(image, snapshot, snapshot['player'], snapshot['facing'])
        fx,fy,fw,_ = snapshot['field'];px,py=snapshot['player']
        cell=fw/snapshot['columns'];scale=page.locator('canvas').bounding_box()['width']/snapshot['viewport'][0]
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
        checks.append({'viewport':[width,height],'reference_style':'workshop','magnet_pixels':red,'unchanged_grid':[10,11],
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
    for dimensions in WEB_LAYOUT_VIEWPORTS:
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
        full_check = not any(vars(args).values())
        boots = boots_checks(browser) if args.boots_only or full_check else {}
        if boots:
            print('BOOTS', json.dumps(boots), flush=True)
        if args.boots_only:
            (BUILD/'boots-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':boots,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        keyboard = keyboard_jump_checks(browser) if args.keyboard_only or full_check else {}
        if keyboard:
            print('KEYBOARD', json.dumps(keyboard), flush=True)
        if args.keyboard_only:
            (BUILD/'keyboard-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':keyboard,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        animations = animation_checks(browser) if args.animations_only or full_check else []
        if args.animations_only:
            (BUILD/'animation-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':animations,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        cranes = crane_checks(browser) if args.cranes_only or full_check else {}
        if cranes:
            print('CRANES', json.dumps(cranes), flush=True)
        if args.cranes_only:
            (BUILD/'crane-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':cranes,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
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
            check_touch_control_layout(rotated)
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
        report = {'status':'PASS','browser':browser.version,'renderer':'SwiftShader', 'boots':boots, 'keyboard':keyboard, 'animations':animations, 'cranes':cranes, 'statistics':statistics, 'wooden_crates':crates,'workshop':workshop,'menu_layouts':menus, 'sprite_poses':sprites, 'ui_batch':ui_batch, 'game_over':results_over,'button_styles':button_styles,
                  'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),
                  'page_errors':all_errors,'failed_requests':all_failed_requests,'checks':results}
        (BUILD/'web-check.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
        browser.close()
finally:
    server.shutdown()
    server.server_close()
