import sys
import base64

def aes_ecb_encrypt_decrypt_test():
    try:
        from Crypto.Cipher import AES
    except ImportError:
        try:
            from Cryptodome.Cipher import AES
        except ImportError:
            print("No pycryptodome installed.")
            return
            
    key = bytes.fromhex("2B7E151628AED2A6ABF7158809CF4F3C")
    # pattern_word logic for Block 1 (idx 4,5,6,7) with seed 0x101
    def pattern_word(seed, idx):
        x = 0x1f123bb5 ^ ((seed * 0x9e3779b9) & 0xffffffff) ^ ((idx * 0x85ebca6b) & 0xffffffff)
        x = (((x & 0xffff) << 16) | ((x >> 16) & 0xffff)) ^ ((idx & 0xffff) << 16 | (seed & 0xffff))
        return x
        
    block0 = b''.join(pattern_word(0x101, i).to_bytes(4, 'little') for i in range(4))
    block1 = b''.join(pattern_word(0x101, i).to_bytes(4, 'little') for i in range(4, 8))
    
    cipher = AES.new(key, AES.MODE_ECB)
    ct0 = cipher.encrypt(block0)
    ct1 = cipher.encrypt(block1)
    
    print("Block 0 Plaintext:", block0.hex())
    print("Block 0 Cipher:", ct0.hex())
    print("Block 1 Plaintext:", block1.hex())
    print("Block 1 Cipher:", ct1.hex())

    # Try decrypting 0ee4b41a with ZERO key
    zero_key = bytes([0]*16)
    c0 = AES.new(zero_key, AES.MODE_ECB)
    ct_target = bytes.fromhex("0ee4b41a639f30ca6b5138872d4356f9")
    print("Zero key Decrypt:", c0.decrypt(ct_target).hex())

aes_ecb_encrypt_decrypt_test()
