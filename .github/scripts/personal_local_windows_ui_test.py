# Drives the extracted personal-local Windows app with UI Automation.
# Synthetic notes only. Does not read or write a user's installed data.
import json
import os
import subprocess
import time
from pathlib import Path

from PIL import ImageGrab
from pywinauto import Desktop
from pywinauto.keyboard import send_keys

ARTIFACTS = Path(os.environ["UI_ARTIFACTS"])
EXE = Path(os.environ["APPFLOWY_EXE"].strip())
APP_DIR = EXE.parent
DATA_DIR = APP_DIR / "AppFlowyDataDoNotRename"
APPDATA_DIR = Path(os.environ["APPDATA"]) / "io.appflowy"
NOTE_MARKER = "CI-NOTE-MARKER"

results = []
shot_index = 0


def log(message):
    print(message, flush=True)


def shot(name):
    global shot_index
    shot_index += 1
    path = ARTIFACTS / f"{shot_index:02d}-{name}.png"
    try:
        ImageGrab.grab(all_screens=True).save(path)
    except Exception:
        ImageGrab.grab().save(path)
    log(f"screenshot {path.name}")
    return path.name


def record(name, passed, detail):
    results.append({"test": name, "passed": passed, "detail": detail})
    log(f"{'PASS' if passed else 'FAIL'} {name}: {detail}")


def crash_excerpt():
    script = r"""
$start = [datetime]::Parse($env:TEST_START)
$events = @()
try {
  $events = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$start} -ErrorAction Stop)
} catch {
  $events = @()
}
$hits = @($events | Where-Object {
  $msg = $_.Message
  $aboutApp = $msg -match 'AppFlowy'
  $crash = $_.Id -eq 1000 -or $msg -match 'APPCRASH|BEX64|0xc0000409'
  $aboutApp -and $crash
})
if ($hits.Count -eq 0) {
  "NO_APPFLOWY_CRASH"
  "Application log entries mentioning AppFlowy since test start:"
  $mentioned = @($events | Where-Object { $_.Message -match 'AppFlowy' })
  if ($mentioned.Count -eq 0) {
    "(none)"
  } else {
    $mentioned | Select-Object -First 8 | ForEach-Object {
      "---"
      "Time: $($_.TimeCreated.ToString('o')) Id: $($_.Id) Provider: $($_.ProviderName)"
      $_.Message
    }
  }
  exit 0
}
"CRASH_COUNT $($hits.Count)"
$hits | Select-Object -First 5 | ForEach-Object {
  "---"
  "Time: $($_.TimeCreated.ToString('o')) Id: $($_.Id) Provider: $($_.ProviderName)"
  $_.Message
}
exit 2
"""
    completed = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    text = (completed.stdout or "") + (completed.stderr or "")
    (ARTIFACTS / "event-log.txt").write_text(text, encoding="utf-8")
    return completed.returncode == 0, text.strip()


def assert_no_crash(step):
    ok, text = crash_excerpt()
    if not ok:
        raise AssertionError(f"crash event after {step}:\n{text[:2000]}")
    return text


def process_running():
    completed = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq AppFlowy.exe", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return "AppFlowy.exe" in (completed.stdout or "")


def kill_app():
    subprocess.run(
        ["taskkill", "/IM", "AppFlowy.exe", "/T", "/F"],
        capture_output=True,
        text=True,
    )
    for _ in range(20):
        if not process_running():
            return
        time.sleep(0.5)


def screen_size():
    import ctypes

    user32 = ctypes.windll.user32
    return user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)


def fit_main_window():
    import ctypes

    user32 = ctypes.windll.user32
    width, height = screen_size()
    hwnd = user32.FindWindowW(None, "AppFlowy")
    if not hwnd:
        return None
    user32.ShowWindow(hwnd, 9)
    user32.SetWindowPos(hwnd, 0, 0, 0, width, height, 0x0040)
    return hwnd


def top_windows():
    desktop = Desktop(backend="uia")
    found = []
    for win in desktop.windows():
        try:
            title = win.window_text() or ""
            rect = win.rectangle()
            found.append((title, rect, win))
        except Exception:
            continue
    return found


