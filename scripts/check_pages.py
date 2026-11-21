"""Exercise the deployed Godot Web release in an anonymous browser."""
import os
from pathlib import PurePosixPath
import sys
import time
from urllib.parse import urljoin, urlsplit

from playwright.sync_api import sync_playwright

site, sha = sys.argv[1:]
site = site.rstrip("/") + "/"
# The normal release writes a match only after a real game, never for the menu demo.
read_match = """async () => {
    const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('/userfs');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
    });
    try {
        const files = db.transaction('FILE_DATA').objectStore('FILE_DATA');
        return await new Promise((resolve, reject) => {
            const request = files.openCursor();
            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                const cursor = request.result;
                if (!cursor) return resolve(null);
                if (cursor.key.endsWith('/stack-attack-profile-v1.json')) {
                    const profile = JSON.parse(new TextDecoder().decode(cursor.value.contents));
                    return resolve(profile.matches[0] || null);
                }
                cursor.continue();
            };
        });
    } finally { db.close(); }
}"""

with sync_playwright() as browser_api:
    browser = browser_api.chromium.launch(executable_path=os.environ["CHROMIUM_BIN"],
        args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
    context = browser.new_context()
    deadline = time.monotonic() + 600
    while True:
        marker = context.request.get(urljoin(site, "source-commit.txt"), params={"build": sha})
        if marker.ok and marker.text().strip() == sha:
            break
        if time.monotonic() >= deadline:
            raise RuntimeError(f"{site} did not serve {sha}")
        time.sleep(10)
    page = context.new_page()
    errors = []
    responses = {}
    page.on("pageerror", lambda error: errors.append(str(error)))

    def record(response):
        if response.url.startswith(site):
            name = PurePosixPath(urlsplit(response.url).path).name
            responses[name] = (response.status, response.headers.get("content-type", "").split(";")[0])

    page.on("response", record)
    with page.expect_console_message(predicate=lambda msg: msg.text == "STACK_ATTACK_READY", timeout=90000):
        page.goto(site)
    assert page.url == site and page.locator("canvas").is_visible()
    assert responses.get("index.wasm") == (200, "application/wasm"), responses
    assert responses.get("index.pck") == (200, "application/octet-stream"), responses
    assert responses.get("index.js") in ((200, "application/javascript"), (200, "text/javascript")), responses
    page.keyboard.press("Enter")
    page.keyboard.press("ArrowRight", delay=350)
    page.keyboard.press("Space")
    deadline = time.monotonic() + 180
    while not (match := page.evaluate(read_match)):
        if time.monotonic() >= deadline:
            raise RuntimeError("The release did not record a match after pressing Play")
        page.wait_for_timeout(1000)
    assert not errors, errors
    print(f"{site} @ {sha} in Chromium {browser.version}: {responses}; completed match: {match}")
    browser.close()
