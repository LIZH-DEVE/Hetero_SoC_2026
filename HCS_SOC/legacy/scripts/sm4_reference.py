#!/usr/bin/env python3
"""SM4 ECB reference implementation for host-side validation.

This module prefers an audited backend when one is installed. If none is
available, it falls back to a local pure-Python implementation and immediately
verifies it against the GM/T 0002-2012 standard single-block vector at import
time. The fallback must never be used unless that self-test passes.
"""

from __future__ import annotations

from dataclasses import dataclass


SM4_BLOCK_SIZE = 16

_SBOX = (
    0xD6, 0x90, 0xE9, 0xFE, 0xCC, 0xE1, 0x3D, 0xB7, 0x16, 0xB6, 0x14, 0xC2, 0x28, 0xFB, 0x2C, 0x05,
    0x2B, 0x67, 0x9A, 0x76, 0x2A, 0xBE, 0x04, 0xC3, 0xAA, 0x44, 0x13, 0x26, 0x49, 0x86, 0x06, 0x99,
    0x9C, 0x42, 0x50, 0xF4, 0x91, 0xEF, 0x98, 0x7A, 0x33, 0x54, 0x0B, 0x43, 0xED, 0xCF, 0xAC, 0x62,
    0xE4, 0xB3, 0x1C, 0xA9, 0xC9, 0x08, 0xE8, 0x95, 0x80, 0xDF, 0x94, 0xFA, 0x75, 0x8F, 0x3F, 0xA6,
    0x47, 0x07, 0xA7, 0xFC, 0xF3, 0x73, 0x17, 0xBA, 0x83, 0x59, 0x3C, 0x19, 0xE6, 0x85, 0x4F, 0xA8,
    0x68, 0x6B, 0x81, 0xB2, 0x71, 0x64, 0xDA, 0x8B, 0xF8, 0xEB, 0x0F, 0x4B, 0x70, 0x56, 0x9D, 0x35,
    0x1E, 0x24, 0x0E, 0x5E, 0x63, 0x58, 0xD1, 0xA2, 0x25, 0x22, 0x7C, 0x3B, 0x01, 0x21, 0x78, 0x87,
    0xD4, 0x00, 0x46, 0x57, 0x9F, 0xD3, 0x27, 0x52, 0x4C, 0x36, 0x02, 0xE7, 0xA0, 0xC4, 0xC8, 0x9E,
    0xEA, 0xBF, 0x8A, 0xD2, 0x40, 0xC7, 0x38, 0xB5, 0xA3, 0xF7, 0xF2, 0xCE, 0xF9, 0x61, 0x15, 0xA1,
    0xE0, 0xAE, 0x5D, 0xA4, 0x9B, 0x34, 0x1A, 0x55, 0xAD, 0x93, 0x32, 0x30, 0xF5, 0x8C, 0xB1, 0xE3,
    0x1D, 0xF6, 0xE2, 0x2E, 0x82, 0x66, 0xCA, 0x60, 0xC0, 0x29, 0x23, 0xAB, 0x0D, 0x53, 0x4E, 0x6F,
    0xD5, 0xDB, 0x37, 0x45, 0xDE, 0xFD, 0x8E, 0x2F, 0x03, 0xFF, 0x6A, 0x72, 0x6D, 0x6C, 0x5B, 0x51,
    0x8D, 0x1B, 0xAF, 0x92, 0xBB, 0xDD, 0xBC, 0x7F, 0x11, 0xD9, 0x5C, 0x41, 0x1F, 0x10, 0x5A, 0xD8,
    0x0A, 0xC1, 0x31, 0x88, 0xA5, 0xCD, 0x7B, 0xBD, 0x2D, 0x74, 0xD0, 0x12, 0xB8, 0xE5, 0xB4, 0xB0,
    0x89, 0x69, 0x97, 0x4A, 0x0C, 0x96, 0x77, 0x7E, 0x65, 0xB9, 0xF1, 0x09, 0xC5, 0x6E, 0xC6, 0x84,
    0x18, 0xF0, 0x7D, 0xEC, 0x3A, 0xDC, 0x4D, 0x20, 0x79, 0xEE, 0x5F, 0x3E, 0xD7, 0xCB, 0x39, 0x48,
)

_FK = (0xA3B1BAC6, 0x56AA3350, 0x677D9197, 0xB27022DC)

_CK = (
    0x00070E15, 0x1C232A31, 0x383F464D, 0x545B6269,
    0x70777E85, 0x8C939AA1, 0xA8AFB6BD, 0xC4CBD2D9,
    0xE0E7EEF5, 0xFC030A11, 0x181F262D, 0x343B4249,
    0x50575E65, 0x6C737A81, 0x888F969D, 0xA4ABB2B9,
    0xC0C7CED5, 0xDCE3EAF1, 0xF8FF060D, 0x141B2229,
    0x30373E45, 0x4C535A61, 0x686F767D, 0x848B9299,
    0xA0A7AEB5, 0xBCC3CAD1, 0xD8DFE6ED, 0xF4FB0209,
    0x10171E25, 0x2C333A41, 0x484F565D, 0x646B7279,
)