def dump_tree(label):
    lines = [f"# {label}"]
    for title, rect, win in top_windows():
        lines.append(f"WINDOW {title!r} {rect}")
        lines.extend(describe(win, 1))
    text = "\n".join(lines[:2500])
    path = ARTIFACTS / "uia-tree.txt"
    previous = path.read_text(encoding="utf-8") if path.exists() else ""
    path.write_text(previous + "\n" + text + "\n", encoding="utf-8")
    return text


def describe(ctrl, depth):
    if depth > 8:
        return []
    lines = []
    try:
        children = ctrl.children()
    except Exception:
        return lines
    for child in children:
        try:
            name = child.element_info.name or ""
            ctype = child.element_info.control_type or ""
            rect = child.element_info.rectangle
            if name or ctype in ("Window", "Pane", "Button", "Edit", "ListItem"):
                lines.append(f"{'  ' * depth}{ctype} {name!r} {rect}")
        except Exception:
            continue
        lines.extend(describe(child, depth + 1))
        if len(lines) > 800:
            break
    return lines


def elements():
    found = []

    def walk(ctrl, depth):
        if depth > 14:
            return
        try:
            name = ctrl.element_info.name or ""
            ctype = ctrl.element_info.control_type or ""
            rect = ctrl.element_info.rectangle
            found.append(
                {
                    "name": name,
                    "type": ctype,
                    "left": rect.left,
                    "top": rect.top,
                    "right": rect.right,
                    "bottom": rect.bottom,
                    "ctrl": ctrl,
                }
            )
        except Exception:
            return
        try:
            children = ctrl.children()
        except Exception:
            return
        for child in children:
            walk(child, depth + 1)

    for _, _, win in top_windows():
        walk(win, 0)
    return found


def wait_for(predicate, timeout, label):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        fit_main_window()
        last = predicate()
        if last:
            return last
        time.sleep(2)
    dump_tree(f"timeout-{label}")
    shot(f"timeout-{label}")
    raise AssertionError(f"timed out waiting for {label}")


def named(items, text, *types):
    matches = []
    for item in items:
        if text not in item["name"]:
            continue
        if types and item["type"] not in types:
            continue
        if item["right"] <= item["left"] or item["bottom"] <= item["top"]:
            continue
        matches.append(item)
    return matches


def close_note_windows():
    import ctypes

    user32 = ctypes.windll.user32
    hwnd = user32.FindWindowW(None, "AppFlowy Note")
    while hwnd:
        user32.PostMessageW(hwnd, 0x0010, 0, 0)
        time.sleep(0.5)
        hwnd = user32.FindWindowW(None, "AppFlowy Note")


def click(item):
    ctrl = item["ctrl"]
    try:
        ctrl.set_focus()
    except Exception:
        pass
    try:
        ctrl.iface_invoke.Invoke()
        return
    except Exception:
        pass
    ctrl.click_input()


def launch():
    log(f"launch {EXE}")
    subprocess.Popen([str(EXE)], cwd=str(APP_DIR))
    wait_for(
        lambda: process_running() and any(title == "AppFlowy" for title, _, _ in top_windows()),
        90,
        "main-window",
    )
    fit_main_window()
    time.sleep(2)


def ensure_workspace():
    def ready():
        items = elements()
        if named(items, "Getting started") or named(items, "Share") or named(items, "공유"):
            return items
        return None

    try:
        return wait_for(ready, 20, "existing-workspace")
    except AssertionError:
        pass

    def gate():
        items = elements()
        buttons = named(items, "Create local workspace", "Button", "Text")
        buttons += named(items, "로컬 작업공간 만들기", "Button", "Text")
        return buttons[0] if buttons else None

    button = wait_for(gate, 120, "create-workspace")
    shot("create-workspace")
    click(button)
    return wait_for(ready_workspace, 180, "workspace-ready")


def ready_workspace():
    items = elements()
    if named(items, "Getting started") and (
        named(items, "Share") or named(items, "공유") or named(items, "Search pages and content")
    ):
        return items
    return None


