import binascii
import importlib.util
import pathlib
import sys
import types
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
SEND_UDP_TEST = (
    REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "send_udp_crypto_test.py"
)
TOOLS_DIR = SEND_UDP_TEST.parent


def _load_send_udp_module():
    module_name = "shadow_send_udp_crypto_test"
    if str(TOOLS_DIR) not in sys.path:
        sys.path.insert(0, str(TOOLS_DIR))
    spec = importlib.util.spec_from_file_location(module_name, SEND_UDP_TEST)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class _FakeSocket:
    def __init__(self, replies):
        self._replies = list(replies)
        self.timeout_history = []
        self.blocking_history = []

    def gettimeout(self):
        return 3.0

    def settimeout(self, value):
        self.timeout_history.append(value)

    def setblocking(self, value):
        self.blocking_history.append(value)

    def recvfrom(self, _size):
        if self._replies:
            return self._replies.pop(0)
        raise BlockingIOError()


class TestSendUdpCryptoTestBehavior(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = _load_send_udp_module()

    def test_resolve_expected_reply_prefers_binding_aware_ciphertext(self):
        payload = binascii.unhexlify(self.module.AES_DEFAULT_PAYLOAD_HEX)
        control_client = types.SimpleNamespace(binding_id=0xC4BA0C4B)
        args = types.SimpleNamespace(
            algo="aes",
            expected_reply_hex=None,
            expect_timeout=False,
            expect_any_reply=False,
            skip_control_session=False,
            user_key_hex=None,
        )

        expected, expected_mode = self.module._resolve_expected_reply(
            args, payload, control_client
        )

        self.assertEqual(expected_mode, "auto_session_reply")
        self.assertIsNone(expected)

    def test_resolve_expected_reply_honors_explicit_expected_hex(self):
        payload = binascii.unhexlify(self.module.AES_DEFAULT_PAYLOAD_HEX)
        control_client = types.SimpleNamespace(binding_id=0xC4BA0C4B)
        explicit = "00112233445566778899aabbccddeeff"
        args = types.SimpleNamespace(
            algo="aes",
            expected_reply_hex=explicit,
            expect_timeout=False,
            expect_any_reply=False,
            skip_control_session=False,
            user_key_hex=None,
        )

        expected, expected_mode = self.module._resolve_expected_reply(
            args, payload, control_client
        )

        self.assertEqual(expected_mode, "explicit")
        self.assertEqual(expected, binascii.unhexlify(explicit))

    def test_drain_socket_removes_stale_packets_before_real_attempt(self):
        fake_socket = _FakeSocket(
            [
                (b"stale-1", ("192.168.1.20", 4660)),
                (b"stale-2", ("192.168.1.20", 4660)),
            ]
        )

        drained = self.module._drain_socket(fake_socket)

        self.assertEqual(drained, 2)
        self.assertEqual(fake_socket._replies, [])
        self.assertEqual(fake_socket.timeout_history, [3.0])


if __name__ == "__main__":
    unittest.main()
