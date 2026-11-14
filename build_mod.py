"""Package the already-proven UE4SS loader and the PlayTools Lua sources."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parent
VERSION = '0.6.3-ue4ss'
GAME_EXE_SHA256 = '4415933ce33476f14c837abb61a1b60af8b78cd81783896501913a7aac69e423'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    payload = ROOT / 'manager/payload5'
    files = payload / 'files'
    framework = ROOT / 'vendor/ue4ss'
    sources = {'platform/steam/dwmapi.dll': framework / 'dwmapi.dll'}
    for name in ('UE4SS.dll', 'UE4SS-settings.ini', 'MemberVariableLayout.ini', 'LICENSE'):
        sources['platform/steam/ue4ss/' + name] = framework / 'ue4ss' / name
    for source in (framework / 'ue4ss/UE4SS_Signatures').glob('*.lua'):
        sources['platform/steam/ue4ss/UE4SS_Signatures/' + source.name] = source
    helper = framework / 'ue4ss/Mods/shared/UEHelpers/UEHelpers.lua'
    sources['platform/steam/ue4ss/Mods/shared/UEHelpers/UEHelpers.lua'] = helper
    for source in (ROOT / 'lua/PBZPlayTools/Scripts').glob('*.lua'):
        sources['platform/steam/ue4ss/Mods/PBZPlayTools/Scripts/' + source.name] = source
    for staged in (files / 'platform/steam/ue4ss/Mods/PBZPlayTools/Scripts').glob('*.lua'):
        if staged.relative_to(files).as_posix() not in sources:
            staged.unlink()
    for relative, source in sources.items():
        target = files / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    enabled = files / 'platform/steam/ue4ss/Mods/PBZPlayTools/enabled.txt'
    enabled.write_text('', encoding='utf-8')
    entries = sorted(list(sources) + [enabled.relative_to(files).as_posix()])
    hashes = {'files/' + relative: sha256(files / relative) for relative in entries}
    manifest = {'version': VERSION, 'steam_build': '26367565', 'game_exe_sha256': GAME_EXE_SHA256,
                'files': entries, 'payload_sha256': hashes}
    (payload / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    (ROOT / 'dist').mkdir(exist_ok=True)
    (ROOT / 'dist/build.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'version': VERSION, 'files': len(entries), 'framework': 'UE4SS 4.0.0'}, indent=2))


if __name__ == '__main__':
    main()