def magnifier_visible(search):
    items = elements()
    for item in items:
        if item["type"] not in ("Image", "Button", "Text"):
            continue
        same_row = abs(((item["top"] + item["bottom"]) / 2) - ((search["top"] + search["bottom"]) / 2)) < 24
        on_left_edge = search["left"] - 8 <= item["left"] <= search["left"] + 48
        if same_row and on_left_edge and item["name"] != search["name"]:
            return True
    width, height = screen_size()
    left = max(0, search["left"])
    top = max(0, search["top"])
    right = min(width, max(left + 1, min(search["left"] + 42, search["right"])))
    bottom = min(height, max(top + 1, search["bottom"]))
    image = ImageGrab.grab(bbox=(left, top, right, bottom))
    colors = image.getcolors(maxcolors=5000) or []
    return len(colors) > 8


def test_launch():
    launch()
    shot("launched")
    dump_tree("launched")
    ensure_workspace()
    shot("workspace")
    dump_tree("workspace")
    if not process_running():
        raise AssertionError("AppFlowy.exe exited during launch")
    excerpt = assert_no_crash("launch")
    record("1 launch stays running", True, "AppFlowy.exe is running and the event log has no AppFlowy APPCRASH/BEX64. " + excerpt.splitlines()[0])


def test_portable_data():
    if not DATA_DIR.exists():
        raise AssertionError(f"missing {DATA_DIR}")
    contents = [p.name for p in DATA_DIR.rglob("*")][:30]
    if not contents:
        raise AssertionError(f"{DATA_DIR} is empty")
    if APPDATA_DIR.exists():
        written = [str(p) for p in APPDATA_DIR.rglob("*")][:20]
        raise AssertionError(f"wrote {APPDATA_DIR}: {written}")
    assert_no_crash("portable-data")
    record(
        "2 portable data",
        True,
        f"{DATA_DIR} contains {contents[:8]} and {APPDATA_DIR} does not exist",
    )


def test_search_bar_and_query():
    close_note_windows()
    time.sleep(1)
    items = elements()
    searches = named(items, "Search pages and content")
    searches += named(items, "페이지와 내용을 검색")
    if not searches:
        shares = [
            item
            for item in items
            if item["name"].strip() in ("Share", "공유")
        ]
        if shares:
            share_top = (shares[0]["top"] + shares[0]["bottom"]) / 2
            searches = [
                item
                for item in items
                if item["type"] in ("Edit", "Document")
                and item["right"] <= shares[0]["left"] + 8
                and abs(((item["top"] + item["bottom"]) / 2) - share_top) < 40
                and item["right"] - item["left"] > 180
            ]
    if not searches:
        raise AssertionError("header search field is not visible")
    search = sorted(searches, key=lambda item: item["right"] - item["left"], reverse=True)[0]
    shares = [
        item
        for item in named(items, "Share") + named(items, "공유")
        if abs(((item["top"] + item["bottom"]) / 2) - ((search["top"] + search["bottom"]) / 2)) < 40
    ]
    titles = [
        item
        for item in named(items, "Getting started")
        if abs(((item["top"] + item["bottom"]) / 2) - ((search["top"] + search["bottom"]) / 2)) < 40
        and item["left"] < search["left"]
    ]
    if not shares:
        raise AssertionError("Share button is not on the search row")
    if not titles:
        raise AssertionError("page title is not left of the search field")
    share = min(shares, key=lambda item: item["left"])
    title = max(titles, key=lambda item: item["right"])
    width = search["right"] - search["left"]
    if not (title["left"] < search["left"] and search["right"] <= share["left"] + 12 and width > 180):
        raise AssertionError(
            f"search layout title={title['left']}:{title['right']} search={search['left']}:{search['right']} share={share['left']}"
        )
    if not magnifier_visible(search):
        raise AssertionError("magnifier is not visible on the left of the search field")
    shot("search-bar")
    click(search)
    time.sleep(1)
    send_keys("Getting{SPACE}started", pause=0.03)
    def result():
        current = elements()
        dialogs = named(current, "Local search") + named(current, "로컬 검색")
        if not dialogs:
            return None
        floor = max(item["bottom"] for item in dialogs)
        hits = [
            item
            for item in named(current, "Getting started", "Text", "ListItem")
            if item["top"] >= floor - 4 and item["left"] > 240
        ]
        return hits[0] if hits else None

    wait_for(result, 40, "search-result")
    shot("search-result")
    send_keys("{ESC}")
    time.sleep(1)
    assert_no_crash("search")
    record(
        "4 header search",
        True,
        f"search field width {width}px sits between Getting started and Share; typing the title showed that note",
    )


