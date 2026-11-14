"""Install the UE4SS runtime and PlayTools Lua mod; never start the game."""
from __future__ import annotations
import csv
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import threading
from runtime import VERSION, atomic_json, control_directory, read_control

DEFAULT_GAME = r'E:\SteamLibrary\steamapps\common\PBZ'
METADATA = 'ProjectPBZ/Content/Paks/~mods/PBZPlayTools.json'
MOD = 'platform/steam/ue4ss/Mods/PBZPlayTools'
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


class InstallationService:
    def __init__(self, resources: Path):
        self._payload = resources / 'payload'
        self._lock = threading.Lock()

    @staticmethod
    def _game_root(directory: str) -> Path:
        root = Path(directory).expanduser().resolve()
        if not (root / 'platform/steam/PBZ.exe').is_file():
            raise ValueError('请选择包含 platform\\steam\\PBZ.exe 的游戏根目录。')
        return root

    @staticmethod
    def _ensure_game_closed() -> None:
        result = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True,
                                text=True, errors='replace', check=True, creationflags=NO_WINDOW)
        if any(row and row[0].lower() == 'pbz.exe' for row in csv.reader(io.StringIO(result.stdout))):
            raise RuntimeError('请先退出游戏')

    def inspect(self, directory: str) -> dict:
        root = self._game_root(directory)
        saved = json.loads((root / METADATA).read_text(encoding='utf-8')) if (root / METADATA).is_file() else {}
        settings = {'randomWeapons': saved.get('randomWeapons', False),
                    'randomShadowWeapons': saved.get('randomShadowWeapons', False)}
        settings.update({key: value for key, value in read_control(root).get('settings', {}).items()
                         if key in settings})
        return {'directory': str(root), 'installed': (root / MOD / 'enabled.txt').is_file(),
                'version': saved.get('version'), 'settings': settings}

    def install(self, directory: str, settings: dict) -> dict:
        with self._lock:
            root = self._game_root(directory)
            self._ensure_game_closed()
            manifest = json.loads((self._payload / 'manifest.json').read_text(encoding='utf-8'))
            if file_hash(root / 'platform/steam/PBZ.exe') != manifest['game_exe_sha256']:
                raise ValueError('游戏 EXE 不是本版原文件。若装过 0.4，请先用 0.4 卸载还原，再安装本版。')
            saved = json.loads((root / METADATA).read_text(encoding='utf-8')) if (root / METADATA).is_file() else {}
            owned = set(saved.get('owned_files', []))
            files = manifest['files']
            for relative in files:
                target = root / relative
                if target.is_file() and not relative.startswith(MOD) and relative not in owned:
                    if file_hash(target) != manifest['payload_sha256']['files/' + relative]:
                        raise ValueError(f'游戏目录已有其他版本框架文件，请先移出：{target}')
            for relative in files:
                target = root / relative
                if not target.exists() or relative.startswith(MOD):
                    owned.add(relative)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(self._payload / 'files' / relative, target)
            for relative in owned - set(files):
                if relative.startswith(MOD + '/'):
                    (root / relative).unlink(missing_ok=True)
                    owned.discard(relative)
            channel = control_directory(root)
            channel.mkdir(parents=True, exist_ok=True)
            config = {key: settings.get(key) is True for key in ('randomWeapons', 'randomShadowWeapons')}
            config.update(fragmentsEnabled=False, mapTarget='', mapItemID='')
            atomic_json(channel / 'control.json', {'protocol': 1, 'revision': 'installation', 'settings': config})
            (channel / 'status.json').unlink(missing_ok=True)
            lua_config = ('return { directory = ' + json.dumps(channel.as_posix(), ensure_ascii=False)
                          + ', version = "' + VERSION + '" }\n')
            (root / MOD / 'Scripts/config.lua').write_text(lua_config, encoding='utf-8', newline='\n')
            for name in ('zzz_PBZPlayTools_P.pak', 'zzz_PBZFragmentFinder_P.pak'):
                (channel.parent / name).unlink(missing_ok=True)
            metadata = {**config, 'version': VERSION, 'owned_files': sorted(owned)}
            atomic_json(root / METADATA, metadata)
            return {**self.inspect(str(root)), 'message': '已安装'}

    def uninstall(self, directory: str) -> dict:
        with self._lock:
            root = self._game_root(directory)
            self._ensure_game_closed()
            saved = json.loads((root / METADATA).read_text(encoding='utf-8'))
            if saved.get('version') != VERSION:
                raise ValueError('请使用安装该版本的工具卸载。0.4 需要同时还原原版校验记录。')
            for relative in saved['owned_files']:
                (root / relative).unlink(missing_ok=True)
            (root / METADATA).unlink()
            for name in ('control.json', 'status.json'):
                (control_directory(root) / name).unlink(missing_ok=True)
            return {**self.inspect(str(root)), 'message': '已卸载'}
