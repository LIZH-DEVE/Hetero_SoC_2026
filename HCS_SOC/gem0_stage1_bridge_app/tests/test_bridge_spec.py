import unittest

from bridge_spec import (
    LOCAL_IP,
    LOCAL_MAC,
    extract_ethertype,
    frame_targets_stage1,
    pack_be32_words,
    unpack_be32_words,
)


class BridgeSpecTests(unittest.TestCase):
    def test_pack_be32_words_uses_wire_order(self):
        frame = bytes.fromhex("123456789abc020a350001200806")
        words = pack_be32_words(frame)
        self.assertEqual(words, [0x12345678, 0x9ABC020A, 0x35000120, 0x08060000])

    def test_unpack_be32_words_restores_original_prefix(self):
        words = [0x12345678, 0x9ABC020A, 0x35000120, 0x08060000]
        data = unpack_be32_words(words, 14)
        self.assertEqual(data, bytes.fromhex("123456789abc020a350001200806"))

    def test_arp_broadcast_for_local_ip_is_forwarded(self):
        arp = bytes.fromhex(
            "ffffffffffff"
            "123456789abc"
            "0806"
            "0001080006040001"
            "123456789abc"
            "c0a80102"
            "000000000000"
            "c0a80114"
        )
        self.assertTrue(frame_targets_stage1(arp, LOCAL_MAC, LOCAL_IP))

    def test_udp_for_local_mac_and_ip_is_forwarded(self):
        udp = bytes.fromhex(
            "020a35000120"
            "123456789abc"
            "0800"
            "4500001c1234400040110000"
            "c0a80102"
            "c0a80114"
            "1234123400080000"
        )
        self.assertTrue(frame_targets_stage1(udp, LOCAL_MAC, LOCAL_IP))

    def test_unrelated_ipv4_frame_is_ignored(self):
        other = bytes.fromhex(
            "020a35000121"
            "123456789abc"
            "0800"
            "4500001c1234400040110000"
            "c0a80102"
            "c0a80115"
            "1234123400080000"
        )
        self.assertFalse(frame_targets_stage1(other, LOCAL_MAC, LOCAL_IP))

    def test_extract_ethertype_handles_short_frame(self):
        self.assertIsNone(extract_ethertype(b"\x00" * 8))


if __name__ == "__main__":
    unittest.main()
