"""Local WebView bridge for installation, settings and explicit upgrade actions."""
from __future__ import annotations
import json
from pathlib import Path
import sys
from installation import DEFAULT_GAME, InstallationService
from runtime import RuntimeService


def resource_directory() -> Path:
    return Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parent))


class DesktopAPI:
    def __init__(self, resources: Path):
        self._resources = resources
        self._service = InstallationService(resources)
        self._window = None
        self._runtime = RuntimeService()

    def initialize(self) -> dict:
        config = json.loads((self._resources / 'app.json').read_text(encoding='utf-8'))
        return {'ok': True, 'data': {**config, 'directory': DEFAULT_GAME}}

    def choose_directory(self, current_directory: str = '') -> dict:
        import webview
        try:
            selected = self._window.create_file_dialog(webview.FileDialog.FOLDER,
                                                       directory=current_directory or '')
            return {'ok': True, 'data': {'directory': str(selected[0]) if selected else None}}
        except Exception as error:
            return {'ok': False, 'error': str(error)}

    def inspect(self, directory: str) -> dict:
        return self._call(self._service.inspect, directory)

    def install(self, directory: str, settings: dict) -> dict:
        return self._call(self._service.install, directory, settings)

    def uninstall(self, directory: str) -> dict:
        return self._call(self._service.uninstall, directory)

    def runtime_status(self, directory: str) -> dict:
        return self._call(self._runtime_call, self._runtime.status, directory)

    def apply_settings(self, directory: str, settings: dict) -> dict:
        return self._call(self._runtime_call, self._runtime.save_settings, directory, settings)

    def upgrade_weapons(self, directory: str) -> dict:
        return self._call(self._runtime_call, self._runtime.upgrade, directory)

    def fragment_settings(self, directory: str, enabled: bool) -> dict:
        return self._call(self._runtime_call, self._runtime.fragments, directory, enabled)

    def search_items(self, directory: str, query: str) -> dict:
        return self._call(self._runtime_call, self._runtime.search_items, directory, query)

    def show_item(self, directory: str, item_id: str) -> dict:
        return self._call(self._runtime_call, self._runtime.show_item, directory, item_id)

    def _runtime_call(self, action, directory, *arguments):
        root = self._service._game_root(directory)
        return action(root, *arguments)

    @staticmethod
    def _call(action, *arguments) -> dict:
        try:
            return {'ok': True, 'data': action(*arguments)}
        except Exception as error:
            return {'ok': False, 'error': str(error)}


def main() -> None:
    import webview
    resources = resource_directory()
    config = json.loads((resources / 'app.json').read_text(encoding='utf-8'))
    api = DesktopAPI(resources)
    api._window = webview.create_window(config['title'],
        url=(resources / 'frontend/index.html').as_uri(), js_api=api,
        width=820, height=690, min_size=(580, 540), background_color='#f3f5f9')
    webview.start(gui='edgechromium', http_server=False)
