#!/usr/bin/env python3
"""Capture the production GTK daemon in an isolated X11 desktop. Requires Xvfb,
openbox, xcompmgr, xsetroot, ImageMagick, dbus-run-session, and python3-pil.
Run through dbus-run-session; screenshots contain only synthetic identity data.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from PIL import Image

root = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
subprocess.run(["cargo", "build", "-p", "nameplate"], cwd=root / "linux", check=True)
target = Path(os.environ.get("CARGO_TARGET_DIR", root / "linux/target"))
binary = target / "debug/nameplate"
positions = ["topLeft", "topCenter", "topRight", "leftCenter", "rightCenter", "bottomLeft", "bottomCenter", "bottomRight"]
cases = [(p, 0, 0) for p in positions] + [("rightCenter", 0, -100), ("rightCenter", 0, 100), ("topCenter", -100, 0), ("bottomRight", 100000, 100000)]
rows = []
with tempfile.TemporaryDirectory(prefix="nameplate-x11-") as temporary:
    work = Path(temporary)
    read_fd, write_fd = os.pipe()
    processes = []
    try:
        xvfb = subprocess.Popen(["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1280x800x24", "-nolisten", "tcp", "-noreset"], pass_fds=(write_fd,))
        processes.append(xvfb)
        os.close(write_fd)
        display = os.read(read_fd, 32).decode().strip()
        os.close(read_fd)
        env = dict(os.environ, DISPLAY=":" + display, XDG_CONFIG_HOME=str(work / "config"), XDG_RUNTIME_DIR=str(work / "runtime"), GDK_BACKEND="x11", GSK_RENDERER="cairo")
        (work / "runtime").mkdir(mode=0o700)
        config_dir = work / "config/nameplate"
        config_dir.mkdir(parents=True)
        for command in (["openbox"], ["xcompmgr"]):
            processes.append(subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(0.6)
        subprocess.run(["xsetroot", "-solid", "#0f141a"], env=env, check=True)
        with (output / "daemon.log").open("w") as log:
            for index, (position, x, y) in enumerate(cases):
                config = dict(name="Evidence machine", glyph="★", color="#1D9E75", useFleetFile=False,
                    frameEnabled=False, tagEnabled=True, watermarkEnabled=False, splashEnabled=False,
                    tagCorner=position, tagHorizontalOffset=x, tagVerticalOffset=y)
                staged = config_dir / "next.json"
                staged.write_text(json.dumps(config))
                staged.replace(config_dir / "settings.json")
                if index == 0:
                    processes.append(subprocess.Popen([str(binary)], env=env, stdout=log, stderr=log))
                time.sleep(5 if index == 0 else 1)
                if processes[-1].poll() is not None:
                    raise RuntimeError("Production GTK daemon exited.")
                subprocess.run(["xwininfo", "-root", "-tree"], env=env, check=True, stdout=(output / "windows.txt").open("w"))
                file = f"{position}-{x}-{y}.png"
                subprocess.run(["import", "-window", "root", str(output / file)], env=env, check=True)
                image = Image.open(output / file).convert("RGB")
                pixels = [(px, py) for py in range(image.height) for px in range(image.width)
                    if all(abs(a - b) <= 8 for a, b in zip(image.getpixel((px, py)), (29, 158, 117)))]
                if len(pixels) < 100:
                    raise RuntimeError(f"No visible production tag captured for {position}.")
                left = min(px for px, _ in pixels); right = max(px for px, _ in pixels)
                top = min(py for _, py in pixels); bottom = max(py for _, py in pixels)
                width, height = right - left + 1, bottom - top + 1
                h_anchor = "start" if position in ("topLeft", "leftCenter", "bottomLeft") else "center" if position in ("topCenter", "bottomCenter") else "end"
                v_anchor = "start" if position in ("topLeft", "topCenter", "topRight") else "center" if position in ("leftCenter", "rightCenter") else "end"
                def origin(anchor, extent, item, offset):
                    available = extent - item
                    value = 14 + max(0, offset) if anchor == "start" else available - 14 - max(0, offset) if anchor == "end" else available / 2 + offset
                    return min(max(value, 14), available - 14)
                expected_x = origin(h_anchor, image.width, width, x)
                expected_y = origin(v_anchor, image.height, height, y)
                if abs(left - expected_x) > 2 or abs(top - expected_y) > 2:
                    raise RuntimeError(f"Wrong captured placement for {position}: {left},{top} vs {expected_x},{expected_y}.")
                rows.append(dict(position=position, horizontalOffset=x, verticalOffset=y, displayWidth=image.width,
                    displayHeight=image.height, scale=1, screenshot=file, greenPixels=len(pixels),
                    capturedPixelBounds=dict(left=left, top=top, right=right, bottom=bottom)))
                print(f"Verified live GTK capture: {file}", flush=True)
        subprocess.run(["xwininfo", "-root", "-tree"], env=env, check=True, stdout=(output / "windows.txt").open("w"))
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
(output / "runtime.json").write_text(json.dumps(dict(
    revision=os.environ.get("NAMEPLATE_EVIDENCE_SHA", subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()),
    environment="Production GTK daemon in an isolated Xvfb X11 desktop with Openbox and xcompmgr; one virtual 1280×800 monitor at 1×", cases=rows), indent=2) + "\n")
