import argparse
import binascii
import json
from pathlib import Path

import ftd2xx


RAW_HEX = "02004A5858696C696E780058696C696E7820555342204361626C6500"
BASE_PAYLOAD = bytes.fromhex(RAW_HEX)


def build_user_area(total_size: int) -> bytes:
    if len(BASE_PAYLOAD) > total_size:
        raise ValueError(f"user area payload too large: {len(BASE_PAYLOAD)} > {total_size}")
    return BASE_PAYLOAD + (b"\x00" * (total_size - len(BASE_PAYLOAD)))


def decode_user_area(data: bytes) -> dict:
    fwid = int.from_bytes(data[:4], byteorder="little", signed=False) if len(data) >= 4 else 0
    rest = data[4:]
    fields = rest.split(b"\x00")
    vendor = fields[0].decode("utf-8", errors="ignore") if len(fields) > 0 else ""
    product = fields[1].decode("utf-8", errors="ignore") if len(fields) > 1 else ""
    return {
        "fwid": fwid,
        "vendor": vendor,
        "product": product,
        "hex": binascii.hexlify(data).decode(),
        "size": len(data),
    }


def normalize_for_json(value):
    if isinstance(value, bytes):
        return value.decode("ascii", errors="ignore").rstrip("\x00")
    if hasattr(value, "value"):
        return normalize_for_json(value.value)
    if isinstance(value, tuple):
        return [normalize_for_json(item) for item in value]
    if isinstance(value, list):
        return [normalize_for_json(item) for item in value]
    if isinstance(value, dict):
        return {str(key): normalize_for_json(item) for key, item in value.items()}
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def main() -> int:
    parser = argparse.ArgumentParser(description="Read or repair AX7020 FT232HL user area with a fixed Xilinx payload.")
    parser.add_argument("--session-dir", required=True, help="Directory for before/after dumps")
    parser.add_argument("--write", action="store_true", help="Write repaired user area")
    parser.add_argument("--confirm-write", action="store_true", help="Required with --write")
    args = parser.parse_args()

    session_dir = Path(args.session_dir)
    session_dir.mkdir(parents=True, exist_ok=True)

    dev_count = ftd2xx.createDeviceInfoList()
    print(f"device_count={dev_count}")
    if dev_count != 1:
        raise RuntimeError(f"Expected exactly one FTDI device, found {dev_count}")

    info = normalize_for_json(ftd2xx.getDeviceInfoDetail(0))
    print(f"device_info={json.dumps(info, ensure_ascii=False)}")
    (session_dir / "device_info.json").write_text(json.dumps(info, indent=2, ensure_ascii=False), encoding="utf-8")

    dev = ftd2xx.open(0)
    try:
        ua_size = dev.eeUASize()
        ua_before = dev.eeUARead(ua_size)

        before_info = decode_user_area(ua_before)
        print(f"user_area_before={json.dumps(before_info, ensure_ascii=False)}")

        (session_dir / "user_area_before.bin").write_bytes(ua_before)
        (session_dir / "user_area_before.json").write_text(json.dumps(before_info, indent=2), encoding="utf-8")

        if not args.write:
            return 0

        if not args.confirm_write:
            raise RuntimeError("--write requires --confirm-write")

        ua_after = build_user_area(total_size=ua_size)
        after_info = decode_user_area(ua_after)
        print(f"user_area_target={json.dumps(after_info, ensure_ascii=False)}")
        print(f"user_area_target_raw_hex={RAW_HEX}")

        dev.eeUAWrite(ua_after)
        ua_verify = dev.eeUARead(ua_size)
        verify_info = decode_user_area(ua_verify)
        print(f"user_area_after={json.dumps(verify_info, ensure_ascii=False)}")

        (session_dir / "user_area_target.bin").write_bytes(ua_after)
        (session_dir / "user_area_target.json").write_text(json.dumps(after_info, indent=2), encoding="utf-8")
        (session_dir / "user_area_after.bin").write_bytes(ua_verify)
        (session_dir / "user_area_after.json").write_text(json.dumps(verify_info, indent=2), encoding="utf-8")

        if ua_verify != ua_after:
            raise RuntimeError("User area verify mismatch after write")

        print("WRITE_OK")
        print("Power-cycle the board now, then rerun verify_ax7020_ft_prog_recovery.ps1.")
        return 0
    finally:
        dev.close()


if __name__ == "__main__":
    raise SystemExit(main())
