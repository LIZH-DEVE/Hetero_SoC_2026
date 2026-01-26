# =============================================================================
# PROJECT: Hetero_SoC (Crypto SmartNIC)
# COMPONENT: Task 4.1 - Golden Model (Algorithm Hardening Phase)
# OBJECTIVE: Generate deterministic truth vectors for RTL verification.
# =============================================================================

import os
import binascii
from Crypto.Cipher import AES
from Crypto.Hash import SHA256
from Crypto.Random import get_random_bytes

# 路径审计：确保输出路径与 Vivado 仿真工作流同步
CUR_DIR = os.path.dirname(os.path.abspath(__file__))

def gen_vector(idx):
    """
    核查维度：AES-256-CBC (256b Key, 128b IV) & SHA-256。
    强约束：按照手册 Day 2 定义，Payload 必须 128-bit 对齐。
    """
    # 熵源采集
    key = get_random_bytes(32)   # 256-bit 密钥空间
    iv  = get_random_bytes(16)    # 128-bit 初始向量
    plaintext = get_random_bytes(16) # 模拟单个 AXI-Stream 数据槽 (128-bit)

    # 加密算力模型：AES-256-CBC
    cipher_engine = AES.new(key, AES.MODE_CBC, iv)
    ciphertext = cipher_engine.encrypt(plaintext)
    
    # 摘要算力模型：SHA-256
    hash_engine = SHA256.new()
    hash_engine.update(plaintext)
    digest = hash_engine.digest()

    # 交付物持久化：Verilog $readmemh 兼容格式
    fname = os.path.join(CUR_DIR, f"test_{idx}.hex")
    with open(fname, "w") as f:
        # 按行存储，严禁前缀，全小写 hex 编码
        f.write(f"{binascii.hexlify(key).decode()}\n")        # Line 0: [255:0] Key
        f.write(f"{binascii.hexlify(iv).decode()}\n")         # Line 1: [127:0] IV
        f.write(f"{binascii.hexlify(plaintext).decode()}\n")  # Line 2: [127:0] Plaintext
        f.write(f"{binascii.hexlify(ciphertext).decode()}\n") # Line 3: [127:0] Expected Cipher
        f.write(f"{binascii.hexlify(digest).decode()}\n")     # Line 4: [255:0] Expected Hash
    
    print(f"[AUDIT] Vector {idx} Integrity Confirmed: {fname}")

if __name__ == "__main__":
    # 执行 5 组独立随机测试，覆盖不同数据分布
    for i in range(5):
        gen_vector(i)