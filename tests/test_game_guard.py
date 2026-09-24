import importlib.util
import pathlib
import subprocess
import sys
import unittest


ROOT = pathlib.Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location("llama_game_guard", ROOT / "scripts/llama-game-guard.py")
guard = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = guard
SPEC.loader.exec_module(guard)


MONITORS = [{"x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1}]


def game(**overrides):
    value = {
        "class": "steam_app_2406770",
        "title": "Bodycam",
        "pid": 1234,
        "fullscreen": 1,
        "at": [0, 0],
        "size": [2560, 1440],
    }
    value.update(overrides)
    return value


class GuardTests(unittest.TestCase):
    def test_fullscreen_known_game_is_detected(self):
        result = guard.choose_game([game()], MONITORS, lambda pid: "Bodycam.exe")
        self.assertTrue(result.active)

    def test_windowed_game_is_not_detected(self):
        result = guard.choose_game([game(fullscreen=0, size=[1280, 720])], MONITORS, lambda pid: "Bodycam.exe")
        self.assertFalse(result.active)

    def test_hyprland_fullscreen_client_state_two_is_detected(self):
        monitors = [{"x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.25}]
        result = guard.choose_game([game(fullscreen=2, size=[2048, 1152])], monitors, lambda pid: "Bodycam-Win64-Shipping.exe")
        self.assertTrue(result.active)

    def test_fullscreen_desktop_app_is_not_detected(self):
        result = guard.choose_game([game(**{"class": "brave-browser", "title": "Bodycam trailer"})], MONITORS, lambda pid: "")
        self.assertFalse(result.active)

    def test_maximized_unrelated_window_is_not_detected(self):
        result = guard.choose_game([game(**{"class": "orca", "title": "Orca"})], MONITORS, lambda pid: "")
        self.assertFalse(result.active)

    def test_geometry_allows_reserved_bar(self):
        result = guard.choose_game([game(size=[2560, 1414])], MONITORS, lambda pid: "game.exe")
        self.assertTrue(result.active)

    def test_service_order_stops_dependencies_before_server(self):
        calls = []

        def runner(command, **kwargs):
            calls.append(command[-1])
            return subprocess.CompletedProcess(command, 0)

        controller = guard.ServiceController(runner=runner)
        controller.pause()
        self.assertEqual(calls, list(controller.services))
        calls.clear()
        controller.resume()
        self.assertEqual(calls, list(reversed(controller.services)))


if __name__ == "__main__":
    unittest.main()