_STANDARD_KEY = bytes.fromhex("0123456789abcdeffedcba9876543210")
_STANDARD_PLAINTEXT = bytes.fromhex("0123456789abcdeffedcba9876543210")
_STANDARD_CIPHERTEXT = bytes.fromhex("681edf34d206965e86b3e94f536e4246")


def _rotl32(value: int, shift: int) -> int:
    value &= 0xFFFFFFFF
    return ((value << shift) | (value >> (32 - shift))) & 0xFFFFFFFF


def _tau(value: int) -> int:
    return (
        (_SBOX[(value >> 24) & 0xFF] << 24)
        | (_SBOX[(value >> 16) & 0xFF] << 16)
        | (_SBOX[(value >> 8) & 0xFF] << 8)
        | _SBOX[value & 0xFF]
    )


def _linear(value: int) -> int:
    return value ^ _rotl32(value, 2) ^ _rotl32(value, 10) ^ _rotl32(value, 18) ^ _rotl32(value, 24)


def _linear_key(value: int) -> int:
    return value ^ _rotl32(value, 13) ^ _rotl32(value, 23)


def _t(value: int) -> int:
    return _linear(_tau(value))


def _t_key(value: int) -> int:
    return _linear_key(_tau(value))


def _bytes_to_words(block: bytes) -> list[int]:
    return [int.from_bytes(block[i:i + 4], "big") for i in range(0, len(block), 4)]


def _words_to_bytes(words: list[int]) -> bytes:
    return b"".join((word & 0xFFFFFFFF).to_bytes(4, "big") for word in words)


def _expand_round_keys(key: bytes) -> list[int]:
    if len(key) != SM4_BLOCK_SIZE:
        raise ValueError("SM4 key must be exactly 16 bytes")
    mk = _bytes_to_words(key)
    k = [mk[i] ^ _FK[i] for i in range(4)]
    rk: list[int] = []
    for idx in range(32):
        next_word = k[idx] ^ _t_key(k[idx + 1] ^ k[idx + 2] ^ k[idx + 3] ^ _CK[idx])
        k.append(next_word & 0xFFFFFFFF)
        rk.append(k[idx + 4])
    return rk


def _encrypt_block_pure_python(key: bytes, block: bytes) -> bytes:
    if len(block) != SM4_BLOCK_SIZE:
        raise ValueError("SM4 block must be exactly 16 bytes")
    rk = _expand_round_keys(key)
    x = _bytes_to_words(block)
    for idx in range(32):
        x.append((x[idx] ^ _t(x[idx + 1] ^ x[idx + 2] ^ x[idx + 3] ^ rk[idx])) & 0xFFFFFFFF)
    return _words_to_bytes([x[35], x[34], x[33], x[32]])


@dataclass(frozen=True)
class _Backend:
    name: str
    encrypt_block: callable


def _load_backend() -> _Backend:
    try:
        from gmssl.sm4 import CryptSM4, SM4_ENCRYPT  # type: ignore

        def _encrypt_block_gmssl(key: bytes, block: bytes) -> bytes:
            if len(key) != SM4_BLOCK_SIZE or len(block) != SM4_BLOCK_SIZE:
                raise ValueError("SM4 key and block must be exactly 16 bytes")
            cipher = CryptSM4()
            cipher.set_key(key, SM4_ENCRYPT)
            return bytes(cipher.crypt_ecb(block))

        return _Backend(name="gmssl", encrypt_block=_encrypt_block_gmssl)
    except Exception:
        return _Backend(name="python-reference", encrypt_block=_encrypt_block_pure_python)


_BACKEND = _load_backend()


def backend_name() -> str:
    return _BACKEND.name


def encrypt_block(key: bytes, block: bytes) -> bytes:
    return _BACKEND.encrypt_block(key, block)


def ecb_encrypt(key: bytes, payload: bytes) -> bytes:
    if len(payload) == 0 or (len(payload) % SM4_BLOCK_SIZE) != 0:
        raise ValueError("SM4 payload must be non-empty and 16-byte aligned")
    return b"".join(encrypt_block(key, payload[idx:idx + SM4_BLOCK_SIZE]) for idx in range(0, len(payload), SM4_BLOCK_SIZE))


def self_test() -> None:
    observed = encrypt_block(_STANDARD_KEY, _STANDARD_PLAINTEXT)
    if observed != _STANDARD_CIPHERTEXT:
        raise RuntimeError(
            f"SM4 backend '{backend_name()}' failed standard vector: "
            f"expected {_STANDARD_CIPHERTEXT.hex()} got {observed.hex()}"
        )


self_test()
