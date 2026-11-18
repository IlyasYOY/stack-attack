#!/usr/bin/env python3
"""End-to-end checks against the actual exported game; debug fixtures require ?qa=1."""
import functools
import argparse
import base64
from contextlib import contextmanager
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
group.add_argument('--crates-only', action='store_true', help='Check ten rendered wooden crate appearances and their lifetime')
group.add_argument('--animations-only', action='store_true', help='Check row clear and crush transitions and capture their rendered phases')
group.add_argument('--keyboard-only', action='store_true', help='Check jump keys and menu keyboard isolation')
group.add_argument('--loot-only', action='store_true', help='Record deterministic ground loot, impacts and swaps')
group.add_argument('--bonuses-only', action='store_true', help='Check expanded equipment in combination')
group.add_argument('--boots-only', action='store_true', help='Check ground pickups, air jumps and responsive boots UI')
group.add_argument('--helmet-only', action='store_true', help='Check helmet contacts, recovery, rewards and layouts')
group.add_argument('--mallet-only', action='store_true', help='Check wooden mallet inputs, equipment, physics and statistics')
group.add_argument('--gloves-only', action='store_true', help='Check hold-to-pull controls, charges and rewards')
args = parser.parse_args()

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
SHOTS = BUILD / 'screenshots'
WEB_LAYOUT_VIEWPORTS = (
    (390, 844), (844, 390), (320, 568), (568, 320), (344, 882), (882, 344),
    (768, 1004), (1004, 768), (360, 360),
)
NEW_GEAR = ('strong_arms', 'speed_boots', 'lamp_helmet', 'spring_boots')
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
    expected = {'left', 'right', 'jump'}
    if snapshot['gloves_charges'] > 0:
        expected.add('grab')
    if snapshot['mallet_charges'] > 0:
        expected.add('mallet')
    if snapshot['lamp_helmet_charges'] > 0:
        expected.add('lamp')
    assert snapshot['controls'].keys() == expected
    checked = []
    for action, rect in snapshot['controls'].items():
        x, y, w, h = rect
        assert 0 <= x and 0 <= y and x + w <= width + 1 and y + h <= height + 1, (
            'Touch control is outside the viewport', action, rect, snapshot['viewport'])
        assert x + w <= field_x or x >= field_x + field_width or y + h <= field_y or y >= field_y + field_height, (
            'Touch control overlaps the field', action, rect, snapshot['field'], snapshot['viewport'])
        for other_action, (ox, oy, ow, oh) in checked:
            assert x + w <= ox or ox + ow <= x or y + h <= oy or oy + oh <= y, (
                'Touch controls overlap', action, other_action, rect, snapshot['viewport'])
        checked.append((action, rect))


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
    # Sample all three scarf colours. At small nearest-neighbour scales the middle stripe can vanish.
    with Image.open(ROOT / 'art/hero_idle.png') as idle:
        scarf = {idle.getpixel((x, 22))[:3] for x in (8, 9, 10)}
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
                band = [x for y in range(22, 26) for x in range(image.width) if image.getpixel((x,y))[:3] in scarf]
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
                    points = [(x,y) for y in range(top,bottom) for x in range(left,right) if image.getpixel((x,y)) in scarf]
                    assert points, ('Torso marker was not rendered', dimensions, pose, facing)
                    xs, ys = zip(*points)
                    center = (min(xs)+max(xs)+1)/2
                    expected_center = (fx+(px+snapshot['player_size'][0]/2)*cell)*scale
                    crop_hash = hashlib.sha256(image.crop((left,top,right,bottom)).tobytes()).hexdigest()
                    bx, by, bw, bh = snapshot['equipment_body']
                    body_crop = image.crop(tuple(round(v * scale) for v in (bx, by, bx + bw, by + bh)))
                    body_hash = hashlib.sha256(body_crop.tobytes()).hexdigest()
                    red = check_hero_hand(image, snapshot, snapshot['player'], facing)
                    feet = hero_sprite_crop(image, snapshot, snapshot['player'], facing, (0, 32, 32, 48))
                    rocket_pixels = color_pixels(feet, ROCKET_BOOT_COLORS)
                    assert (rocket_pixels > 0) == equipped, (
                        'Rocket boots did not render at the feet as expected', dimensions, pose, facing, equipped, rocket_pixels)
                    poses.append({'pose':pose,'boots_equipped':equipped,'magnet_pixels':red,'rocket_boot_pixels':rocket_pixels,
                                  'facing':facing,'frame':frame,'player':snapshot['player'],
                                  'torso_center_x':center,'body_sha256':body_hash,'marker_bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1],
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
                assert len({samples[pose]['body_sha256'] for pose in ('idle', 'walk_stride', 'jump', 'push')}) == 4
                assert samples['idle']['body_sha256'] == samples['walk_recover']['body_sha256']
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
    panel_x, _, panel_width, _ = snapshot['panel']['rect']
    expected = (panel_x + panel_width / 2) * scale
    assert abs(center-expected) <= max(3,scale*2), ('Score pixels are not centered in the result panel',snapshot['score'],center,expected)
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


def equipment_screen_shot(page, name):
    snapshot = state(page)
    x, y, w, h = snapshot['equipment_body']
    px, py, pw, ph = snapshot['panel']['rect']
    fx, fy, fw, fh = snapshot['field']
    axis = snapshot['viewport'][0] / 2
    assert abs(fx + fw / 2 - axis) <= 1 and abs(px + pw / 2 - axis) <= 1, ('Off-center stage', name)
    assert px + pw <= x or py + ph <= y or py >= y + h, ('Panel covers the equipment figure', name)
    path = screenshot(page, name)
    with Image.open(ROOT / path) as frame:
        scale = frame.width / snapshot['viewport'][0]
        figure = frame.convert('RGB').crop(tuple(round(v * scale) for v in (x, y, x + w, y + h)))
    assert color_pixels(figure, menu_shaded_colors({(240, 186, 132)}), 1) > 0, ('Missing character pixels', name)
    return path


def game_over_screens(browser):
    checks = []
    for dimensions in [(390,844),(844,390),(768,1004)]:
        context = browser.new_context(viewport={'width':dimensions[0],'height':dimensions[1]}, has_touch=True, device_scale_factor=1)
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda value: errors.append(str(value)))
        page.goto(URL)
        wait_screen(page, 'menu')
        background = state(page)
        geometry = {key: background[key] for key in ('field', 'crane_rail', 'equipment_body')}
        shots = [equipment_screen_shot(page, f'body-menu-{dimensions[0]}x{dimensions[1]}.png')]
        button(page, 'play', True)
        wait_screen(page, 'playing')
        scenario(page, 'chain')
        page.wait_for_function('window.stackAttackState.score === 200 && window.stackAttackState.state === "playing"')
        for reason, fixture in [('crushed','crush'),('overflow','overflow')]:
            assert all(state(page)[key] == value for key, value in geometry.items())
            # Collect actual items; surviving gear stays on the result screen.
            for kind in ('strong_arms', 'spring_boots'):
                pick_ground(page, kind)
            if reason == 'overflow':
                pick_ground(page, 'lamp_helmet')
            scenario(page, fixture)
            wait_screen(page, 'over')
            score_only_result(page)
            snapshot = state(page)
            assert all(snapshot[key] == value for key, value in geometry.items())
            assert snapshot['strong_arms_hud']['text'] == str(snapshot['strong_arms_charges'])
            assert 'pickup' not in snapshot['buttons'] and 'pause' not in snapshot['buttons']
            assert snapshot['loss_reason'] == reason
            assert snapshot['lines'] == (2 if reason == 'crushed' else 0)
            fixed_panel(page)
            shots.append(equipment_screen_shot(page, f'game-over-{reason}-{dimensions[0]}x{dimensions[1]}.png'))
            button(page, 'again' if reason == 'crushed' else 'home', True)
            wait_screen(page, 'playing' if reason == 'crushed' else 'menu')
        assert not state(page)['strong_arms_hud'], 'Menu kept the completed match equipment'
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
    assert items[prefix+'broken_crates'] == f"Сломано {match.get('broken_crates', '—')}"


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
        'played':2, 'best_score':200, 'total_lines':2, 'total_crates':20, 'total_broken_crates':0,
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
        'broken_crates_value':'0',
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
                assert before['variant'] == after['variant'], ('Crane cargo changed within one pass', before, after)
        for release in snapshot['crane_releases'][len(releases):]:
            index = release['crane']
            crane = snapshot['cranes'][index]
            column = release['column']
            assert not released_this_pass[index], ('Crane released twice on one pass', release)
            assert 0 <= column < columns and not crane['loaded'] and not crane['waiting']
            assert not any((other['tick'], other['column']) == (release['tick'], column) for other in releases)
            crates = [crate for crate in snapshot['visible_crates'] if crate['id'] == release['crate_id']]
            assert len(crates) == 1 and abs(crates[0]['x'] - column) < 1e-5, ('Claw did not release the board crate', release, crates)
            assert crates[0]['variant'] == release['variant'] == crane['variant'], (
                'The released crate must retain its crane cargo appearance', release, crates, crane)
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
    return sprite_pixel_height(region)


def panel_hero_height(image, snapshot):
    x, y, w, h = snapshot['equipment_body']
    sx, sy = image.width / snapshot['viewport'][0], image.height / snapshot['viewport'][1]
    return sprite_pixel_height(image.crop((round(x*sx), round(y*sy), round((x+w)*sx), round((y+h)*sy))))


def sprite_pixel_height(region):
    # Include the cap highlight and trousers that survive nearest-neighbour sampling at eight pixels per cell.
    colors = {(240,186,132), (39,123,130), (94,169,163), (119,193,177), (164,156,132),
              (215,67,56), (241,187,131), (121,88,60)}
    # The glove and boot strokes are still slightly translucent at the squash frame.
    rows = []
    for line in range(region.height):
        scanline = region.crop((0, line, region.width, line + 1)).get_flattened_data()
        if any(max(abs(channel - target) for channel, target in zip(pixel, marker)) <= 5
               for pixel in scanline for marker in colors):
            rows.append(line)
    assert rows, ('No workshop hero pixels found', region.size)
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
        assert crate['variant'] == origin['variant'], ('Descent changed a crate appearance', origin, crate)
    collapse_image = animation_image(page, dimensions, shots, 'collapse')
    former_top = (.15, rows - 1.9, .65, .25)
    assert wood_fraction(field_crop(collapse_image, collapse, *former_top)) < .1
    assert wood_fraction(field_crop(still, loaded, *former_top)) > .25
    pause_animation_and_rotate(page, collapse, dimensions)

    second = animation_step(page, 16)
    assert second['state'] == 'clearing' and second['clear_animation']['phase'] == 'glow'
    assert set(second['clear_animation']['ids']) == remaining.keys()
    assert {crate['id']: crate['variant'] for crate in second['visible_crates']} == {
        crate_id: crate['variant'] for crate_id, crate in remaining.items()}
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
    standing_image = animation_image(page, dimensions, shots)
    standing_height = hero_height(standing_image, loaded)
    standing_panel = panel_hero_height(standing_image, loaded)
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
    assert panel_hero_height(squash_image, squash) < standing_panel * .5, ('Equipment portrait stayed upright at impact', dimensions)
    pause_animation_and_rotate(page, squash, dimensions)

    settled = animation_step(page, 17)
    assert settled['screen'] == 'playing' and settled['crush_animation']['active']
    assert .62 < settled['crush_animation']['progress'] < .9
    assert_frozen_animation(hit, settled, phase=False)
    settled_image = animation_image(page, dimensions, shots, 'crush-settled')
    impact_x = next(crate['x'] for crate in hit['visible_crates'] if crate['id'] == hit['crush_animation']['impact_crate'])
    for offset in (0, 1/3, 2/3):
        star = field_crop(settled_image, settled, impact_x + offset, settled['rows'] - 1.7, 1/3, .47)
        # Each rendered star occupies only two pixels on the smallest square board.
        required_pixels = min(3, max(1, star.width * star.height // 6))
        assert warm_pixels(star) >= required_pixels, ('A crush star did not render above the crate', dimensions, offset)
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
    assert not overflow['crush_animation']['active'] and overflow['crush_animation']['progress'] < 0
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


def assert_boots(snapshot, equipped, charges):
    assert (snapshot['boots_equipped'], snapshot['boots_charges']) == (equipped, charges)


def pick_ground(page, kind, touch=True, charges=-1):
    board = animation_request(page, 'ground_board', items=[[kind, 4.7, 11, charges]], animation_hold=True)
    assert board['nearest_item']['kind'] == kind and 'pickup' in board['buttons']
    if touch:
        button(page, 'pickup', True)
    else:
        page.keyboard.press('KeyE')
    result = animation_step(page, 0)
    assert result[kind + '_charges'] == board['nearest_item']['charges'], (kind, result['nearest_item'])
    return result

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
    return labels


def check_boots_hud(snapshot, charges):
    hud = snapshot['boots_hud']
    if charges is None:
        assert not hud, ('Unequipped boots showing in HUD', hud)
        return
    assert hud['text'] == str(charges), ('Incorrect charge counter', hud, charges)
    check_boots_rect(snapshot, hud['rect'])
    if 'pause' in snapshot['buttons']:
        x, y, w, h = hud['rect']
        px, py, pw, ph = snapshot['buttons']['pause']
        assert x + w <= px or px + pw <= x or y + h <= py or py + ph <= y, (
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
    assert before['grounded'] and charges > 0
    if held:
        first = hold_boots_jump(page, touch)
    else:
        press_boots_jump(page, touch)
        first = animation_step(page, 34)
    assert_boots(first, True, charges)
    assert not first['grounded'] and first['player'][1] < before['player'][1] - .5
    if capture:
        shot = boots_shot(page, 'first-jump' if charges > 1 else 'last-first-jump', shots)
        check_boots_exhaust(Image.open(ROOT / shot).convert('RGB'), first, False)
    press_boots_jump(page, touch)
    boosted = animation_step(page, 1)
    assert_boots(boosted, True, charges - 1)
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
            assert_boots(rotated, True, 0)
            check_touch_control_layout(rotated)
            check_boots_hud(rotated, 0)
            shot = boots_shot(page, phase, shots)
            check_boots_exhaust(Image.open(ROOT / shot).convert('RGB'), rotated, True)
            resize_boots_view(page, original)
    if charges == 1:
        press_boots_jump(page, touch)
    again = animation_step(page, 1)
    assert_boots(again, True, charges - 1)
    assert again['player_velocity'][1] > boosted['player_velocity'][1], 'Unexpected thrust with no new usable press'
    if charges == 1:
        descending = animation_step(page, 48)
        assert not descending['grounded'] and descending['player_velocity'][1] > 0
        assert_boots(descending, True, 0)
        check_boots_hud(descending, 0)
        if capture:
            check_boots_exhaust(Image.open(io.BytesIO(page.screenshot())).convert('RGB'), descending, False)
    landed = animation_step(page, 180)
    assert landed['grounded'] and landed['player'] == [first['player'][0], before['player'][1]]
    assert_boots(landed, charges > 1, charges - 1)
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


def body_slot_checks(page, shots):
    loadout = {'head': 'helmet', 'hands': 'strong_arms', 'feet': 'spring_boots'}
    candidates = {'head': 'lamp_helmet', 'hands': 'mallet', 'feet': 'boots'}
    stacks = [[x, 10 - level, 0] for x, height in [(0, 3), (1, 2), (2, 1), (7, 1), (8, 2), (9, 1)]
              for level in range(height)]
    set_bonus_board(page, loadout)
    for dimensions in [(320, 568), (844, 390), (360, 360)]:
        resize_boots_view(page, dimensions)
        for slot, kind in candidates.items():
            snapshot = animation_request(page, 'ground_board', items=[[kind, 4.85, 11, 2]],
                                         player=[4.2, 10.12], crates=stacks, animation_hold=True)
            check_touch_control_layout(snapshot)
            field_x, field_y, field_w, field_h = snapshot['field']
            _, _, body_w, body_h = snapshot['equipment_body']
            assert 32 <= body_w <= 64 and body_h <= max(48, field_h * .25)
            badges = [snapshot[item + '_hud']['rect'] for item in loadout.values()]
            bx, by, bw, bh = snapshot['equipment_body']
            if by >= field_y + field_h:
                assert all(a[0] + a[2] < b[0] for a, b in zip(badges, badges[1:]))
                assert all(by <= y + h and y >= field_y + field_h and x + w < bx for x, y, w, h in badges)
                assert by + bh < min(r[1] for r in snapshot['controls'].values())
            else:
                assert field_x + field_w < badges[0][0]
                assert all(a[1] + a[3] < b[1] for a, b in zip(badges, badges[1:]))
            assert all(y > field_y + field_h for _, y, _, _ in snapshot['controls'].values())
            pickup = snapshot['buttons']['pickup']
            x, y, w, h = pickup
            check_boots_rect(snapshot, pickup)
            assert w >= 48 and h >= 48
            badge_x, badge_y, badge_w, badge_h = snapshot[loadout[slot] + '_hud']['rect']
            assert badge_x + badge_w <= x
            assert abs(y + h / 2 - badge_y - badge_h / 2) < 2
            assert snapshot['nearest_item']['charges'] == 2
            if dimensions[0] != dimensions[1]:
                shots.append(screenshot(page, f'body-{slot}-{dimensions[0]}x{dimensions[1]}.png'))
            button(page, 'pickup', touch=True)
            exchanged = animation_step(page, 0)
            assert exchanged[kind + '_hud']['text'] == '2'
            page.keyboard.press('KeyE')
            assert animation_step(page, 0)['nearest_item']['kind'] == kind
    set_bonus_board(page, {})


def ground_checks(browser, record=False):
    errors, shots = [], []
    context, page = open_boots_game(browser, (600, 960), errors)
    try:
        body_slot_checks(page, shots)
        resize_boots_view(page, (600, 960))
        kinds = ('helmet', 'lamp_helmet', 'gloves', 'mallet', 'strong_arms', 'speed_boots', 'boots', 'spring_boots')
        items = [[kind, index + 1.5, 11, -1] for index, kind in enumerate(kinds)]
        board = animation_request(page, 'ground_board', items=items, player=[0.05, 10.12], animation_hold=True)
        assert len(board['ground_items']) == 8 and not board['nearest_item']
        shots.append(screenshot(page, 'ground-eight-items.png'))

        if record:
            page.evaluate("""() => {
                const stream = document.querySelector('canvas').captureStream(30);
                const recorder = new MediaRecorder(stream, {mimeType:'video/webm;codecs=vp8'});
                const chunks = [];
                recorder.ondataavailable = event => chunks.push(event.data);
                window.finishLootVideo = () => new Promise(resolve => {
                    recorder.onstop = () => {
                        stream.getTracks().forEach(track => track.stop());
                        const reader = new FileReader();
                        reader.onload = () => resolve(reader.result.split(',')[1]);
                        reader.readAsDataURL(new Blob(chunks, {type:'video/webm'}));
                    };
                    recorder.stop();
                });
                recorder.start();
            }""")
            page.wait_for_timeout(800)

        # Seed 2 makes the real destruction rolls for this row yield three distinct items.
        row = [[column, 10, 0] for column in range(10)]
        animation_request(page, 'ground_board', player=[7.0, 9.12], crates=row, seed=2, animation_hold=True)
        clearing = animation_step(page, 1)
        assert clearing['state'] == 'clearing'
        if record:
            page.wait_for_timeout(350)
        released = animation_step(page, 18)
        for _ in range(24):
            if released['ground_items']:
                break
            released = animation_step(page, 1)
        assert [item['kind'] for item in released['ground_items']] == ['gloves', 'mallet', 'strong_arms']
        assert all(item['vy'] < 0 for item in released['ground_items'])
        animation_step(page, 7)
        shots.append(screenshot(page, 'ground-row-drop.png'))
        animation_step(page, 0, animation_hold=False)
        page.wait_for_function("window.stackAttackState.ground_items.every(i => i.bounced && i.y === 11 && i.vy === 0)")
        settled = animation_step(page, 0, animation_hold=True)
        assert settled['lines'] == 1 and settled['cleared_crates'] == 10 and settled['mallet_charges'] == 0
        page.keyboard.press('KeyE')
        assert animation_step(page, 0)['mallet_charges'] == 3

        # Four real impacts on a five-charge helmet. Seed 14 keeps this shot free of extra loot.
        crates = [[4, 3 + i * 1.5, 0] for i in range(4)]
        animation_request(page, 'ground_board', player=[3, 10.12], crates=crates,
                          items=[['helmet', 4.5, 11, 5]], seed=14, animation_hold=True)
        animation_step(page, 0, animation_hold=False)
        page.wait_for_function("window.stackAttackState.broken_crates === 4")
        damaged = animation_step(page, 0, animation_hold=True)
        assert damaged['ground_items'][0]['charges'] == 1 and 'pickup' not in damaged['buttons']
        page.keyboard.down('ArrowRight')
        try:
            nearby = animation_step(page, 24)
        finally:
            page.keyboard.up('ArrowRight')
        assert nearby['nearest_item']['charges'] == 1 and nearby['helmet_charges'] == 0
        shots.append(screenshot(page, 'ground-helmet-one.png'))
        if record:
            page.wait_for_timeout(750)
        page.keyboard.press('KeyE')
        assert animation_step(page, 0)['helmet_charges'] == 1

        staged = animation_request(page, 'ground_board', player=[4, 10.12],
                                   items=[['lamp_helmet', 4.7, 11, 2]], animation_hold=True)
        assert staged['nearest_item']['kind'] == 'lamp_helmet'
        page.keyboard.down('KeyE')
        try:
            swapped = animation_step(page, 1)
            assert swapped['lamp_helmet_charges'] == 2 and swapped['nearest_item']['charges'] == 1
            page.keyboard.down('KeyE')
            held = animation_step(page, 16)
            assert held['ground_items'] == swapped['ground_items'] and held['lamp_helmet_equipped']
        finally:
            page.keyboard.up('KeyE')
        shots.append(screenshot(page, 'ground-swapped.png'))
        if record:
            page.wait_for_timeout(750)
        button(page, 'pickup', True)
        returned = animation_step(page, 0)
        assert returned['helmet_charges'] == 1 and returned['nearest_item']['kind'] == 'lamp_helmet'
        assert returned['nearest_item']['x'] == staged['nearest_item']['x']
        page.keyboard.down('ArrowLeft')
        try:
            away = animation_step(page, 48)
        finally:
            page.keyboard.up('ArrowLeft')
        assert not away['nearest_item'] and 'pickup' not in away['buttons']
        # Exchange the last helmet charge, then pull a crate onto that same item.
        set_bonus_board(page, {'head': 'helmet', 'hands': 'gloves'}, charges={'helmet': 1})
        px = 4 - state(page)['player_size'][0] - 0.05
        side = animation_request(page, 'ground_board', player=[px, 10.12], facing=1, crates=[[4, 10, 0]],
                                 items=[['lamp_helmet', 3.5, 11, 0]], seed=14, animation_hold=True)
        page.keyboard.press('KeyE')
        discarded = animation_step(page, 0)
        assert discarded['nearest_item']['kind'] == 'helmet' and discarded['nearest_item']['charges'] == 1
        shots.append(screenshot(page, 'ground-side-before.png'))
        if record:
            page.wait_for_timeout(650)
        page.keyboard.down('KeyG')
        try:
            impact = animation_step(page, 20)
        finally:
            page.keyboard.up('KeyG')
        assert impact['broken_crates'] == side['broken_crates'] + 1 and impact['lines'] == side['lines']
        assert not impact['visible_crates'] and not impact['ground_items'] and impact['lamp_helmet_equipped']
        shots.append(screenshot(page, 'ground-side-after.png'))
        if record:
            page.wait_for_timeout(700)
            video = page.evaluate('window.finishLootVideo()')
            (SHOTS / 'ground-scenarios.webm').write_bytes(base64.b64decode(video))
    finally:
        context.close()
    assert not errors, errors
    return {'seeded_row_drops':3, 'helmet_impacts':4, 'keyboard_repeat_and_touch_swap':'PASS', 'screenshots':shots}


def boots_checks(browser):
    portrait, landscape = (390, 844), (844, 390)
    shots, errors = [], []
    context, page = open_boots_game(browser, portrait, errors)
    initial_stats = personal_statistics(state(page))
    equipped = pick_ground(page, 'boots', False)
    assert_boots(equipped, True, 10)
    check_boots_hud(equipped, 10)
    check_touch_control_layout(equipped)
    boots_shot(page, 'hud', shots)

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

    swapped = pick_ground(page, 'boots')
    assert swapped['nearest_item']['charges'] == 7
    assert_boots(swapped, True, 10)
    resize_boots_view(page, landscape)

    animation_request(page, 'boots_jump', animation_hold=True)
    animation_step(page, 1)
    page.keyboard.down('ArrowLeft')
    try:
        assert animation_step(page, 1)['facing'] == -1
    finally:
        page.keyboard.up('ArrowLeft')
    for remaining in range(10, 0, -1):
        use_air_jump(page, False, shots, capture=remaining == 1)
    equipped = pick_ground(page, 'boots', False)
    assert_boots(equipped, True, 10)
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
        equipped = pick_ground(page, 'boots')
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
    return {'ground_pickup_and_swap':'PASS', 'keyboard_and_touch':'PASS',
            'separate_press_and_last_charge':'PASS', 'last_charge_and_restart':'PASS',
            'rocket_exhaust_on_second_jump':'PASS',
            'screenshots':shots, 'screenshot_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in shots}}


def check_helmet_hud(snapshot, charges):
    assert snapshot['helmet_charges'] == charges
    hud = snapshot['helmet_hud']
    if charges == 0:
        assert not hud, ('Broken or absent helmet showing in HUD', hud)
        return
    assert hud['text'] == str(charges), ('Incorrect helmet charge counter', hud, charges)
    check_boots_rect(snapshot, hud['rect'])
    x, y, w, h = hud['rect']
    neighbors = [snapshot['buttons']['pause']] if 'pause' in snapshot['buttons'] else []
    if snapshot['boots_hud']:
        neighbors.append(snapshot['boots_hud']['rect'])
    for ax, ay, aw, ah in neighbors:
        assert x + w <= ax or ax + aw <= x or y + h <= ay or ay + ah <= y, (
            'Helmet counter overlaps another HUD control', hud, neighbors, snapshot['viewport'])


def check_gloves_hud(snapshot, charges):
    assert snapshot['gloves_charges'] == charges
    hud = snapshot['gloves_hud']
    if charges == 0:
        assert not hud, ('Broken or absent gloves showing in HUD', hud)
        return
    assert hud['text'] == str(charges), ('Incorrect glove charge counter', hud, charges)
    check_boots_rect(snapshot, hud['rect'])
    neighbors = [snapshot['buttons']['pause']] if 'pause' in snapshot['buttons'] else []
    neighbors.extend(snapshot[key]['rect'] for key in ('boots_hud', 'helmet_hud') if snapshot[key])
    x, y, w, h = hud['rect']
    for ax, ay, aw, ah in neighbors:
        assert x + w <= ax or ax + aw <= x or y + h <= ay or ay + ah <= y, (
            'Glove counter overlaps another HUD control', hud, neighbors, snapshot['viewport'])



def check_helmet_pause(snapshot, helmet, boots, gloves=0):
    slots = check_boots_panel(snapshot, {'resume', 'restart', 'home'})
    assert slots['slot_head'] == (f'{helmet} / 5' if helmet else '—'), slots
    assert slots['slot_feet'] == (f'{boots} / 10' if boots else '—'), slots
    assert slots['slot_hands'] == (f'{gloves} / 6' if gloves else '—'), slots
    check_gloves_hud(snapshot, gloves)
    check_helmet_hud(snapshot, helmet)
    check_boots_hud(snapshot, boots if boots else None)


def helmet_shot(page, phase, shots):
    size = page.viewport_size
    shot = screenshot(page, f'helmet-{phase}-{size["width"]}x{size["height"]}.png')
    shots.append(shot)


def cleared_metrics(snapshot):
    return tuple(snapshot[key] for key in ('score', 'lines', 'cleared_crates'))


def helmet_board(page, crates, **options):
    snapshot = animation_request(page, 'helmet_board', crates=crates, animation_hold=True, **options)
    assert snapshot['animation_held'] and snapshot['grounded'] and not snapshot['helmet_hits']
    assert len(snapshot['visible_crates']) == len(crates), snapshot['visible_crates']
    return snapshot


def check_helmet_hits(before, after, crate_ids, direction, charges):
    hits = after['helmet_hits']
    assert len(hits) == len(crate_ids) and {hit['crate_id'] for hit in hits} == set(crate_ids), hits
    assert [hit['direction'] for hit in hits] == [direction] * len(crate_ids), hits
    assert [hit['charges'] for hit in hits] == charges, hits
    assert [hit['helmet_broke'] for hit in hits] == [charge == 0 for charge in charges], hits
    assert set(crate_ids).isdisjoint(crate['id'] for crate in after['visible_crates']), hits
    assert crate_variants(after) == {crate_id: variant for crate_id, variant in crate_variants(before).items()
                                     if crate_id not in crate_ids}
    assert before['ticks'] < min(hit['tick'] for hit in hits) and max(hit['tick'] for hit in hits) <= after['ticks']
    assert after['screen'] == 'playing' and after['state'] == 'playing' and not after['loss_reason']
    assert cleared_metrics(after) == cleared_metrics(before)
    assert personal_statistics(after) == personal_statistics(before)
    assert after['boots_charges'] == before['boots_charges']
    check_helmet_hud(after, charges[-1])
    return hits


def helmet_checks(browser):
    portrait, landscape = (390, 844), (844, 390)
    shots, errors = [], []
    context, page = open_boots_game(browser, portrait, errors)
    initial = state(page)
    check_helmet_hud(initial, 0)
    initial_stats = personal_statistics(initial)
    pick_ground(page, 'helmet', False, charges=3)
    pick_ground(page, 'boots')
    pick_ground(page, 'gloves')
    # Freeze a falling crate above the hero, then resume the same trajectory.
    falling = helmet_board(page, [[4, 8.4, 3]])
    falling_id = falling['visible_crates'][0]['id']
    approaching = animation_step(page, 8)
    assert approaching['visible_crates'][0]['y'] > falling['visible_crates'][0]['y']
    assert not approaching['helmet_hits']
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    animation_step(page, 0, animation_hold=False)
    for dimensions in (portrait, landscape):
        paused = resize_boots_view(page, dimensions)
        assert_frozen_animation(approaching, paused)
        assert not paused['helmet_hits']
        check_helmet_pause(paused, 3, 10, 6)
        helmet_shot(page, 'pause', shots)
    animation_step(page, 0, animation_hold=True)
    button(page, 'resume', True)
    resumed = state(page)
    assert_frozen_animation(approaching, resumed)
    impact = animation_step(page, 24)
    fall_hits = check_helmet_hits(falling, impact, [falling_id], 'fall', [2])
    assert impact['grounded'] and impact['player'] == falling['player']
    helmet_shot(page, 'falling-impact', shots)

    # The crate above the target overlaps it by 0.05 cells and misses the hero.
    jump_crates = [[3.1, 10, 0], [3.1, 9, 0], [4, 8, 0], [4.95, 7, 0]]
    jumping = helmet_board(page, jump_crates)
    _, _, target, supported = jumping['visible_crates']
    settled = animation_step(page, 12)
    assert not settled['helmet_hits'] and settled['player'] == jumping['player']
    assert {crate['id']:crate['y'] for crate in settled['visible_crates']} == {
        crate['id']:crate['y'] for crate in jumping['visible_crates']}
    press_boots_jump(page, True)
    rising = animation_step(page, 8)
    assert rising['player'][1] < jumping['player'][1] - .4 and not rising['helmet_hits']
    helmet_shot(page, 'jumping-under', shots)
    impact = animation_step(page, 20)
    jump_hits = check_helmet_hits(jumping, impact, [target['id']], 'jump', [1])
    assert not impact['grounded'] and impact['player_velocity'][1] < 0
    assert next(crate['y'] for crate in impact['visible_crates'] if crate['id'] == supported['id']) > supported['y']
    falling_through = animation_step(page, 60)
    cascade = next(crate for crate in falling_through['visible_crates'] if crate['id'] == supported['id'])
    assert cascade['y'] > target['y'] + 1 and falling_through['helmet_hits'] == jump_hits
    assert falling_through['helmet_charges'] == 1
    helmet_shot(page, 'cascade', shots)

    replaced = pick_ground(page, 'helmet', charges=3)
    assert replaced['nearest_item']['charges'] == 1
    check_helmet_hud(replaced, 3)
    assert_boots(replaced, True, 10)

    # One descending crate on each side of the hero crosses the head in the same tick.
    simultaneous = helmet_board(page, [[4, 8.5, 5], [5, 8.5, 5]], player=[4.72, 10.12])
    after = animation_step(page, 24)
    same_tick_hits = check_helmet_hits(simultaneous, after, [c['id'] for c in simultaneous['visible_crates']], 'fall', [2, 1])
    assert same_tick_hits[0]['tick'] == same_tick_hits[1]['tick'], same_tick_hits
    assert after['player'] == simultaneous['player'] and after['grounded']

    last = helmet_board(page, jump_crates[:-1])
    page.keyboard.press('ArrowUp')
    after_last = animation_step(page, 26)
    last_hits = check_helmet_hits(last, after_last, [last['visible_crates'][-1]['id']], 'jump', [0])
    assert not after_last['grounded'] and after_last['player_velocity'][1] < 0
    check_boots_hud(after_last, 10)
    helmet_shot(page, 'last-charge', shots)
    press_boots_jump(page, True)
    rocket = animation_step(page, 1)
    assert rocket['boots_charges'] == 9 and rocket['player_velocity'][1] < after_last['player_velocity'][1] - 2
    check_helmet_hud(rocket, 0)

    bare = helmet_board(page, jump_crates[:-1])
    press_boots_jump(page, True)
    bumped = animation_step(page, 26)
    assert bumped['player'][1] >= 9 and bumped['player_velocity'][1] >= 0
    assert bumped['visible_crates'] == animation_step(page, 40)['visible_crates']
    assert not bumped['helmet_hits'] and bumped['screen'] == 'playing'
    exposed = helmet_board(page, [[4, 8.4, 3]])
    animation_step(page, 180)
    wait_screen(page, 'over')
    lost = state(page)
    assert lost['loss_reason'] == 'crushed' and not lost['helmet_hits']
    score, lines, crates = cleared_metrics(exposed)
    assert personal_statistics(exposed) == initial_stats
    match = lost['profile']['matches'][0]
    assert (match['score'], match['lines'], match['crates']) == (score, lines, crates) == (0, 0, 0)
    stats = lost['profile']['statistics']
    assert (stats['best_score'], stats['total_lines'], stats['total_crates']) == (score, lines, crates)
    assert stats['crushed'] == 1 and len(lost['profile']['matches']) == 1
    helmet_shot(page, 'bare-loss', shots)
    context.close()

    for dimensions in ((320, 568), (568, 320), (360, 360)):
        context, page = open_boots_game(browser, dimensions, errors)
        pick_ground(page, 'helmet', charges=3)
        equipped = pick_ground(page, 'boots')
        check_helmet_hud(equipped, 3)
        check_boots_hud(equipped, 10)
        check_touch_control_layout(equipped)
        helmet_shot(page, 'equipped', shots)
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        paused = state(page)
        assert_frozen_animation(equipped, paused)
        check_helmet_pause(paused, 3, 10)
        helmet_shot(page, 'pause', shots)
        button(page, 'restart', True)
        wait_screen(page, 'playing')
        restarted = state(page)
        assert restarted['session'] == equipped['session'] + 1 and cleared_metrics(restarted) == (0, 0, 0)
        check_helmet_hud(restarted, 0)
        assert_boots(restarted, False, 0)
        assert not restarted['helmet_hits'] and personal_statistics(restarted) == personal_statistics(equipped)
        context.close()
    assert not errors, errors
    return {'ground_pickup_and_swap':'PASS', 'keyboard_and_touch':'PASS',
            'pause_resume_resize_and_restart':'PASS', 'boots_compatibility':'PASS', 'cascade':'PASS',
            'bare_jump_and_crush':'PASS', 'statistics':'PASS', 'fall_hit':fall_hits, 'jump_hit':jump_hits,
            'simultaneous_hits':same_tick_hits, 'last_charge':last_hits, 'final_match':match, 'screenshots':shots,
            'screenshot_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in shots}}


GLOVE_CELL_TICKS = 39  # One cell at 3.1 cells per second, with physics at 120 Hz.


def gloves_shot(page, phase, shots):
    size = page.viewport_size
    shot = screenshot(page, f'gloves-{phase}-{size["width"]}x{size["height"]}.png')
    shots.append(shot)


def gloves_board(page, *, facing=1, x=None, gap=0, extra=(), player_x=None):
    before = state(page)
    width, height = before['player_size']
    if x is None:
        x = 4 if facing == 1 else 5
    if player_x is None:
        player_x = x - width - gap if facing == 1 else x + 1 + gap
    snapshot = animation_request(page, 'gloves_board', crates=[[x, 10, 0], *extra],
                                 player=[player_x, before['rows'] - height], facing=facing, animation_hold=True)
    assert snapshot['animation_held'] and snapshot['grounded'] and snapshot['facing'] == facing
    check_glove_grip(snapshot)
    assert not snapshot['gloves_pulls']
    assert len(snapshot['visible_crates']) == 1 + len(extra), snapshot['visible_crates']
    return snapshot


@contextmanager
def glove_touches(page):
    controls = state(page)['controls']
    points = {}
    for identifier, action in enumerate(('grab', 'jump', 'left', 'right'), 1):
        if action in controls:
            x, y = point(page, controls[action])
            points[action] = {'x':x, 'y':y, 'id':identifier}
    cdp = page.context.new_cdp_session(page)

    def dispatch(event, *actions):
        cdp.send('Input.dispatchTouchEvent', {'type':event, 'touchPoints':[points[action] for action in actions]})

    try:
        yield dispatch
    finally:
        dispatch('touchEnd')
        cdp.detach()


@contextmanager
def hold_grab(page, touch):
    if touch:
        with glove_touches(page) as dispatch:
            dispatch('touchStart', 'grab')
            yield
    else:
        page.keyboard.down('g')
        try:
            yield
        finally:
            page.keyboard.up('g')


def check_glove_grip(snapshot, *, held=False, moving=False, crate_id=-1):
    assert (snapshot['pull_held'], snapshot['pull_in_progress'], snapshot['grabbed_crate_id']) == (
        held, moving, crate_id), ('Unexpected glove grip', snapshot['screen'], snapshot['ticks'],
                                  snapshot['pull_held'], snapshot['pull_in_progress'], snapshot['grabbed_crate_id'])


def check_partial_pull(board, partial, *, cells=0, held=True):
    target = board['visible_crates'][0]
    crate = next(c for c in partial['visible_crates'] if c['id'] == target['id'])
    direction = -board['facing']
    travel = (crate['x'] - target['x']) * direction
    assert cells < travel < cells + 1 and crate['y'] == target['y'], (target, crate, cells)
    assert crate['variant'] == target['variant']
    assert abs(partial['player'][0] - board['player'][0] - travel * direction) < .001
    assert partial['player'][1] == board['player'][1] and partial['grounded']
    assert partial['facing'] == board['facing']
    assert len(partial['gloves_pulls']) == cells, partial['gloves_pulls']
    check_gloves_hud(partial, board['gloves_charges'] - cells)
    check_glove_grip(partial, held=held, moving=True, crate_id=target['id'] if held else -1)
    if held:
        assert partial['hero_frame'] == 'grab'


def check_pull_cells(board, finished, cells):
    target, *others = board['visible_crates']
    direction = -board['facing']
    charges = board['gloves_charges']
    check_gloves_hud(finished, charges - cells)
    assert finished['grounded'] and finished['player'][1] == board['player'][1]
    assert finished['facing'] == board['facing'] and not finished['pull_in_progress']
    assert abs(finished['player'][0] - board['player'][0] - cells * direction) < .001
    expected_x = {c['id']:c['x'] for c in others} | {target['id']:target['x'] + cells * direction}
    assert {c['id']:c['x'] for c in finished['visible_crates']} == expected_x
    assert {c['id']:c['variant'] for c in finished['visible_crates']} == {
        c['id']:c['variant'] for c in board['visible_crates']}
    hits = finished['gloves_pulls']
    assert len(hits) == cells, hits
    assert [hit['tick'] - board['ticks'] for hit in hits] == [GLOVE_CELL_TICKS * i for i in range(1, cells + 1)]
    for i, hit in enumerate(hits, 1):
        remaining = charges - i
        assert hit['crate_id'] == target['id'] and hit['charges'] == remaining and hit['gloves_broke'] == (remaining == 0)
        assert hit['facing'] == board['facing'] and hit['tick'] <= finished['ticks']
        assert (hit['x'], hit['y']) == (target['x'] + i * direction, target['y'])
        assert abs(hit['player_x'] - board['player'][0] - i * direction) < .001 and hit['player_y'] == board['player'][1]
    assert cleared_metrics(board) == cleared_metrics(finished)
    assert finished['helmet_charges'] == board['helmet_charges'] and finished['boots_charges'] == board['boots_charges']
    assert personal_statistics(board) == personal_statistics(finished)


def single_glove_pull(page, board, shots):
    with hold_grab(page, True):
        check_partial_pull(board, animation_step(page, 1))
        gloves_shot(page, 'grabbed', shots)
        check_partial_pull(board, animation_step(page, 5))
        gloves_shot(page, 'partial-pull', shots)
    check_partial_pull(board, animation_step(page, 1), held=False)
    finished = animation_step(page, 2 * GLOVE_CELL_TICKS)
    check_pull_cells(board, finished, 1)
    check_glove_grip(finished)
    return finished


def gloves_focus_loss(page):
    other = page.context.new_page()
    sessions = [page.context.new_cdp_session(tab) for tab in (page, other)]
    try:
        page.bring_to_front()
        for session in sessions:
            session.send('Emulation.setFocusEmulationEnabled', {'enabled':False})
        assert page.evaluate('document.hasFocus()')
        page.evaluate('''() => {
            window.qaTrustedBlur = false;
            window.addEventListener('blur', event => { window.qaTrustedBlur = event.isTrusted; }, {once:true});
        }''')
        other.bring_to_front()
        page.wait_for_function('!document.hasFocus() && window.qaTrustedBlur')
        wait_screen(page, 'paused')
        return state(page)
    finally:
        for session in sessions:
            session.detach()
        other.close()
        page.bring_to_front()


def keyboard_glove_pull(page, shots):
    board = gloves_board(page, extra=[[8, 10, 0]])
    target_id = board['visible_crates'][0]['id']
    with hold_grab(page, False):
        check_partial_pull(board, animation_step(page, 1))
        gloves_shot(page, 'grabbed', shots)
        page.keyboard.down('g')  # Playwright sends a KeyG repeat while the key stays down.
        page.keyboard.down('ArrowRight')
        try:
            page.keyboard.press('ArrowUp')
            check_partial_pull(board, animation_step(page, 5))
            gloves_shot(page, 'partial-pull', shots)
            check_partial_pull(board, animation_step(page, GLOVE_CELL_TICKS - 7))
            first_cell = animation_step(page, 1)
            check_pull_cells(board, first_cell, 1)
            check_glove_grip(first_cell, held=True, crate_id=target_id)
            second_cell = animation_step(page, GLOVE_CELL_TICKS)
            check_pull_cells(board, second_cell, 2)
            check_glove_grip(second_cell, held=True, crate_id=target_id)
        finally:
            page.keyboard.up('ArrowRight')
    stopped = animation_step(page, GLOVE_CELL_TICKS + 5)
    check_pull_cells(board, stopped, 2)
    check_glove_grip(stopped)
    return stopped['gloves_pulls']


def multitouch_glove_pull(page, shots):
    board = gloves_board(page, facing=-1, gap=.12, extra=[[1, 10, 0]])
    target_id = board['visible_crates'][0]['id']
    with glove_touches(page) as dispatch:
        dispatch('touchStart', 'grab', 'left', 'jump')
        check_partial_pull(board, animation_step(page, 1))
        gloves_shot(page, 'grabbed', shots)
        check_partial_pull(board, animation_step(page, 5))
        gloves_shot(page, 'partial-pull', shots)
        dispatch('touchEnd', 'jump')  # Grab and Left stay down.
        first_cell = animation_step(page, GLOVE_CELL_TICKS - 6)
        check_pull_cells(board, first_cell, 1)
        check_glove_grip(first_cell, held=True, crate_id=target_id)

        check_partial_pull(board, animation_step(page, 6), cells=1)
        dispatch('touchEnd', 'grab')  # Left cannot keep pulling after the grab finger lifts.
        dispatch('touchStart', 'jump')
        check_partial_pull(board, animation_step(page, 1), cells=1, held=False)
        second_cell = animation_step(page, GLOVE_CELL_TICKS - 7)
        check_pull_cells(board, second_cell, 2)
        check_glove_grip(second_cell)
    stopped = animation_step(page, GLOVE_CELL_TICKS + 5)
    check_pull_cells(board, stopped, 2)
    check_glove_grip(stopped)
    return stopped['gloves_pulls']


def gloves_release_checks(page, portrait, landscape, shots):
    resize_boots_view(page, portrait)
    for interruption in ('pause', 'focus', 'rotation'):
        board = gloves_board(page)
        touch = interruption == 'rotation'
        with hold_grab(page, touch):
            partial = animation_step(page, 6)
            check_partial_pull(board, partial)
            if interruption == 'rotation':
                interrupted = resize_boots_view(page, portrait)
                assert interrupted['screen'] == 'playing'
            elif interruption == 'focus':
                interrupted = gloves_focus_loss(page)
            else:
                button(page, 'pause', True)
                wait_screen(page, 'paused')
                interrupted = state(page)
                check_helmet_pause(interrupted, 3, 10, board['gloves_charges'])
                gloves_shot(page, 'pause', shots)
                paused = resize_boots_view(page, landscape)
                assert_frozen_animation(interrupted, paused)
                check_glove_grip(paused, moving=True)
                check_helmet_pause(paused, 3, 10, board['gloves_charges'])
                gloves_shot(page, 'pause', shots)
            assert_frozen_animation(partial, interrupted)
            check_glove_grip(interrupted, moving=True)
            check_gloves_hud(interrupted, board['gloves_charges'])
            if not touch:
                button(page, 'resume', True)
                wait_screen(page, 'playing')
                assert_frozen_animation(interrupted, state(page))
                page.keyboard.down('g')  # A repeat from the original hold must not rearm the input.
            finished = animation_step(page, 2 * GLOVE_CELL_TICKS)
            check_pull_cells(board, finished, 1)
            check_glove_grip(finished)
        with hold_grab(page, touch):
            check_partial_pull(board, animation_step(page, 1), cells=1)


def gloves_checks(browser):
    portrait, landscape = (390, 844), (844, 390)
    shots, errors = [], []
    context, page = open_boots_game(browser, portrait, errors)
    initial = state(page)
    board = gloves_board(page)
    with hold_grab(page, False):
        bare = animation_step(page, GLOVE_CELL_TICKS)
    check_pull_cells(board, bare, 0)
    check_glove_grip(bare)
    check_gloves_hud(bare, 0)
    pick_ground(page, 'gloves', False)
    resize_boots_view(page, landscape)
    pick_ground(page, 'helmet', charges=3)
    equipped = pick_ground(page, 'boots')
    check_helmet_hud(equipped, 3)
    check_boots_hud(equipped, 10)
    check_gloves_hud(equipped, 6)
    gloves_shot(page, 'loadout', shots)

    board = gloves_board(page, player_x=1)
    with hold_grab(page, False):
        far = animation_step(page, GLOVE_CELL_TICKS)
    check_pull_cells(board, far, 0)
    assert far['grabbed_crate_id'] == -1

    # A completed tap between physics ticks cannot leave a latched input.
    board = gloves_board(page)
    page.keyboard.press('g')
    page.touchscreen.tap(*point(page, state(page)['controls']['grab']))
    tapped = animation_step(page, GLOVE_CELL_TICKS)
    check_pull_cells(board, tapped, 0)
    check_glove_grip(tapped)

    # The wall and the first blocker obstruct retreat. The elevated blocker
    # intersects only the pulled crate; it starts clear of the hero's head.
    blockers = ((1, []), (4, [[2, 10, 0]]), (4, [[2.98, 9.05, 0]]))
    for x, extra in blockers:
        board = gloves_board(page, x=x, extra=extra)
        with hold_grab(page, False):
            blocked = animation_step(page, GLOVE_CELL_TICKS if not extra or extra[0][1] == 10 else 1)
            check_pull_cells(board, blocked, 0)

    touch_pulls = multitouch_glove_pull(page, shots)
    resize_boots_view(page, portrait)
    keyboard_pulls = keyboard_glove_pull(page, shots)

    # The first cell removes support. The next is blocked at the left edge.
    board = gloves_board(page, x=2, extra=[[2.75, 9, 0]])
    supported = board['visible_crates'][1]
    page.mouse.move(*point(page, board['controls']['grab']))
    page.mouse.down()
    try:
        settled = animation_step(page, 2 * GLOVE_CELL_TICKS)
        check_pull_cells(board, settled, 1)
    finally:
        page.mouse.up()
    fallen = next(c for c in settled['visible_crates'] if c['id'] == supported['id'])
    assert (fallen['x'], fallen['y']) == (supported['x'], 10)
    gloves_shot(page, 'cascade', shots)

    resize_boots_view(page, landscape)
    swapped = pick_ground(page, 'gloves')
    assert swapped['nearest_item']['charges'] == 1
    check_gloves_hud(swapped, 6)

    gloves_release_checks(page, portrait, landscape, shots)
    swapped = pick_ground(page, 'gloves')
    assert swapped['nearest_item']['charges'] == 3
    check_gloves_hud(swapped, 6)

    gloves_board(page)
    press_boots_jump(page, True)
    airborne = animation_step(page, 32)
    check_glove_grip(airborne)
    assert not airborne['grounded'] and not airborne['gloves_pulls']
    press_boots_jump(page, True)
    boosted = animation_step(page, 1)
    check_boots_hud(boosted, 9)
    assert boosted['player_velocity'][1] < airborne['player_velocity'][1] - 2
    check_gloves_hud(boosted, 6)
    falling = helmet_board(page, [[4, 8.4, 3]])
    impact = animation_step(page, 36)
    check_helmet_hits(falling, impact, [falling['visible_crates'][0]['id']], 'fall', [2])
    check_gloves_hud(impact, 6)

    board = gloves_board(page, x=8)
    with hold_grab(page, True):
        check_pull_cells(board, animation_step(page, 3 * GLOVE_CELL_TICKS), 3)
        check_partial_pull(board, animation_step(page, 3 * GLOVE_CELL_TICKS - 1), cells=5)
        exhausted = animation_step(page, 1)
        check_pull_cells(board, exhausted, 6)
        check_glove_grip(exhausted)
        assert exhausted['field'] == board['field'] and exhausted['crane_rail'] == board['crane_rail'], (
            'Removing the grab control shifted the game board', board['field'], exhausted['field'])
        check_touch_control_layout(exhausted)
        gloves_shot(page, 'last-charge', shots)
        check_pull_cells(board, animation_step(page, GLOVE_CELL_TICKS + 5), 6)
    with hold_grab(page, False):
        check_glove_grip(animation_step(page, 1))
    assert personal_statistics(exhausted) == personal_statistics(initial)
    equipped = pick_ground(page, 'gloves')
    assert equipped['gloves_charges'] == 6
    button(page, 'pause', True)
    wait_screen(page, 'paused')
    button(page, 'restart', True)
    wait_screen(page, 'playing')
    restarted = state(page)
    assert restarted['session'] == equipped['session'] + 1 and cleared_metrics(restarted) == (0, 0, 0)
    check_gloves_hud(restarted, 0)
    check_glove_grip(restarted)
    assert not restarted['gloves_pulls']
    check_touch_control_layout(restarted)
    context.close()

    for dimensions in ((320, 568), (568, 320), (360, 360)):
        context, page = open_boots_game(browser, dimensions, errors)
        equipped = pick_ground(page, 'gloves')
        check_gloves_hud(equipped, 6)
        check_touch_control_layout(equipped)
        glove_control = equipped['controls']['grab']
        assert glove_control[2] >= 48 and glove_control[3] >= 48, glove_control
        board = gloves_board(page)
        pulled = single_glove_pull(page, board, shots)
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        paused = state(page)
        assert_frozen_animation(pulled, paused)
        check_helmet_pause(paused, 0, 0, 5)
        gloves_shot(page, 'pause', shots)
        context.close()
    assert not errors, errors
    return {'keyboard_pulls':keyboard_pulls, 'touch_pulls':touch_pulls, 'trusted_tab_focus_loss':'PASS',
            'hold_release_key_repeat_and_multitouch':'PASS', 'movement_and_jump_lock':'PASS',
            'blocked_and_partial_pulls':'PASS', 'support_cascade':'PASS',
            'last_charge_and_restart':'PASS', 'ground_pickup_and_swap':'PASS',
            'pause_and_both_layouts':'PASS', 'helmet_and_boots_compatibility':'PASS', 'screenshots':shots,
            'screenshot_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in shots}}


def crate_variants(snapshot):
    return {crate['id']: crate['variant'] for crate in snapshot['visible_crates']}


def crate_rect(snapshot, crate):
    left, top, width, _ = snapshot['field']
    cell = width / snapshot['columns']
    # The engine snaps sprite origins to the 24-pixel board grid before scaling.
    x, y = [round(crate[axis] * 24) / 24 for axis in ('x', 'y')]
    return left + x * cell, top + y * cell, cell, cell


def crate_face(image, snapshot, rect):
    x, y, w, h = rect
    scale_x = image.width / snapshot['viewport'][0]
    scale_y = image.height / snapshot['viewport'][1]
    # Exclude the edges that can be covered by the jaws or the frame.
    bounds = (round((x + .18 * w) * scale_x), round((y + .25 * h) * scale_y),
              round((x + .82 * w) * scale_x), round((y + .84 * h) * scale_y))
    return image.crop(bounds).resize((20, 20), Image.Resampling.BILINEAR)


def closest_crate_face(face, references):
    distances = {variant: sum(ImageStat.Stat(ImageChops.difference(face, reference)).mean)
                 for variant, reference in references.items()}
    return min(distances, key=distances.get), distances


def crate_hashes(page, snapshot):
    image = Image.open(io.BytesIO(page.screenshot())).convert('RGB')
    return {crate['variant']: hashlib.sha256(
        field_crop(image, snapshot, crate['x'], crate['y'], 1, 1).tobytes()).hexdigest()
        for crate in snapshot['visible_crates']}


def wooden_crates(browser):
    dimensions = (360, 800)
    context = browser.new_context(viewport={'width': dimensions[0], 'height': dimensions[1]},
                                  has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors = []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    original_stats = personal_statistics(state(page))
    checks = []
    for screen, dimensions in [('menu', (360, 800)), ('playing', (390, 844)), ('playing', (844, 390)),
                               ('playing', (320, 568)), ('playing', (568, 320))]:
        if state(page)['screen'] != screen:
            button(page, 'play', True)
            wait_screen(page, 'playing')
        width, height = dimensions
        page.set_viewport_size({'width': width, 'height': height})
        layout = 'landscape' if width > height else 'portrait'
        page.wait_for_function('value => window.stackAttackState.layout === value', arg=layout)
        page.wait_for_timeout(220)
        snapshot = animation_request(page, 'crate_appearance', gallery=True)
        crates = snapshot['visible_crates']
        assert [crate['variant'] for crate in crates] == list(range(10)), crates
        hashes = crate_hashes(page, snapshot)
        assert len(set(hashes.values())) == 10, ('The gallery must render ten distinct appearances', screen, hashes)

        retagged = animation_request(page, 'crate_appearance', gallery=True, tag_offset=1)
        new_crates = retagged['visible_crates']
        assert all((before['color'] + 1) % 3 == after['color'] for before, after in zip(crates, new_crates))
        assert crate_hashes(page, retagged) == hashes, ('Legacy tags changed rendered crate pixels', screen, hashes)
        gallery = screenshot(page, f'wood-crates-gallery-{screen}-{width}x{height}.png')

        dense = animation_request(page, 'crate_appearance', stacks=True)
        assert set(crate_variants(dense).values()) == set(range(10))
        assert len(dense['visible_crates']) >= 20
        dense_path = screenshot(page, f'wood-crates-stacks-{screen}-{width}x{height}.png')
        checks.append({'screen': screen, 'viewport': dimensions, 'variant_pixel_sha256': hashes,
                       'legacy_tags_independent': 'PASS', 'screenshots': [gallery, dense_path]})
    assert personal_statistics(state(page)) == original_stats
    assert not errors, errors
    context.close()
    print('WOODEN_CRATES', json.dumps(checks), flush=True)
    return checks


def crate_lifetime_checks(browser):
    context = browser.new_context(viewport={'width': 390, 'height': 844}, has_touch=True, device_scale_factor=1)
    page = context.new_page()
    errors, shots = [], []
    page.on('pageerror', lambda value: errors.append(str(value)))
    page.goto(URL)
    wait_screen(page, 'menu')
    button(page, 'play', True)
    wait_screen(page, 'playing')

    gallery = animation_request(page, 'crate_appearance', gallery=True)
    gallery_image = animation_image(page, (390, 844), shots)
    faces = {crate['variant']: crate_face(gallery_image, gallery, crate_rect(gallery, crate))
             for crate in gallery['visible_crates']}

    animation_request(page, 'cranes', animation_hold=True)
    animation_step(page, 150)
    carrying = animation_step(page, 150)
    assert not carrying['crane_releases'] and all(c['loaded'] for c in carrying['cranes'])
    carrying_image = animation_image(page, (390, 844), shots, 'wood-crane-carrying')
    animation_step(page, 110)
    dropped = animation_step(page, 20)
    falling_image = animation_image(page, (390, 844), shots, 'wood-crane-falling')
    assert len(dropped['crane_releases']) == len(carrying['cranes']) == 2
    falling = {crate['id']:crate for crate in dropped['visible_crates']}
    rendered_handoffs = []
    for release in dropped['crane_releases']:
        index, expected = release['crane'], release['variant']
        cargo = carrying['cranes'][index]
        crate = falling[release['crate_id']]
        assert expected == cargo['variant'] == crate['variant'] and 0 < crate['y'] < 8
        cargo_face = crate_face(carrying_image, carrying, carrying['crane_cargo_rects'][index])
        falling_face = crate_face(falling_image, dropped, crate_rect(dropped, crate))
        for target in (cargo_face, falling_face):
            closest, distances = closest_crate_face(target, faces)
            assert closest == expected, ('Rendered crane/cell appearance does not match the gallery',
                                         index, expected, closest, distances)
        rendered_handoffs.append({'crane': index, 'crate_id':crate['id'], 'variant': expected})

    board = animation_request(page, 'push', animation_hold=True)
    original, = board['visible_crates']
    page.keyboard.down('ArrowRight')
    try:
        moving = animation_step(page, 25)
    finally:
        page.keyboard.up('ArrowRight')
    pushed, = moving['visible_crates']
    assert pushed['id'] == original['id'] and pushed['variant'] == original['variant']
    assert pushed['x'] > original['x'] + .25
    pause_animation_and_rotate(page, moving, (390, 844))

    phases = clear_animation_check(page, (390, 844), shots)
    start_crane_preview(page)
    releases = crane_cycle(page, state(page))
    assert all(0 <= release['variant'] < 10 for release in releases)
    assert not errors, errors
    context.close()
    return {'push_pause_rotation': 'PASS', 'clear_descent': phases, 'crane_releases': releases,
            'rendered_handoffs': rendered_handoffs, 'screenshots': shots}


def mallet_board(page, **options):
    return animation_request(page, 'mallet_board', equip=True, animation_hold=True, **options)


def check_mallet_hud(snapshot, charges):
    assert snapshot['mallet_charges'] == charges and snapshot['gloves_charges'] == 0
    assert not snapshot['gloves_hud']
    hud = snapshot['mallet_hud']
    if charges:
        assert hud['text'] == str(charges)
        check_boots_rect(snapshot, hud['rect'])
        x, y, w, h = hud['rect']
        neighbors = [snapshot['buttons']['pause']] if 'pause' in snapshot['buttons'] else []
        neighbors.extend(snapshot[key]['rect'] for key in ('boots_hud', 'helmet_hud') if snapshot[key])
        for ax, ay, aw, ah in neighbors:
            assert x + w <= ax or ax + aw <= x or y + h <= ay or ay + ah <= y
    else:
        assert not hud
    check_touch_control_layout(snapshot)


def mallet_checks(browser):
    portrait, landscape = (390, 844), (844, 390)
    errors, shots = [], []
    context, page = open_boots_game(browser, portrait, errors)
    try:
        pick_ground(page, 'gloves')
        resize_boots_view(page, landscape)
        check_mallet_hud(pick_ground(page, 'mallet'), 3)
        check_gloves_hud(pick_ground(page, 'gloves'), 6)
        assert not state(page)['mallet_hud'] and 'mallet' not in state(page)['controls']

        board = mallet_board(page, facing=1, stack=True, helmet=2, boots=5)
        check_mallet_hud(board, 3)
        floor_crate = max(board['visible_crates'], key=lambda crate: crate['y'])
        upper_crate = next(crate for crate in board['visible_crates'] if crate['id'] != floor_crate['id'])
        page.keyboard.down('KeyG')
        try:
            windup = animation_step(page, 1)
            assert len(windup['mallet_swings']) == 1 and not windup['mallet_hits']
            check_mallet_hud(windup, 3)
            shots.append(screenshot(page, 'mallet-windup.png'))
            first = animation_step(page, 13)
            shots.append(screenshot(page, 'mallet-strike.png'))
            page.keyboard.down('KeyG')  # Browser auto-repeat carries the same keydown state.
            landed = animation_step(page, 100)
        finally:
            page.keyboard.up('KeyG')
        hit, = landed['mallet_hits']
        assert hit['crate_id'] == floor_crate['id'] and not hit['mallet_broke']
        survivor, = landed['visible_crates']
        assert survivor['id'] == upper_crate['id'] and survivor['x'] == upper_crate['x'] and survivor['y'] == floor_crate['y']
        assert survivor['variant'] == upper_crate['variant']
        assert first['field'] == landed['field'] == board['field']
        assert landed['boots_charges'] == 5 and landed['helmet_charges'] == 2
        assert len(landed['mallet_swings']) == 1
        assert landed['broken_crates'] == board['broken_crates'] + 1
        assert cleared_metrics(landed) == cleared_metrics(board)
        check_mallet_hud(landed, 2)

        resize_boots_view(page, portrait)
        miss = mallet_board(page, facing=-1, target=False, at_edge=True)
        page.touchscreen.tap(*point(page, miss['controls']['mallet']))
        failed = animation_step(page, 50)
        assert len(failed['mallet_misses']) == 1 and not failed['mallet_hits']
        assert failed['broken_crates'] == miss['broken_crates']
        check_mallet_hud(failed, 3)
        x, y = point(page, failed['controls']['mallet'])
        touch = context.new_cdp_session(page)
        try:
            touch.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[{'x':x, 'y':y, 'id':1}]})
            held = animation_step(page, 60)
            assert len(held['mallet_swings']) == 2 and len(held['mallet_misses']) == 2
            for drag_y in (y - 100, y):
                touch.send('Input.dispatchTouchEvent', {'type':'touchMove', 'touchPoints':[{'x':x, 'y':drag_y, 'id':1}]})
                assert len(animation_step(page, 40)['mallet_swings']) == 2
        finally:
            touch.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
            touch.detach()
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        pause = check_boots_panel(state(page), {'resume', 'restart', 'home'})
        assert pause['slot_hands'] == '3 / 3', pause
        shots.append(screenshot(page, 'mallet-pause-portrait.png'))
        button(page, 'resume', True)
        wait_screen(page, 'playing')

        final = mallet_board(page, facing=-1, charges=1)
        page.touchscreen.tap(*point(page, final['controls']['mallet']))
        last = animation_step(page, 15)
        hit, = last['mallet_hits']
        assert hit['facing'] == -1 and hit['charges'] == 0 and hit['mallet_broke'] and not last['visible_crates']
        assert last['broken_crates'] == final['broken_crates'] + 1 and cleared_metrics(last) == cleared_metrics(final)
        assert last['field'] == final['field'] and last['buttons']['pause'] == final['buttons']['pause']
        check_mallet_hud(last, 0)
        shots.append(screenshot(page, 'mallet-last-hit.png'))

        for lose_focus in (False, True):
            staged = mallet_board(page)
            page.keyboard.press('KeyG')
            assert len(animation_step(page, 1)['mallet_swings']) == 1
            if lose_focus:
                gloves_focus_loss(page)
            else:
                page.keyboard.press('Escape')
                wait_screen(page, 'paused')
            button(page, 'resume', True)
            wait_screen(page, 'playing')
            resumed = animation_step(page, 40)
            assert not resumed['mallet_hits'] and resumed['mallet_charges'] == 3
            assert resumed['visible_crates'] == staged['visible_crates']
        scenario(page, 'overflow')
        wait_screen(page, 'over')
        completed = state(page)['profile']
        match, = completed['matches']
        assert match['broken_crates'] == 2 and match['lines'] == 0 and match['score'] == 0
        assert completed['statistics']['total_broken_crates'] == 2
        button(page, 'again', True)
        wait_screen(page, 'playing')
        mallet_board(page)
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        button(page, 'restart', True)
        wait_screen(page, 'playing')
        restarted = state(page)
        check_mallet_hud(restarted, 0)
        assert not restarted['mallet_swings'] and restarted['broken_crates'] == 0
    finally:
        context.close()
    assert not errors, errors
    return {'screenshots': shots, 'keyboard_and_touch': 'PASS', 'equipment_and_layout': 'PASS',
            'last_hit_and_support': 'PASS', 'pause_focus_and_restart': 'PASS', 'statistics_and_score': 'PASS'}


def set_bonus_board(page, loadout, **options):
    return animation_request(page, 'bonus_board', loadout=loadout, animation_hold=True, **options)


def bonus_events(snapshot, kind):
    return [event for event in snapshot['bonus_events'] if event['type'] == kind]


def bonuses_checks(browser):
    errors, shots = [], []
    portrait, landscape = (320, 568), (568, 320)
    context, page = open_boots_game(browser, portrait, errors)
    try:
        resize_boots_view(page, landscape)
        for item in ('strong_arms', 'speed_boots', 'lamp_helmet'):
            equipped = pick_ground(page, item)
            assert equipped[item + '_charges'] > 0 and equipped[item + '_hud']
        check_touch_control_layout(equipped)
        resize_boots_view(page, portrait)
        width = state(page)['player_size'][0]
        loadout = {'hands':'strong_arms', 'feet':'speed_boots', 'head':'lamp_helmet'}
        staged = set_bonus_board(page, loadout, player=[4-width, 10.12], crates=[[4,10,0],[5,10,0]],
            charges={'strong_arms':1, 'lamp_helmet':1}, cranes_enabled=True,
            cranes=[{'x':0.0, 'loaded':True, 'release_column':8}, {'x':8.5, 'loaded':False, 'release_column':1}])
        check_touch_control_layout(staged)
        primary = {crate['id']:crate for crate in staged['visible_crates']}
        touch = context.new_cdp_session(page)
        x, y = point(page, staged['controls']['right'])
        lx, ly = point(page, staged['controls']['lamp'])
        right = {'x':x, 'y':y, 'id':1}
        lamp = {'x':lx, 'y':ly, 'id':2}
        try:
            touch.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[right]})
            animation_step(page, 1)
            touch.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[right, lamp]})
            pushed = animation_step(page, 40)
        finally:
            touch.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
            touch.detach()
        assert pushed['lamp_helmet_equipped'] and pushed['lamp_helmet_charges'] == 0 and pushed['lamp_columns'] == [8]
        assert pushed['strong_arms_charges'] == 0 and len(bonus_events(pushed, 'strong_push')) == 1
        assert {c['id']:c['x'] for c in pushed['visible_crates']} == {i:c['x']+1 for i,c in primary.items()}
        assert {c['id']:c['variant'] for c in pushed['visible_crates']} == {i:c['variant'] for i,c in primary.items()}
        assert cleared_metrics(pushed) == cleared_metrics(staged)
        shots.append(screenshot(page, 'bonuses-lamp-and-pair.png'))

        blocked = set_bonus_board(page, loadout, player=[7-width,10.12], crates=[[7,10,0],[8,10,0],[9,10,0]],
            cranes_enabled=True, cranes=[{'loaded':False}, {'loaded':False}])
        page.keyboard.down('ArrowRight')
        try:
            page.keyboard.press('KeyF')
            after = animation_step(page, 60)
        finally:
            page.keyboard.up('ArrowRight')
        assert after['visible_crates'] == blocked['visible_crates'] and after['player'] == blocked['player']
        for name in ('strong_arms', 'speed_boots', 'lamp_helmet'):
            assert after[name+'_charges'] == blocked[name+'_charges']
        assert not bonus_events(after, 'lamp_reveal') and not bonus_events(after, 'strong_push')

        runner = set_bonus_board(page, {'feet':'speed_boots'}, charges={'speed_boots':1})
        page.keyboard.down('ArrowRight')
        try:
            fast = animation_step(page, 12)
            finished = animation_step(page, 16)
        finally:
            page.keyboard.up('ArrowRight')
        assert fast['player'][0] - runner['player'][0] > .49 and fast['speed_boots_charges'] == 1
        assert finished['speed_boots_charges'] == 0 and finished['player'][0] > runner['player'][0]+1

        rescue = set_bonus_board(page, {'head':'lamp_helmet', 'hands':'mallet', 'feet':'spring_boots'},
            player=[4.35,10.12], crates=[[4,9.02,6]], charges={'lamp_helmet':3})
        check_touch_control_layout(rescue)
        saved = animation_step(page, 22)
        assert not saved['lamp_helmet_equipped'] and saved['lamp_helmet_charges'] == 0 and saved['state'] == 'playing'
        assert saved['broken_crates'] == rescue['broken_crates']+1 and not saved['visible_crates']
        assert len(bonus_events(saved, 'lamp_break')) == 1

        combination = {'head':'lamp_helmet', 'hands':'mallet', 'feet':'spring_boots'}
        board = set_bonus_board(page, combination)
        check_touch_control_layout(board)
        page.touchscreen.tap(*point(page, board['controls']['jump']))
        short = animation_step(page, 1)
        assert not short['grounded'] and short['spring_boots_charges'] == board['spring_boots_charges']

        board = set_bonus_board(page, combination)
        page.keyboard.down('Space')
        meter = animation_step(page, 110)
        assert meter['grounded'] and meter['spring_charge_stages'] == 5
        assert meter['spring_boots_hud']['meter_stages'] == 5
        assert meter['spring_boots_hud']['meter_limit'] == board['spring_charge_limit'] > 5
        check_boots_rect(meter, meter['spring_boots_hud']['meter_rect'])
        shots.append(screenshot(page, 'bonuses-spring-meter.png'))
        page.keyboard.up('Space')
        launched = animation_step(page, 1)
        jump, = bonus_events(launched, 'spring_jump')
        assert jump['stages'] == 5 and not jump['automatic'] and launched['spring_boots_charges'] == board['spring_boots_charges'] - 5
        assert launched['spring_boots_hud']['meter_limit'] == board['spring_charge_limit']

        board = set_bonus_board(page, combination)
        touch = context.new_cdp_session(page)
        x, y = point(page, board['controls']['jump'])
        page.keyboard.down('Space')
        try:
            touch.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[{'x':x,'y':y,'id':1}]})
            assert animation_step(page, 24)['spring_charge_stages'] == 1
            touch.send('Input.dispatchTouchEvent', {'type':'touchCancel', 'touchPoints':[]})
            assert animation_step(page, 24)['spring_charge_stages'] == 2
        finally:
            page.keyboard.up('Space')
            touch.detach()
        after_cancel = animation_step(page, 1)
        assert bonus_events(after_cancel, 'spring_jump')[0]['stages'] == 2

        for interruption in ('focus', 'resize'):
            board = set_bonus_board(page, combination)
            page.keyboard.down('Space')
            try:
                assert animation_step(page, 26)['spring_charge_stages'] == 1
                if interruption == 'focus':
                    gloves_focus_loss(page)
                    button(page, 'resume', True)
                    wait_screen(page, 'playing')
                else:
                    resize_boots_view(page, landscape)
            finally:
                page.keyboard.up('Space')
            quiet = animation_step(page, 32)
            assert quiet['grounded'] and quiet['spring_charge_stages'] == 0 and not bonus_events(quiet, 'spring_jump')
            assert quiet['spring_boots_charges'] == board['spring_boots_charges']

        auto = set_bonus_board(page, combination, charges={'spring_boots':4})
        press = context.new_cdp_session(page)
        px, py = point(page, auto['controls']['jump'])
        try:
            press.send('Input.dispatchTouchEvent', {'type':'touchStart', 'touchPoints':[{'x':px,'y':py,'id':1}]})
            released = animation_step(page, 90)
            assert released['spring_boots_charges'] == 0 and released['player'][1] < auto['player'][1]
            assert released['spring_boots_hud']['meter_stages'] == released['spring_boots_hud']['meter_limit'] == 4
            auto_jump, = bonus_events(released, 'spring_jump')
            assert auto_jump['automatic'] and auto_jump['stages'] == 4
            shots.append(screenshot(page, 'bonuses-spring-auto.png'))
            held = animation_step(page, 148)
            assert len(bonus_events(held, 'spring_jump')) == 1
        finally:
            press.send('Input.dispatchTouchEvent', {'type':'touchEnd', 'touchPoints':[]})
            press.detach()

        rockets = set_bonus_board(page, {'feet':'boots', 'head':'helmet', 'hands':'gloves'}, charges={'boots':3})
        page.keyboard.press('Space')
        first = animation_step(page, 23)
        assert first['boots_charges'] == rockets['boots_charges'] and not first['grounded']
        for remaining in (2,1,0):
            page.keyboard.down('ArrowUp')
            try:
                charged = animation_step(page, 1)
                assert charged['boots_charges'] == remaining and charged['player_velocity'][1] < -7
                page.keyboard.down('ArrowUp')
                assert animation_step(page, 10)['boots_charges'] == remaining
            finally:
                page.keyboard.up('ArrowUp')
        assert not animation_step(page, 180)['boots_equipped']
        button(page, 'pause', True)
        wait_screen(page, 'paused')
        button(page, 'restart', True)
        wait_screen(page, 'playing')
        restarted = state(page)
        assert all(restarted[key+'_charges']==0 for key in NEW_GEAR) and not restarted['lamp_helmet_equipped']
        assert not restarted['bonus_events'] and restarted['score'] == 0
    finally:
        context.close()
    assert not errors, errors
    return {'ground_pickup_and_restart':'PASS', 'pair_speed_and_lamp_multitouch':'PASS',
            'spring_and_rocket_separate_inputs':'PASS', 'focus_resize_and_pause':'PASS', 'screenshots':shots}


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
        ground = ground_checks(browser, record=args.loot_only) if args.loot_only or full_check else {}
        if ground:
            print('GROUND', json.dumps(ground), flush=True)
        if args.loot_only:
            browser.close()
            raise SystemExit(0)
        bonuses = bonuses_checks(browser) if args.bonuses_only or full_check else {}
        if bonuses:
            print('BONUSES', json.dumps(bonuses), flush=True)
        if args.bonuses_only:
            (BUILD/'bonuses-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':bonuses,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        if args.crates_only:
            crates = wooden_crates(browser)
            lifetime = crate_lifetime_checks(browser)
            (BUILD/'crates-check.json').write_text(json.dumps({'status':'PASS', 'browser':browser.version,
                'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),
                'rendered_variants':crates, 'lifetime':lifetime}, indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        mallet = mallet_checks(browser) if args.mallet_only or full_check else {}
        if mallet:
            print('MALLET', json.dumps(mallet), flush=True)
        if args.mallet_only:
            (BUILD/'mallet-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':mallet,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        helmet = helmet_checks(browser) if args.helmet_only or full_check else {}
        if helmet:
            print('HELMET', json.dumps(helmet), flush=True)
        if args.helmet_only:
            (BUILD/'helmet-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':helmet,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        boots = boots_checks(browser) if args.boots_only or full_check else {}
        if boots:
            print('BOOTS', json.dumps(boots), flush=True)
        if args.boots_only:
            (BUILD/'boots-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':boots,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
            browser.close()
            raise SystemExit(0)
        gloves = gloves_checks(browser) if args.gloves_only or full_check else {}
        if gloves:
            print('GLOVES', json.dumps(gloves), flush=True)
        if args.gloves_only:
            (BUILD/'gloves-check.json').write_text(json.dumps({'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                'checks':gloves,'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest()},indent=2)+'\n')
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
        report = {'status':'PASS','browser':browser.version,'renderer':'SwiftShader', 'ground':ground, 'bonuses':bonuses, 'mallet':mallet, 'helmet':helmet, 'boots':boots, 'gloves':gloves, 'keyboard':keyboard, 'animations':animations, 'cranes':cranes, 'statistics':statistics, 'wooden_crates':crates,'workshop':workshop,'menu_layouts':menus, 'sprite_poses':sprites, 'ui_batch':ui_batch, 'game_over':results_over,'button_styles':button_styles,
                  'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),
                  'page_errors':all_errors,'failed_requests':all_failed_requests,'checks':results}
        (BUILD/'web-check.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
        browser.close()
finally:
    server.shutdown()
    server.server_close()
