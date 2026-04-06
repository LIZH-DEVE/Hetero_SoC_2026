LOCAL_IP = bytes.fromhex("c0a80114")
LOCAL_MAC = bytes.fromhex("020a35000120")


def pack_be32_words(data: bytes) -> list[int]:
    words = []
    for offset in range(0, len(data), 4):
        chunk = data[offset:offset + 4]
        chunk = chunk + bytes(4 - len(chunk))
        words.append(int.from_bytes(chunk, byteorder="big"))
    return words


def unpack_be32_words(words: list[int], length: int) -> bytes:
    data = bytearray()
    for word in words:
        data.extend(word.to_bytes(4, byteorder="big"))
    return bytes(data[:length])


def extract_ethertype(frame: bytes) -> int | None:
    if len(frame) < 14:
        return None
    return int.from_bytes(frame[12:14], byteorder="big")


def is_broadcast_mac(mac: bytes) -> bool:
    return mac == b"\xff\xff\xff\xff\xff\xff"


def frame_targets_stage1(frame: bytes, local_mac: bytes, local_ip: bytes) -> bool:
    if len(frame) < 14:
        return False

    dst_mac = frame[0:6]
    ethertype = extract_ethertype(frame)
    if ethertype == 0x0806:
        if len(frame) < 42:
            return False
        arp_oper = int.from_bytes(frame[20:22], byteorder="big")
        arp_target_ip = frame[38:42]
        return is_broadcast_mac(dst_mac) and arp_oper == 1 and arp_target_ip == local_ip

    if ethertype == 0x0800:
        if len(frame) < 34:
            return False
        ip_proto = frame[23]
        ip_dst = frame[30:34]
        return dst_mac == local_mac and ip_proto == 17 and ip_dst == local_ip

    return False
