import importlib.util
import pathlib
import struct
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROL_PY = REPO_ROOT / "HCS_SOC" / "udp_crypto_control.py"
HANDOFF_CONTROL_PY = (
    REPO_ROOT / "handoff" / "robeieda_porting_pack" / "tools" / "udp_crypto_control.py"
)


def _load_module(path: pathlib.Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class TestUdpCryptoControlStatusDecode(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.control_module = _load_module(CONTROL_PY, "shadow_udp_crypto_control")
        cls.handoff_module = _load_module(
            HANDOFF_CONTROL_PY, "shadow_udp_crypto_control_handoff"
        )

    def test_hcs_soc_status_decode_unpacks_reason_bitfields(self):
        status_payload = self.control_module.STATUS_STRUCT.pack(
            0xC4BA0C4B,
            1,
            0x00004303,
            0,
            2,
            1,
            7,
            0,
            0,
            3,
            0,
            1,
            0,
            0,
        )

        decoded = self.control_module.decode_status_payload(status_payload)

        self.assertEqual(decoded["authorized_mask_raw"], 0x00004303)
        self.assertEqual(decoded["authorized_mask"], 0x03)
        self.assertEqual(decoded["last_drop_reason"], 0x3)
        self.assertEqual(decoded["last_lock_reason"], 0x4)

    def test_hcs_soc_status_decode_unpacks_shadow_mirror_seen_flags(self):
        status_payload = self.control_module.STATUS_STRUCT.pack(
            0xC4BA0C4B,
            1,
            0x0005432A,
            0,
            2,
            1,
            7,
            0,
            0,
            3,
            0,
            1,
            0,
            0,
        )

        decoded = self.control_module.decode_status_payload(status_payload)

        self.assertEqual(decoded["authorized_mask_raw"], 0x0005432A)
        self.assertEqual(decoded["authorized_mask"], 0x2A)
        self.assertEqual(decoded["last_drop_reason"], 0x3)
        self.assertEqual(decoded["last_lock_reason"], 0x4)
        self.assertEqual(decoded["acl_hit_seen"], 1)
        self.assertEqual(decoded["replay_seen"], 0)
        self.assertEqual(decoded["timeout_seen"], 1)
        self.assertEqual(decoded["reauth_seen"], 0)

    def test_handoff_status_decode_unpacks_reason_bitfields(self):
        status_payload = self.handoff_module.STATUS_STRUCT.pack(
            0xC4BA0C4B,
            1,
            0x00002101,
            1,
            2,
            1,
            7,
            0,
            1,
            0,
            0,
            1,
            0,
            0,
        )

        decoded = self.handoff_module.decode_status_payload(status_payload)

        self.assertEqual(decoded["authorized_mask_raw"], 0x00002101)
        self.assertEqual(decoded["authorized_mask"], 0x01)
        self.assertEqual(decoded["last_drop_reason"], 0x1)
        self.assertEqual(decoded["last_lock_reason"], 0x2)

    def test_handoff_status_decode_unpacks_shadow_mirror_seen_flags(self):
        status_payload = self.handoff_module.STATUS_STRUCT.pack(
            0xC4BA0C4B,
            1,
            0x000A2101,
            1,
            2,
            1,
            7,
            0,
            1,
            0,
            0,
            1,
            0,
            0,
        )

        decoded = self.handoff_module.decode_status_payload(status_payload)

        self.assertEqual(decoded["authorized_mask_raw"], 0x000A2101)
        self.assertEqual(decoded["authorized_mask"], 0x01)
        self.assertEqual(decoded["last_drop_reason"], 0x1)
        self.assertEqual(decoded["last_lock_reason"], 0x2)
        self.assertEqual(decoded["acl_hit_seen"], 0)
        self.assertEqual(decoded["replay_seen"], 1)
        self.assertEqual(decoded["timeout_seen"], 0)
        self.assertEqual(decoded["reauth_seen"], 1)


if __name__ == "__main__":
    unittest.main()
