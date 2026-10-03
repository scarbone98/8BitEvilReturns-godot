#!/usr/bin/env python3
"""Runs every weapon (base -> evolved via chest) and every union headless,
reporting script errors and whether the evolution happened. Dev tool."""
import re, subprocess, sys
src = open('src/data/weapons.gd').read()
base = re.findall(r'^\t"(\w+)": \{\n\t\t"name"', src, re.M)
evo = dict(re.findall(r'^\t"(\w+)": \{\n(?:\t\t.*\n)*?\t\t"evolve": \{"with": "(\w+)"', src, re.M))
union = re.findall(r'^\t"(\w+)": \{\n(?:\t\t.*\n)*?\t\t"union": \{"with": "(\w+)", "into": "(\w+)"', src, re.M)
cases = [(w, ",".join([w] * 8 + ([evo[w]] if w in evo else []))) for w in base]
cases += [(f"{a}+{b}", ",".join([a] * 8 + [b] * 8)) for a, b, _ in union]
bad = 0
for name, give in cases:
    out = subprocess.run(["godot4", "--headless", "--path", ".", "--quit-after", "900", "--",
        "--autoplay", "--dev", "--minute=3", "--chest", "--speed=2", f"--give={give}", "--char=matt"],
        capture_output=True, text=True, timeout=180).stdout + ""
    errs = [l for l in out.splitlines() if ("SCRIPT ERROR" in l or "ERROR:" in l) and "X509" not in l]
    status = [l for l in out.splitlines() if l.startswith("[")]
    print(f"{name:28s} {'ERR' if errs else 'ok '} {status[-1][:150] if status else ''}")
    for e in errs[:3]: print("    ", e)
    bad += bool(errs)
sys.exit(1 if bad else 0)
