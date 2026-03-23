from Crypto.Cipher import AES
import binascii

plaintext = bytes.fromhex("3243F6A8885A308D313198A2E0370734")
key = bytes.fromhex("2B7E151628AED2A6ABF7158809CF4F3C")
expected = bytes.fromhex("3925841D02DC09FBDC118597196A0B32")
actual = bytes.fromhex("71CF20DF02D89DB45E7D112064C55BD8")

def word_swap(b):
    return b[12:16] + b[8:12] + b[4:8] + b[0:4]

def byte_swap(b):
    res = bytearray(16)
    for i in range(4):
        res[i*4] = b[i*4+3]
        res[i*4+1] = b[i*4+2]
        res[i*4+2] = b[i*4+1]
        res[i*4+3] = b[i*4]
    return bytes(res)

tests = []
for p in [plaintext, word_swap(plaintext), byte_swap(plaintext), byte_swap(word_swap(plaintext))]:
    for k in [key, word_swap(key), byte_swap(key), byte_swap(word_swap(key))]:
        tests.append((p, k))

for p, k in tests:
    cipher = AES.new(k, AES.MODE_ECB)
    
    # Check encrypt
    c = cipher.encrypt(p)
    if c == actual:
        print(f"ENCRYPT MATCH! K={k.hex()}, P={p.hex()}")
        exit(0)
    for transform, name in [(word_swap, "word"), (byte_swap, "byte"), (lambda x: byte_swap(word_swap(x)), "word+byte")]:
        if transform(c) == actual:
            print(f"ENCRYPT MATCH ({name} swapped out)! K={k.hex()}, P={p.hex()}")
            exit(0)
            
    # Check decrypt
    c = cipher.decrypt(p)
    if c == actual:
        print(f"DECRYPT MATCH! K={k.hex()}, P={p.hex()}")
        exit(0)
    for transform, name in [(word_swap, "word"), (byte_swap, "byte"), (lambda x: byte_swap(word_swap(x)), "word+byte")]:
        if transform(c) == actual:
            print(f"DECRYPT MATCH ({name} swapped out)! K={k.hex()}, P={p.hex()}")
            exit(0)

print("Done")
