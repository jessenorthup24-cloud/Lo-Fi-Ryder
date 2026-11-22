#!/usr/bin/env python3
"""Downloads the CC0 tracks listed in sources.json, picks the usable ones, normalizes and encodes them.

    python3 tools/music/prepare_music.py tools/music/sources.json OUT_DIR

Writes OUT_DIR/tracks/*.ogg, OUT_DIR/tracks.json (file, title, artist, license, page) and OUT_DIR/log.txt.
Runs in CI (the build machine can reach the music sites); the result is cached on the `music` branch.
A source that fails to download is logged and skipped.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

AUDIO = (".mp3", ".ogg", ".wav", ".flac", ".m4a")
MIN_S, MAX_S = 75.0, 420.0


def log(out, msg):
    print(msg)
    with open(os.path.join(out, "log.txt"), "a") as f:
        f.write(msg + "\n")


def duration(path):
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                           capture_output=True, text=True, timeout=60)
        return float(r.stdout.strip())
    except Exception:
        return 0.0


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")[:48] or "track"


def bare(name):
    t = os.path.basename(name)
    while os.path.splitext(t)[1].lower() in AUDIO:
        t = os.path.splitext(t)[0]
    return t


def nice_title(name):
    t = bare(name)
    t = re.sub(r"^\d+[\s._-]*", "", t)
    t = re.sub(r"(?i)holizna(cc0)?|[-_ ]*\(?cc0\)?", "", t)
    t = re.sub(r"[_]+", " ", t).strip(" -_")
    return t[:1].upper() + t[1:] if t else "Untitled"


def main():
    src_file, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, "tracks"), exist_ok=True)
    cfg = json.load(open(src_file))
    tracks = []
    work = tempfile.mkdtemp()
    for i, s in enumerate(cfg["sources"]):
        url = s["url"]
        dl = os.path.join(work, "src%d_%s" % (i, os.path.basename(url)))
        r = subprocess.run(["curl", "-sSL", "--retry", "3", "--max-time", "600", "-A", "Mozilla/5.0 (Lo-Fi Ryder build)",
                            "-o", dl, "-w", "%{http_code}", url], capture_output=True, text=True)
        code = r.stdout.strip()
        size = os.path.getsize(dl) if os.path.exists(dl) else 0
        if code != "200" or size < 50000:
            log(out, "SKIP %s: http %s, %d bytes %s" % (url, code, size, r.stderr.strip()[:200]))
            continue
        files = []
        if zipfile.is_zipfile(dl):
            d = os.path.join(work, "x%d" % i)
            with zipfile.ZipFile(dl) as z:
                z.extractall(d)
            for root, _, names in os.walk(d):
                for n in names:
                    if n.lower().endswith(AUDIO) and not n.startswith("._"):
                        files.append(os.path.join(root, n))
        else:
            files.append(dl)
        # the same song often ships as both .mp3 and .ogg: keep one (prefer ogg)
        by_name = {}
        for f in sorted(files):
            k = bare(f).lower()
            if k not in by_name or f.lower().endswith(".ogg"):
                by_name[k] = f
        files = sorted(by_name.values())
        log(out, "OK %s: %d bytes, %d songs" % (url, size, len(files)))
        wanted = [w.lower() for w in s.get("pick", [])]
        if wanted:
            files = sorted(files, key=lambda f: next((i for i, w in enumerate(wanted) if w in bare(f).lower()), 999))
        picked = 0
        for f in files:
            dur = duration(f)
            log(out, "   %6.1fs  %s" % (dur, os.path.basename(f)))
            if wanted and not any(w in bare(f).lower() for w in wanted):
                continue
            if picked >= int(s.get("max", 3)) or not (MIN_S <= dur <= MAX_S):
                continue
            title = s.get("title") if len(files) == 1 and s.get("title") else nice_title(f)
            name = "%s_%s.ogg" % (slug(s["artist"]), slug(title))
            dst = os.path.join(out, "tracks", name)
            enc = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f, "-vn",
                                  "-af", "loudnorm=I=-17:TP=-1.5:LRA=11,afade=t=in:d=0.8",
                                  "-ac", "2", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "1.5", dst],
                                 capture_output=True, text=True)
            if enc.returncode != 0:
                log(out, "   encode failed: %s" % enc.stderr[:300])
                continue
            picked += 1
            tracks.append({"file": name, "title": title, "artist": s["artist"], "album": s.get("album", ""),
                           "license": s["license"], "page": s.get("page", url), "seconds": round(dur, 1)})
            log(out, "   + %s (%.1f MB)" % (name, os.path.getsize(dst) / 1048576.0))
    json.dump({"tracks": tracks}, open(os.path.join(out, "tracks.json"), "w"), indent=1)
    total = sum(os.path.getsize(os.path.join(out, "tracks", t["file"])) for t in tracks)
    log(out, "DONE %d tracks, %.1f MB" % (len(tracks), total / 1048576.0))
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
