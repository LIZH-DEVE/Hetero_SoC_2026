import unittest

import send_udp_crypto_test as sender
import udp_crypto_control as ctrl


class ControlProtocolTests(unittest.TestCase):
    def test_roundtrip_control_message(self) -> None:
        payload = bytes.fromhex("00112233445566778899aabbccddeeff")
        packet = ctrl.pack_control_message(
            msg_type=ctrl.MSG_SET_KEY,
            session_id=0x10203040,
            seq_id=7,
            flags=ctrl.ALGO_FLAG_AES | ctrl.ALGO_FLAG_SM4,
            payload=payload,
            binding_id=0x41583702,
        )

        decoded = ctrl.unpack_control_message(packet)

        self.assertEqual(decoded.msg_type, ctrl.MSG_SET_KEY)
        self.assertEqual(decoded.session_id, 0x10203040)
        self.assertEqual(decoded.seq_id, 7)
        self.assertEqual(decoded.flags, ctrl.ALGO_FLAG_AES | ctrl.ALGO_FLAG_SM4)
        self.assertEqual(decoded.payload, payload)
        self.assertEqual(decoded.status_code, ctrl.STATUS_OK)

    def test_effective_key_changes_with_algo(self) -> None:
        user_key = bytes.fromhex("00112233445566778899aabbccddeeff")

        aes_key = ctrl.derive_effective_key(user_key, 0x41583702, ctrl.ALGO_AES)
        sm4_key = ctrl.derive_effective_key(user_key, 0x41583702, ctrl.ALGO_SM4)

        self.assertEqual(len(aes_key), 16)
        self.assertEqual(len(sm4_key), 16)
        self.assertNotEqual(aes_key, sm4_key)

    def test_auth_tag_changes_with_payload(self) -> None:
        tag_a = ctrl.compute_auth_tag(
            msg_type=ctrl.MSG_SET_KEY,
            session_id=1,
            seq_id=2,
            flags=ctrl.ALGO_FLAG_AES,
            status_code=ctrl.STATUS_OK,
            payload=b"A" * 16,
            binding_id=0x41583702,
        )
        tag_b = ctrl.compute_auth_tag(
            msg_type=ctrl.MSG_SET_KEY,
            session_id=1,
            seq_id=2,
            flags=ctrl.ALGO_FLAG_AES,
            status_code=ctrl.STATUS_OK,
            payload=b"B" * 16,
            binding_id=0x41583702,
        )

        self.assertNotEqual(tag_a, tag_b)

    def test_status_decode_includes_crypto_counters(self) -> None:
        payload = ctrl.STATUS_STRUCT.pack(
            0x41583702,
            0x01020304,
            ctrl.ALGO_FLAG_AES | ctrl.ALGO_FLAG_SM4,
            1,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
        )

        decoded = ctrl.decode_status_payload(payload)

        self.assertEqual(decoded["binding_id"], 0x41583702)
        self.assertEqual(decoded["session_id"], 0x01020304)
        self.assertEqual(decoded["crypto_timeout"], 18)
        self.assertEqual(decoded["crypto_fail"], 19)

    def test_effective_key_contract_uses_big_endian_binding_id(self) -> None:
        user_key = bytes.fromhex(ctrl.DEFAULT_AES_USER_KEY_HEX)

        derived = ctrl.derive_effective_key(user_key, 0x41583702, ctrl.ALGO_AES)

        self.assertEqual(derived.hex(), "f79bcb65cdb7b7a3f497dea53c693557")

    def test_aes_binding_aware_expected_matches_observed_board_reply(self) -> None:
        payload = bytes.fromhex(sender.AES_DEFAULT_PAYLOAD_HEX)
        user_key = bytes.fromhex(ctrl.DEFAULT_AES_USER_KEY_HEX)
        effective_key = ctrl.derive_effective_key(user_key, 0x41583702, ctrl.ALGO_AES)

        expected = sender.expected_aes_ecb(payload, key=effective_key)

        self.assertEqual(expected.hex(), "8f823d9b4747ca31d5a64c9986747ea8")

    def test_sm4_baseline_matches_standard_vector(self) -> None:
        key = bytes.fromhex(ctrl.DEFAULT_SM4_USER_KEY_HEX)
        payload = bytes.fromhex(sender.SM4_DEFAULT_PAYLOAD_HEX)

        expected = sender.expected_sm4_ecb(payload, key=key)

        self.assertEqual(expected.hex(), sender.SM4_EXPECTED_REPLY_HEX)

    def test_sm4_binding_aware_expected_matches_observed_board_reply(self) -> None:
        payload = bytes.fromhex(sender.SM4_DEFAULT_PAYLOAD_HEX)
        user_key = bytes.fromhex(ctrl.DEFAULT_SM4_USER_KEY_HEX)
        effective_key = ctrl.derive_effective_key(user_key, 0x41583702, ctrl.ALGO_SM4)

        expected = sender.expected_sm4_ecb(payload, key=effective_key)

        self.assertEqual(expected.hex(), "aa2860c400ce76a659ab940e7866cda1")


if __name__ == "__main__":
    unittest.main()
