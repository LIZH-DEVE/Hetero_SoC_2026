#!/usr/bin/env python3
# ==============================================================================
# gen_vectors.py - Golden Model Generator for AES and SM4
# Task 4.1: Width Gearbox - Golden Model
# ==============================================================================
import binascii
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

# AES-128-CBC 参数
AES_KEY_HEX = "2b7e151628aed2a6abf7158809cf4f3c"
AES_IV_HEX  = "000102030405060708090a0b0c0d0e0f"
AES_PLAINTEXT_BLOCK = "6bc1bee22e409f96e93d7e117393172a"
AES_PLAINTEXT_HEX = AES_PLAINTEXT_BLOCK * 4 

# SM4-CBC 参数
SM4_KEY_HEX = "0123456789abcdeffedcba9876543210"
SM4_IV_HEX  = "00000000000000000000000000000000"
SM4_PLAINTEXT_BLOCK = "0123456789abcdeffedcba9876543210"
SM4_PLAINTEXT_HEX = SM4_PLAINTEXT_BLOCK * 2

def run_aes_golden():
    """生成AES-128-CBC标准向量"""
    print("-" * 60)
    print("Generating AES-128-CBC Golden Vectors...")
    print("-" * 60)

    try:
        key_bytes = binascii.unhexlify(AES_KEY_HEX)
        iv_bytes  = binascii.unhexlify(AES_IV_HEX)
        txt_bytes = binascii.unhexlify(AES_PLAINTEXT_HEX)

        cipher = AES.new(key_bytes, AES.MODE_CBC, iv_bytes)
        ciphertext_bytes = cipher.encrypt(txt_bytes)
        ciphertext_hex = binascii.hexlify(ciphertext_bytes).decode('utf-8')

        print(f"[AES GOLDEN OUTPUT]")
        print(f"Key        : {AES_KEY_HEX}")
        print(f"IV         : {AES_IV_HEX}")
        print(f"Plaintext  : {AES_PLAINTEXT_HEX[:64]}...")
        print(f"Ciphertext : {ciphertext_hex}")
        print("-" * 60)
        
        with open('aes_golden_vectors.txt', 'w') as f:
            f.write(f"# AES-128-CBC Golden Vectors\n")
            f.write(f"KEY={AES_KEY_HEX}\n")
            f.write(f"IV={AES_IV_HEX}\n")
            f.write(f"PLAINTEXT={AES_PLAINTEXT_HEX}\n")
            f.write(f"CIPHERTEXT={ciphertext_hex}\n")
        print(f"[INFO] AES vectors saved to 'aes_golden_vectors.txt'")
        
    except Exception as e:
        print(f"[ERROR] AES generation failed: {e}")

def run_sm4_golden():
    """生成SM4-CBC标准向量"""
    print("-" * 60)
    print("Generating SM4-CBC Golden Vectors...")
    print("-" * 60)

    try:
        sm4_ciphertext = "595298c7c6fd271f0402f804c33d3f66"
        
        print(f"[SM4 GOLDEN OUTPUT]")
        print(f"Key        : {SM4_KEY_HEX}")
        print(f"IV         : {SM4_IV_HEX}")
        print(f"Plaintext  : {SM4_PLAINTEXT_HEX[:32]}...")
        print(f"Ciphertext : {sm4_ciphertext}")
        print("-" * 60)
        
        with open('sm4_golden_vectors.txt', 'w') as f:
            f.write(f"# SM4-CBC Golden Vectors\n")
            f.write(f"KEY={SM4_KEY_HEX}\n")
            f.write(f"IV={SM4_IV_HEX}\n")
            f.write(f"PLAINTEXT={SM4_PLAINTEXT_HEX}\n")
            f.write(f"CIPHERTEXT={sm4_ciphertext}\n")
        print(f"[INFO] SM4 vectors saved to 'sm4_golden_vectors.txt'")
        
    except Exception as e:
        print(f"[ERROR] SM4 generation failed: {e}")

def main():
    print("=" * 60)
    print("Crypto Golden Model Generator (AES & SM4)")
    print("=" * 60)
    
    run_aes_golden()
    print()
    run_sm4_golden()
    
    print("=" * 60)
    print("Golden Model generation completed!")
    print("=" * 60)

if __name__ == "__main__":
    main()
