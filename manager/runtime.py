"""Exchange settings and explicit upgrade requests with the loaded game plugin."""
from __future__ import annotations
import json
import os
from pathlib import Path
import threading
import time
import uuid

VERSION = '0.6.3-ue4ss'
PROTOCOL = 1


def control_directory(root: Path) -> Path:
    return root / 'ProjectPBZ/Content/Paks/~mods/PBZPlayTools'


def atomic_json(path: Path, value: dict) -> None:
    incoming = path.with_name(path.name + '.incoming')
    try:
        incoming.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(incoming, path)
    finally:
        incoming.unlink(missing_ok=True)


def read_control(root: Path) -> dict:
    path = control_directory(root) / 'control.json'
    return json.loads(path.read_text(encoding='utf-8-sig')) if path.is_file() else {'protocol': PROTOCOL}


class RuntimeService:
    def __init__(self):
        self._lock = threading.Lock()

    @staticmethod
    def status(root: Path) -> dict:
        path = control_directory(root) / 'status.json'
        disconnected = {'connected': False, 'ready': False,
                        'message': '等待连接'}
        if not path.is_file():
            return disconnected
        try:
            state = json.loads(path.read_text(encoding='utf-8-sig'))
        except (json.JSONDecodeError, UnicodeDecodeError):
            # 游戏正写心跳时读到半个JSON，留给下一次只读检查。
            return {**disconnected, 'message': '正在连接…'}
        age = time.time() * 1000 - state.get('updatedAt', 0)
        if state.get('protocol') != PROTOCOL or state.get('version') != VERSION:
            return {**disconnected, 'message': '插件版本不同，请更新'}
        if not 0 <= age <= 5000:
            return {**disconnected, 'message': '连接已中断'}
        ready = state.get('ready') is True
        return {**state, 'connected': True, 'ready': ready,
                'message': '已连接' if ready else '等待进入存档'}

    @staticmethod
    def _require_installation(root: Path) -> None:
        path = root / 'ProjectPBZ/Content/Paks/~mods/PBZPlayTools.json'
        installed = (root / 'platform/steam/ue4ss/Mods/PBZPlayTools/enabled.txt').is_file() and path.is_file()
        version = json.loads(path.read_text(encoding='utf-8')).get('version') if installed else None
        if version != VERSION:
            raise RuntimeError('请先更新插件')

    def save_settings(self, root: Path, settings: dict) -> dict:
        with self._lock:
            self._require_installation(root)
            control = read_control(root)
            updated_settings = control.get('settings', {})
            updated_settings.update({key: settings.get(key) is True
                                     for key in ('randomWeapons', 'randomShadowWeapons')})
            control.update(protocol=PROTOCOL, revision=uuid.uuid4().hex,
                           settings=updated_settings)
            atomic_json(control_directory(root) / 'control.json', control)
            return {'revision': control['revision'],
                    'message': '设置已发送'}

    def fragments(self, root: Path, enabled: bool) -> dict:
        with self._lock:
            self._require_installation(root)
            control = read_control(root)
            control['settings'].update(fragmentsEnabled=enabled)
            control['revision'] = uuid.uuid4().hex
            atomic_json(control_directory(root) / 'control.json', control)
            return {'message': '已开启碎片显示' if enabled else '已关闭碎片显示'}

    def search_items(self, root: Path, query: str) -> dict:
        query = query.strip()
        if not query:
            raise ValueError('请输入物品名称')
        with self._lock:
            self._require_installation(root)
            state = self.status(root)
            if not state['connected'] or not state['ready']:
                raise RuntimeError('请先连接游戏存档')
            control = read_control(root)
            request_id = uuid.uuid4().hex
            control['itemSearch'] = {'id': request_id, 'query': query}
            atomic_json(control_directory(root) / 'control.json', control)
            return {'requestId': request_id, 'message': '查询中…'}

    def show_item(self, root: Path, item_id: str) -> dict:
        with self._lock:
            self._require_installation(root)
            state = self.status(root)
            if not state['connected'] or not state['ready']:
                raise RuntimeError('请先连接当前存档。')
            if item_id:
                item = next((item for item in state.get('items', {}).get('results', [])
                             if item['id'] == item_id), None)
                if not item or not item['remainingCount']:
                    raise ValueError('没有未取得位置')
            control = read_control(root)
            control['settings'].update(mapItemID=item_id, mapTarget='')
            control['revision'] = uuid.uuid4().hex
            atomic_json(control_directory(root) / 'control.json', control)
            return {'message': f'已选择：{item["name"]}' if item_id else '已取消物品显示'}

    def upgrade(self, root: Path) -> dict:
        with self._lock:
            self._require_installation(root)
            state = self.status(root)
            if not state['connected'] or not state['ready']:
                raise RuntimeError('请先连接游戏存档')
            control = read_control(root)
            request_id = uuid.uuid4().hex
            control['upgradeRequest'] = {'protocol': PROTOCOL, 'id': request_id,
                                         'action': 'upgradeAllWeapons', 'session': state['session'],
                                         'issuedAt': int(time.time() * 1000)}
            atomic_json(control_directory(root) / 'control.json', control)
            return {'requestId': request_id, 'message': '升级中…'}
