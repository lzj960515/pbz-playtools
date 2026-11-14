"""Verify the built EXE as an archive and assemble the user delivery package.

This reads packaged resources without starting the EXE or importing its app code.
Run with manager/.venv/Scripts/python.exe after the mod and desktop builds.
"""
from pathlib import Path
import hashlib
import json
import zipfile

from PyInstaller.archive.readers import CArchiveReader

ROOT = Path(__file__).resolve().parent
MANAGER = ROOT / 'manager'
PAYLOAD = MANAGER / 'payload5'


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify_executable(executable: Path, manifest: dict) -> dict:
    archive = CArchiveReader(str(executable))
    names = {name.replace('\\', '/'): name for name in archive.toc}
    expected = {
        'app.json': (MANAGER / 'app.json').read_bytes(),
        'payload/manifest.json': (PAYLOAD / 'manifest.json').read_bytes(),
    }
    for path in (MANAGER / 'frontend').rglob('*'):
        if path.is_file():
            expected[path.relative_to(MANAGER).as_posix()] = path.read_bytes()
    for relative, expected_hash in manifest['payload_sha256'].items():
        path = PAYLOAD / relative
        content = path.read_bytes()
        if digest(content) != expected_hash:
            raise ValueError(f'Payload hash differs: {relative}')
        expected['payload/' + relative] = content
    resource_names = {name for name in names if name.startswith(('payload/', 'frontend/')) or name == 'app.json'}
    if resource_names != set(expected):
        raise ValueError(f'Unexpected EXE resource inventory: {resource_names ^ set(expected)}')
    for name, content in expected.items():
        if archive.extract(names[name]) != content:
            raise ValueError(f'EXE resource differs from current build: {name}')
    pyz_name = next(name for name, entry in archive.toc.items() if entry[-1] == 'z')
    modules = archive.open_embedded_archive(pyz_name).toc
    for module in ('desktop', 'installation', 'runtime',
                   'webview', 'webview.platforms.edgechromium', 'clr', 'pythonnet'):
        if module not in modules:
            raise ValueError(f'Required packaged module is missing: {module}')
    for dependency in ('WebView2Loader.dll', 'Microsoft.Web.WebView2.Core.dll',
                       'Microsoft.Web.WebView2.WinForms.dll', 'Python.Runtime.dll'):
        if not any(Path(name).name == dependency for name in names):
            raise ValueError(f'Required packaged dependency is missing: {dependency}')
    return {'matched_resources': len(expected), 'required_modules_present': True,
            'required_webview_dependencies_present': True, 'app_execution': 'not performed'}


def main() -> None:
    manifest = json.loads((PAYLOAD / 'manifest.json').read_text(encoding='utf-8'))
    executable = MANAGER / 'dist' / manifest['version'] / 'PBZ-PlayTools.exe'
    build = json.loads((ROOT / 'dist/build.json').read_text(encoding='utf-8'))
    if manifest != {key: build[key] for key in manifest}:
        raise ValueError('Desktop payload and mod build records differ')
    checks = verify_executable(executable, manifest)
    files = {'PBZ-PlayTools.exe': executable.read_bytes(),
             'README.md': (ROOT / 'README.md').read_bytes(),
             'TESTING.md': (ROOT / 'TESTING.md').read_bytes(),
             'build.json': (ROOT / 'dist/build.json').read_bytes(),
             'licenses/UE4SS-MIT.txt': (ROOT / 'vendor/ue4ss/ue4ss/LICENSE').read_bytes(),
             'docs/images/tool.png': (ROOT / 'docs/images/tool.png').read_bytes()}
    record = {'version': manifest['version'], 'steam_build': manifest['steam_build'],
              'checks': checks, 'files_sha256': {name: digest(content) for name, content in files.items()}}
    files['release.json'] = json.dumps(record, ensure_ascii=False, indent=2).encode('utf-8')
    release = ROOT / 'dist' / ('PBZ-PlayTools-' + manifest['version'] + '.zip')
    with zipfile.ZipFile(release, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        for name, content in files.items():
            package.writestr(name, content)
    with zipfile.ZipFile(release) as package:
        if set(package.namelist()) != set(files):
            raise ValueError('Release ZIP inventory differs')
        for name, content in files.items():
            if package.read(name) != content:
                raise ValueError(f'Release ZIP content differs: {name}')
    record['zip_sha256'] = digest(release.read_bytes())
    (ROOT / 'dist/release.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'release': str(release), **record}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
