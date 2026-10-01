#!/usr/bin/env python3
"""Faithfully convert the owner-supplied ICNS to the required package PNG on macOS."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
if __name__ == '__main__':
    if sys.platform != 'darwin':
        raise SystemExit('Icon conversion requires macOS sips.')
    subprocess.run(['/usr/bin/sips', '-s', 'format', 'png', '-z', '512', '512',
                    str(ROOT / 'assets/xcode-liquid-glass.icns'), '--out',
                    str(ROOT / 'XcodeBuildStatus.dynamiclakeplugin/icon.png')], check=True)
    subprocess.run(['/usr/bin/sips', '-s', 'format', 'png', '-z', '128', '128',
                    str(ROOT / 'XcodeBuildStatus.dynamiclakeplugin/icon.png'), '--out',
                    str(ROOT / 'XcodeBuildStatus.dynamiclakeplugin/xcode-icon.png')], check=True)