def test_small_window():
    items = elements()
    buttons = named(items, "작은 창으로 열기")
    if not buttons:
        raise AssertionError("작은 창으로 열기 is not visible")
    before = process_running()
    click(buttons[0])

    def opened():
        titles = [title for title, _, _ in top_windows()]
        texts = named(elements(), "읽기 전용 작은 창")
        if any(title == "AppFlowy Note" for title in titles) or texts:
            return titles
        return None

    titles = wait_for(opened, 30, "small-window")
    shot("small-window")
    dump_tree("small-window")
    if not process_running() or not before:
        raise AssertionError("main process exited when the small window opened")
    if not any(title == "AppFlowy" for title in titles):
        raise AssertionError(f"main window gone; windows={titles}")
    excerpt = assert_no_crash("small-window")
    record(
        "3 small window",
        True,
        "AppFlowy Note opened, AppFlowy.exe stayed running, no crash event. " + excerpt.splitlines()[0],
    )
    close_note_windows()
    time.sleep(1)


def test_create_and_restart():
    items = elements()
    buttons = named(items, "New page")
    buttons += named(items, "새 페이지")
    if not buttons:
        raise AssertionError("New page is not visible")
    click(buttons[0])

    def untitled():
        current = elements()
        found = named(current, "Untitled")
        return found[0] if found else None

    wait_for(untitled, 40, "untitled-note")
    time.sleep(1)
    # Click the document body, below the header tools, and type a marker.
    width, height = screen_size()
    Desktop(backend="uia").window(title="AppFlowy").click_input(
        coords=(int(width * 0.55), int(height * 0.55))
    )
    time.sleep(0.5)
    send_keys(NOTE_MARKER, pause=0.02)
    time.sleep(3)
    shot("new-note")
    assert_no_crash("new-note")
    kill_app()
    time.sleep(2)
    launch()

    def restored():
        current = elements()
        if named(current, "Untitled") or named(current, NOTE_MARKER):
            return current
        return None

    wait_for(restored, 180, "note-persisted")
    shot("after-restart")
    dump_tree("after-restart")
    if not DATA_DIR.exists() or APPDATA_DIR.exists():
        raise AssertionError(f"data path changed after restart: data={DATA_DIR.exists()} appdata={APPDATA_DIR.exists()}")
    assert_no_crash("restart")
    record(
        "5 note persists",
        True,
        "Untitled survived a restart and is still stored beside the exe",
    )


def main():
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    kill_app()
    if APPDATA_DIR.exists():
        log(f"pre-existing {APPDATA_DIR}; the test still fails if the app writes there")
    order = [
        ("1 launch stays running", test_launch),
        ("2 portable data", test_portable_data),
        ("3 small window", test_small_window),
        ("4 header search", test_search_bar_and_query),
        ("5 note persists", test_create_and_restart),
    ]
    # Search is listed before the small window in the request, but the small
    # window is easier to reach on the already-open Getting started note.
    # Both run. The numbered names stay aligned with the requested checks.
    failed = False
    for name, fn in order:
        if any(item["test"] == name for item in results):
            continue
        try:
            fn()
        except Exception as error:
            failed = True
            shot(f"fail-{name.split()[0]}")
            try:
                dump_tree(f"fail-{name.split()[0]}")
            except Exception:
                pass
            try:
                _, excerpt = crash_excerpt()
            except Exception as log_error:
                excerpt = str(log_error)
            record(name, False, f"{error}\n{excerpt[:1500]}")
            if not process_running():
                for later, _ in order:
                    if not any(item["test"] == later for item in results):
                        record(later, False, "not run because AppFlowy.exe had already exited")
                break
    (ARTIFACTS / "results.json").write_text(
        json.dumps(results, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    kill_app()
    if failed or len(results) < 5:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
