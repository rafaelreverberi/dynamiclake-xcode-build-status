#!/usr/bin/env python3
"""Build, validate and archive the dependency-free universal macOS JSON plugin."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'XcodeBuildStatus.dynamiclakeplugin'
EXPECTED_FILES = {'plugin.json', 'icon.png', 'xcode-icon.png', 'xcode-build-status'}
LIMITS = {'archive': 7_000_000, 'package': 20_000_000, 'manifest': 128_000, 'icon': 1_500_000}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_manifest(data: bytes, changelog: str) -> dict:
    require(len(data) <= LIMITS['manifest'], 'Manifest exceeds 128 KB')
    m = json.loads(data)
    require(m.get('schemaVersion') == 1, 'Unexpected schema version')
    require(m.get('identifier') == 'com.dynamiclake.plugins.xcode-build-status', 'Unexpected identifier')
    require(m.get('developerName') == 'Rafael Reverberi', 'Unexpected developer name')
    require(m.get('name') == 'Xcode Build Status', 'Unexpected name')
    version = m.get('version')
    require(isinstance(version, str) and re.fullmatch(r'\d+\.\d+\.\d+', version) is not None, 'Invalid semantic version')
    require(f'## {version} ' in changelog, 'Changelog lacks version')
    require(m.get('executable') == 'xcode-build-status' and m.get('icon') == 'icon.png', 'Unexpected package paths')
    require(m.get('arguments') == [] and m.get('autoStart') is True, 'Invalid launch configuration')
    settings = m.get('settings', [])
    require(len(settings) == 3, 'Exactly three settings are required')
    require({s.get('id') for s in settings} == {'successDisplaySeconds', 'failureDisplaySeconds', 'iconStyle'}, 'Unexpected settings')
    for key, default, tint in [('successDisplaySeconds', 3, 'green'), ('failureDisplaySeconds', 5, 'red')]:
        s = next(s for s in settings if s['id'] == key)
        require(s.get('type') == 'slider' and s.get('min') == 1 and s.get('max') == 10 and s.get('step') == 1 and s.get('default') == default and s.get('suffix') == 'sec', f'Invalid slider: {key}')
        require(s.get('tint') == tint and bool(s.get('systemImage')), f'Invalid slider appearance: {key}')
    icon = next(s for s in settings if s['id'] == 'iconStyle')
    require(icon.get('type') == 'select' and icon.get('default') == 'Hammer (SF Symbol)', 'Invalid icon selector')
    require(icon.get('options') == [{'title': 'Hammer (SF Symbol)', 'systemImage': 'hammer.fill'},
                                   {'title': 'Xcode App Icon', 'systemImage': 'photo'}], 'Invalid icon choices')
    return m


def validate_package(package: Path, changelog: str) -> dict:
    paths = list(package.rglob('*'))
    require(all(p.is_file() and not p.is_symlink() for p in paths), 'Package contains a symlink, directory or non-file')
    require({p.name for p in paths} == EXPECTED_FILES, 'Unexpected package files or debug artifacts')
    require(sum(p.stat().st_size for p in paths) <= LIMITS['package'], 'Package exceeds 20 MB')
    m = validate_manifest((package / 'plugin.json').read_bytes(), changelog)
    executable = package / m['executable']
    require(executable.is_file() and bool(executable.stat().st_mode & stat.S_IXUSR), 'Missing executable permission')
    icon = (package / m['icon']).read_bytes()
    require(len(icon) <= LIMITS['icon'] and icon.startswith(b'\x89PNG\r\n\x1a\n') and icon[12:16] == b'IHDR', 'Invalid PNG icon')
    require(struct.unpack('>II', icon[16:24]) == (512, 512), 'Icon must be 512 x 512')
    runtime_icon = (package / 'xcode-icon.png').read_bytes()
    require(len(runtime_icon) <= 15_500 and runtime_icon.startswith(b'\x89PNG\r\n\x1a\n') and
            runtime_icon[12:16] == b'IHDR' and struct.unpack('>II', runtime_icon[16:24]) == (128, 128),
            'Invalid or oversized runtime icon')
    return m


def validate_archive(path: Path, package_name: str = PACKAGE.name) -> None:
    require(path.stat().st_size <= LIMITS['archive'], 'Archive exceeds 7 MB')
    with zipfile.ZipFile(path) as z:
        require(z.testzip() is None, 'ZIP integrity failed')
        require(set(z.namelist()) == {package_name + '/' + n for n in EXPECTED_FILES}, 'Invalid top-level archive structure')
        for info in z.infolist():
            require(info.create_system == 3 and stat.S_ISREG(info.external_attr >> 16), 'Non-regular ZIP member')
        require(stat.S_IMODE(z.getinfo(package_name + '/xcode-build-status').external_attr >> 16) & stat.S_IXUSR, 'ZIP loses executable bit')
        require(sum(i.file_size for i in z.infolist()) <= LIMITS['package'], 'ZIP exceeds extracted size limit')


def run(*args: str) -> None:
    subprocess.run(args, cwd=ROOT, check=True)


def main() -> int:
    require(sys.platform == 'darwin', 'Native builds require macOS and Xcode Command Line Tools')
    # Validate immutable metadata before touching the bundled executable.
    changelog = (ROOT / 'CHANGELOG.md').read_text()
    m = validate_manifest((PACKAGE / 'plugin.json').read_bytes(), changelog)
    run('swift', 'test', '--build-system', 'native')
    run(sys.executable, '-B', '-m', 'unittest', 'discover', '-s', 'Tests', '-v')
    build_args = ['swift', 'build', '--build-system', 'native', '-c', 'release', '--arch', 'arm64', '--arch', 'x86_64']
    run(*build_args)
    binary_dir = Path(subprocess.check_output(build_args + ['--show-bin-path'], cwd=ROOT, text=True).strip())
    executable = PACKAGE / 'xcode-build-status'
    shutil.copyfile(binary_dir / 'xcode-build-status', executable)
    executable.chmod(0o755)
    run('strip', '-S', str(executable))
    run('codesign', '--force', '--sign', '-', str(executable))
    run('codesign', '--verify', '--strict', str(executable))
    archs = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
    require(set(archs) == {'arm64', 'x86_64'}, 'Runtime must be universal arm64/x86_64')
    run(str(executable), '--check')
    validate_package(PACKAGE, changelog)
    output = ROOT / 'dist'
    output.mkdir(exist_ok=True)
    archive = output / f"Xcode-Build-Status-{m['version']}.zip"
    temp = archive.with_suffix('.zip.tmp')
    # Stable ZIP timestamps and modes; byte reproducibility of native builds still depends on toolchain.
    with zipfile.ZipFile(temp, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name in sorted(EXPECTED_FILES):
            path = PACKAGE / name
            info = zipfile.ZipInfo(f'{PACKAGE.name}/{name}', date_time=(2026, 9, 30, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (0o755 if name == m['executable'] else 0o644)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, path.read_bytes())
    validate_archive(temp)
    temp.replace(archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    print(f'Created {archive.name} ({archive.stat().st_size:,} bytes); SHA-256 {digest}')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Release validation failed: {error}', file=sys.stderr)
        raise SystemExit(1)
