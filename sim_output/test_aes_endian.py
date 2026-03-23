import sys
from itertools import permutations

def full_byte_rev(hex_str):
    return bytes.fromhex(hex_str)[::-1].hex()

def word_rev(hex_str):
    b = bytes.fromhex(hex_str)
    return b[12:16] + b[8:12] + b[4:8] + b[0:4]

def word_and_byte_rev(hex_str):
    return full_byte_rev(word_rev(hex_str).hex())

def all_transforms(hex_str):
    return [
        hex_str,
        full_byte_rev(hex_str),
        word_rev(hex_str).hex(),
        full_byte_rev(word_rev(hex_str).hex())
    ]

def test_endianness():
    try:
        from Crypto.Cipher import AES
    except:
        from Cryptodome.Cipher import AES
            
    key_hex = "2B7E151628AED2A6ABF7158809CF4F3C"
    
    def pattern_word(seed, idx):
        x = 0x1f123bb5 ^ ((seed * 0x9e3779b9) & 0xffffffff) ^ ((idx * 0x85ebca6b) & 0xffffffff)
        x = (((x & 0xffff) << 16) | ((x >> 16) & 0xffff)) ^ ((idx & 0xffff) << 16 | (seed & 0xffff))
        return x
        
    block0_hex = "".join([f"{pattern_word(0x101, i):08x}" for i in range(4)])
    
    keys = all_transforms(key_hex)
    pt0s = all_transforms(block0_hex)
    
    for kidx, k in enumerate(keys):
        c = AES.new(bytes.fromhex(k), AES.MODE_ECB)
        for pidx, p in enumerate(pt0s):
            ct = c.encrypt(bytes.fromhex(p)).hex()
            cts = all_transforms(ct)
            for cidx, final_ct in enumerate(cts):
                if final_ct == "9518ad73f0fc38aa204f413aabe25498":
                    print(f"MATCH! key_transform={kidx}, pt_transform={pidx}, out_transform={cidx}")
                    return

test_endianness()
