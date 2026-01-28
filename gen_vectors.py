# scripts/gen_vectors.py
import binascii
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

# ==============================================================================
# 必须与 SystemVerilog Testbench 保持一致的参数
# ==============================================================================
# AES-128 Key
KEY_HEX = "2b7e151628aed2a6abf7158809cf4f3c"

# Initialization Vector (IV)
IV_HEX  = "000102030405060708090a0b0c0d0e0f"

# Input Data (64 Bytes = 4 Blocks)
# 这是 Day 7 使用的 "6bc1..." 重复 4 次
PLAINTEXT_BLOCK = "6bc1bee22e409f96e93d7e117393172a"
PLAINTEXT_HEX   = PLAINTEXT_BLOCK * 4 

def run_aes_golden():
    print("-" * 60)
    print("Generating AES-128-CBC Golden Vectors...")
    print("-" * 60)

    try:
        # 1. Hex String -> Bytes
        key_bytes = binascii.unhexlify(KEY_HEX)
        iv_bytes  = binascii.unhexlify(IV_HEX)
        txt_bytes = binascii.unhexlify(PLAINTEXT_HEX)

        # 2. AES-CBC Encryption
        cipher = AES.new(key_bytes, AES.MODE_CBC, iv_bytes)
        ciphertext_bytes = cipher.encrypt(txt_bytes)
        
        # 3. Bytes -> Hex String
        ciphertext_hex = binascii.hexlify(ciphertext_bytes).decode('utf-8')

        # 4. Output for Testbench
        print(f"[GOLDEN OUTPUT]")
        print(f"AES Ciphertext : {ciphertext_hex}")
        print("-" * 60)
        
    except Exception as e:
        print(f"Error: {e}")
        print("Tip: Run 'pip install pycryptodome' first.")

if __name__ == "__main__":
    run_aes_golden()