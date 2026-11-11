#!/usr/bin/env python3
"""End-to-end checks against the actual exported game; debug fixtures require ?qa=1."""
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import threading
from playwright.sync_api import sync_playwright

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
    for _ in range(5):
        snapshot = state(page)
        rect = snapshot['buttons'][name]
        x, y = point(page, rect)
        bounds = page.locator('canvas').bounding_box()
        if 15 <= y <= bounds['height'] - 18:
            break
        page.mouse.move(bounds['width'] / 2, bounds['height'] / 2)
        page.mouse.wheel(0, 250 if y > bounds['height'] else -250)
        page.wait_for_timeout(180)
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


try:
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=os.environ.get('CHROMIUM_BIN', '/usr/bin/chromium'),
            headless=True, args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
                                 '--autoplay-policy=no-user-gesture-required'])
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
            button(page, 'sound_test', touch)
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
            button(page, 'sound_test', touch)
            effect_samples = []
            for _ in range(4):
                page.wait_for_timeout(60)
                effect_samples.append(rms(page))
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
                      'pause':'PASS', 'line_chain':'PASS', 'both_losses':'PASS', 'restart':'PASS',
                      'settings_and_records_reload':'PASS', 'muted_rms':silent_rms, 'audible_rms':audible_rms, 'effects_rms':max(effect_samples),
                      'screenshots':[menu_shot,game_shot]}
            results.append(result)
            print(json.dumps(result), flush=True)
            context.close()
        report = {'status':'PASS','browser':browser.version,'renderer':'SwiftShader',
                  'pck_sha256':hashlib.sha256((BUILD/'web/index.pck').read_bytes()).hexdigest(),
                  'page_errors':all_errors,'failed_requests':all_failed_requests,'checks':results}
        (BUILD/'web-check.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(report,indent=2))
        browser.close()
finally:
    server.shutdown()
    server.server_close()
