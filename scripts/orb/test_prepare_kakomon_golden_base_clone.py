#!/usr/bin/env python3
"""Tests for the Orb Golden Base clone network-ready gate."""

import pathlib
import subprocess
import unittest


SCRIPT_PATH = pathlib.Path(__file__).with_name(
    "prepare-kakomon-golden-base-clone.sh"
)
FUNCTION_NAME = "wait_for_clone_ipv4_network"


def load_script() -> str:
    return SCRIPT_PATH.read_text(encoding="utf-8")


def extract_function(script: str) -> str:
    start = script.index(f"{FUNCTION_NAME}() {{")
    end = script.index("\n}\n", start) + len("\n}\n")
    return script[start:end]


def run_function_harness(body: str) -> subprocess.CompletedProcess[str]:
    script = load_script()
    harness = f"set -euo pipefail\n{extract_function(script)}\n{body}"
    return subprocess.run(
        ["bash", "-c", harness],
        check=False,
        capture_output=True,
        text=True,
    )


class PrepareKakomonGoldenBaseCloneTest(unittest.TestCase):
    def test_waits_for_address_on_default_route_interface(self) -> None:
        result = run_function_harness(
            r'''
ip() {
  case "$*" in
    "-4 route show default")
      printf 'default via 192.0.2.1 dev ens3 proto dhcp\n'
      ;;
    "-4 -o address show scope global")
      printf '2: ens4 inet 198.51.100.10/24 scope global ens4\n'
      printf '3: ens3 inet 192.0.2.10/24 scope global ens3\n'
      ;;
    *) return 1 ;;
  esac
}
sleep() { :; }
wait_for_clone_ipv4_network
[[ "${clone_ipv4_address}" == 192.0.2.10 ]]
'''
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("network is ready", result.stdout)

    def test_fails_after_bounded_wait(self) -> None:
        result = run_function_harness(
            r'''
ip() { return 0; }
sleep() { :; }
if wait_for_clone_ipv4_network; then
  exit 97
fi
'''
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "IPv4 address or default route was not ready within 120 seconds",
            result.stderr,
        )

    def test_wait_precedes_service_restoration_and_is_recorded(self) -> None:
        script = load_script()
        function_end = script.index("\n}\n", script.index(f"{FUNCTION_NAME}() {{"))
        wait_call = script.index(f"\n{FUNCTION_NAME}\n", function_end)
        service_restoration = script.index(
            'IFS=, read -r -a target_services <<<"${TARGET_SERVICES}"',
            wait_call,
        )

        self.assertLess(wait_call, service_restoration)
        self.assertIn("IPV4_NETWORK_VERIFIED=true", script)


if __name__ == "__main__":
    unittest.main()
