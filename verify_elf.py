import sys
import re

def verify_elf(file_path):
    print(f"Scanning ELF: {file_path}")
    try:
        with open(file_path, 'rb') as f:
            content = f.read()
            
        # Search for ASCII patterns
        patterns = [
            b"Hardware Version",
            b"0xACE",
            b"Fingerprint"
        ]
        
        found_any = False
        for p in patterns:
            if p in content:
                print(f"[MATCH] Found pattern: {p.decode()}")
                found_any = True
            else:
                print(f"[MISS] Pattern NOT found: {p.decode()}")
        
        if found_any:
            print("\n[RESULT] ELF contains updated fingerprint logic. Ready to run.")
        else:
            print("\n[RESULT] ELF is OUTDATED. Please Clean and Rebuild in Vitis.")
            
    except Exception as e:
        print(f"[ERROR] Failed to read ELF: {e}")

if __name__ == "__main__":
    path = "D:/FPGAhanjia/Hetero_SoC_2026_3/Hetero_SoC_2026/HCS_SOC/crypto_test_app/build/crypto_test_app.elf"
    verify_elf(path)
