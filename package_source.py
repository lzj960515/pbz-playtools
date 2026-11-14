"""Archive the tracked publication sources and record release asset digests."""
from pathlib import Path
import hashlib
import json
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent


def main():
    manifest = json.loads((ROOT / 'dist/build.json').read_text(encoding='utf-8'))
    version = manifest['version'].removesuffix('-ue4ss')
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0')
    names = [name for name in names if name]
    archive_path = ROOT / 'dist' / f'PBZ-PlayTools-{version}-source.zip'
    prefix = f'PBZ-PlayTools-{version}-source/'
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in names:
            archive.write(ROOT / name, prefix + name)
    with zipfile.ZipFile(archive_path) as archive:
        for name in names:
            assert archive.read(prefix + name) == (ROOT / name).read_bytes(), name
    assets = [ROOT / 'manager/dist' / manifest['version'] / 'PBZ-PlayTools.exe',
              ROOT / 'dist' / f"PBZ-PlayTools-{manifest['version']}.zip", archive_path]
    checksums = ['{}  {}'.format(hashlib.sha256(path.read_bytes()).hexdigest(), path.name) for path in assets]
    (ROOT / 'dist/SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n', encoding='utf-8')
    print(json.dumps({'source_zip': str(archive_path), 'source_files': len(names), 'checksums': checksums}, indent=2))


if __name__ == '__main__':
    main()
