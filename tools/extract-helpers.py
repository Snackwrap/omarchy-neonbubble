#!/usr/bin/env python3
"""Assemble the perl score helpers exactly as QML concatenates them.

The point is that check-score-io.sh tests the *shipped* strings rather than a
hand-copied approximation that can drift away from Panel.qml without anyone
noticing.

Usage: extract-helpers.py Panel.qml <read-out> <write-out>
"""
import json
import pathlib
import re
import sys


def block(text, name):
    m = re.search(r"readonly property string %s:\n((?:.*\n)*?)\n" % name, text)
    if not m:
        sys.exit("no such property in Panel.qml: " + name)
    return m.group(1)


def assemble(body, pid, walk):
    acc = ""
    for line in body.split("\n"):
        for tok in re.findall(r'"(?:[^"\\]|\\.)*"|root\.pluginId|root\.walkScript', line):
            if tok == "root.pluginId":
                acc += pid
            elif tok == "root.walkScript":
                acc += walk
            else:
                acc += json.loads(tok)
    return acc


qml = pathlib.Path(sys.argv[1]).read_text()
pid = re.search(r'pluginId: "([\w.]+)"', qml).group(1)
walk = assemble(block(qml, "walkScript"), pid, "")
pathlib.Path(sys.argv[2]).write_text(assemble(block(qml, "safeReadScript"), pid, walk))
pathlib.Path(sys.argv[3]).write_text(assemble(block(qml, "safeWriteScript"), pid, walk))
print(pid)
