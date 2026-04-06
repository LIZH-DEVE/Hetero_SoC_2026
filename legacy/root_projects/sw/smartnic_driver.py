#!/usr/bin/env python3
"""
SmartNIC Driver - Python API for Crypto SmartNIC
用于与FPGA SmartNIC通信的Python驱动

功能:
1. 配置加密参数 (算法选择: AES/SM4)
2. 发送明文数据进行加密
3. 接收加密后的密文
4. 查询状态和统计信息
"""

import socket
import struct
import time
import random
from typing import Tuple, Optional, Dict, List
from enum import Enum

# ==============================================================================
# 常量定义
# ==============================================================================

# 端口定义
CRYPTO_PORT = 0x1234    # 加密服务端口
CONFIG_PORT = 0x4321    # 配置端口
DATA_PORT = 0x5678      # 数据传输端口

# 加密算法
class CryptoAlgorithm(Enum):
    AES_128_CBC = 0
    SM4_CBC = 1

# 默认配置
DEFAULT_CONFIG = {
    'algo': CryptoAlgorithm.AES_128_CBC,
    'key': bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c'),  # AES-128 key
    'iv': bytes.fromhex('000102030405060708090a0b0c0d0e0f'),   # AES IV
    'timeout': 5.0,  # 秒
}

# ==============================================================================
# SmartNIC 驱动类
# ==============================================================================

class SmartNICDriver:
    """
    SmartNIC FPGA加速卡驱动程序
    
    使用方法:
    1. 创建驱动实例
    2. 配置加密参数 (set_config)
    3. 发送数据进行加密 (encrypt)
    4. 接收加密结果 (receive)
    5. 查询状态 (get_status)
    """
    
    def __init__(self, ip_addr: str = '192.168.1.10', 
                 fpga_port: int = 8080):
        """
        初始化SmartNIC驱动
        
        Args:
            ip_addr: SmartNIC的IP地址 (默认 192.168.1.10)
            fpga_port: FPGA的通信端口 (默认 8080)
        """
        self.ip_addr = ip_addr
        self.fpga_port = fpga_port
        self.sock = None
        self.config = DEFAULT_CONFIG.copy()
        self.packet_count = 0
        self.byte_count = 0
        
    def connect(self) -> bool:
        """
        连接到SmartNIC
        
        Returns:
            bool: 连接是否成功
        """
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.settimeout(self.config['timeout'])
            print(f"✅ 已连接到 SmartNIC ({self.ip_addr}:{self.fpga_port})")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False
    
    def disconnect(self):
        """断开与SmartNIC的连接"""
        if self.sock:
            self.sock.close()
            self.sock = None
            print("🔌 已断开与SmartNIC的连接")
    
    # =========================================================================
    # 配置接口 (CONFIG_PORT = 0x4321)
    # =========================================================================
    
    def set_config(self, 
                   algorithm: CryptoAlgorithm = CryptoAlgorithm.AES_128_CBC,
                   key: Optional[bytes] = None,
                   iv: Optional[bytes] = None) -> bool:
        """
        配置加密参数
        
        使用方法:
        >>> driver = SmartNICDriver()
        >>> driver.connect()
        >>> # 选择SM4加密
        >>> driver.set_config(algorithm=CryptoAlgorithm.SM4_CBC)
        >>> # 选择AES加密 (默认)
        >>> driver.set_config(algorithm=CryptoAlgorithm.AES_128_CBC)
        >>> # 自定义密钥
        >>> driver.set_config(key=bytes.fromhex('0123456789abcdeffedcba9876543210'))
        
        Args:
            algorithm: 加密算法 (AES_128_CBC 或 SM4_CBC)
            key: 密钥 (AES: 16字节, SM4: 16字节)
            iv: 初始化向量 (16字节)
        
        Returns:
            bool: 配置是否成功
        """
        # 选择加密算法
        if algorithm == CryptoAlgorithm.AES_128_CBC:
            print("🔐 配置加密算法: AES-128-CBC")
            default_key = bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c')
            default_iv = bytes.fromhex('000102030405060708090a0b0c0d0e0f')
        else:  # SM4_CBC
            print("🔐 配置加密算法: SM4-CBC")
            default_key = bytes.fromhex('0123456789abcdeffedcba9876543210')
            default_iv = bytes.fromhex('00000000000000000000000000000000')
        
        # 使用提供的密钥或默认值
        self.config['key'] = key if key else default_key
        self.config['iv'] = iv if iv else default_iv
        self.config['algo'] = algorithm
        
        # 构建配置包
        # 格式: Magic(4B) + seq_id(2B) + algo(1B) + key(16B) + iv(16B)
        magic = 0xDEADBEEF.to_bytes(4, 'big')
        seq_id = (random.randint(1, 65535)).to_bytes(2, 'big')
        algo_byte = bytes([algorithm.value])
        key_bytes = self.config['key']
        iv_bytes = self.config['iv']
        
        config_packet = magic + seq_id + algo_byte + key_bytes + iv_bytes
        
        # 发送配置包
        success, _ = self._send_packet(CONFIG_PORT, config_packet)
        return success
    
    def set_aes(self, 
                key: Optional[bytes] = None, 
                iv: Optional[bytes] = None) -> bool:
        """
        快捷方法: 设置AES-128-CBC加密
        
        使用方法:
        >>> driver.set_aes()  # 使用默认密钥
        >>> driver.set_aes(key=bytes.fromhex('...'), iv=bytes.fromhex('...'))
        """
        return self.set_config(
            algorithm=CryptoAlgorithm.AES_128_CBC,
            key=key,
            iv=iv
        )
    
    def set_sm4(self,
                key: Optional[bytes] = None,
                iv: Optional[bytes] = None) -> bool:
        """
        快捷方法: 设置SM4-CBC加密
        
        使用方法:
        >>> driver.set_sm4()  # 使用默认密钥
        >>> driver.set_sm4(key=bytes.fromhex('...'), iv=bytes.fromhex('...'))
        """
        return self.set_config(
            algorithm=CryptoAlgorithm.SM4_CBC,
            key=key,
            iv=iv
        )
    
    # =========================================================================
    # 数据接口 (CRYPTO_PORT = 0x1234)
    # =========================================================================
    
    def encrypt(self, plaintext: bytes) -> Optional[bytes]:
        """
        发送明文进行加密
        
        使用方法:
        >>> driver.connect()
        >>> driver.set_aes()
        >>> # 加密数据 (必须是16字节整数倍)
        >>> plaintext = b"Hello, SmartNIC!"  # 16 bytes
        >>> ciphertext = driver.encrypt(plaintext)
        >>> print(f"密文: {ciphertext.hex()}")
        
        Args:
            plaintext: 明文数据 (必须是16字节整数倍)
        
        Returns:
            bytes: 加密后的密文，失败返回None
        """
        # 检查数据长度 (必须是16字节整数倍)
        if len(plaintext) % 16 != 0:
            # 自动填充
            padding_len = 16 - (len(plaintext) % 16)
            plaintext = plaintext + bytes([padding_len] * padding_len)
            print(f"⚠️  自动填充至 {len(plaintext)} 字节")
        
        # 构建加密包
        # 格式: src_port(2B) + dst_port(2B) + length(2B) + payload
        src_port = 0x1000.to_bytes(2, 'big')
        dst_port = CRYPTO_PORT.to_bytes(2, 'big')
        length = len(plaintext).to_bytes(2, 'big')
        
        packet = src_port + dst_port + length + plaintext
        
        # 发送并接收
        success, response = self._send_packet(CRYPTO_PORT, packet)
        
        if success and response:
            # 解析响应: status(1B) + length(2B) + ciphertext
            if len(response) >= 3:
                status = response[0]
                if status == 0x00:  # 成功
                    result_len = int.from_bytes(response[1:3], 'big')
                    ciphertext = response[3:3+result_len]
                    
                    self.packet_count += 1
                    self.byte_count += len(ciphertext)
                    
                    print(f"✅ 加密成功: {len(plaintext)} -> {len(ciphertext)} 字节")
                    return ciphertext
                else:
                    print(f"❌ 加密失败，状态码: {status:#x}")
            else:
                print("❌ 响应格式错误")
        return None
    
    def encrypt_file(self, input_file: str, output_file: str) -> bool:
        """
        加密文件
        
        使用方法:
        >>> driver.encrypt_file("plain.txt", "cipher.bin")
        
        Args:
            input_file: 输入文件路径
            output_file: 输出文件路径
        
        Returns:
            bool: 是否成功
        """
        try:
            with open(input_file, 'rb') as f:
                plaintext = f.read()
            
            # 分块加密 (每块最大16KB)
            chunk_size = 16 * 1024  # 16KB
            ciphertext = b''
            
            for i in range(0, len(plaintext), chunk_size):
                chunk = plaintext[i:i+chunk_size]
                encrypted = self.encrypt(chunk)
                if encrypted:
                    ciphertext += encrypted
                else:
                    print(f"❌ 加密第 {i//chunk_size} 块失败")
                    return False
            
            with open(output_file, 'wb') as f:
                f.write(ciphertext)
            
            print(f"✅ 文件加密完成: {input_file} -> {output_file}")
            print(f"   大小: {len(plaintext)} -> {len(ciphertext)} 字节")
            return True
            
        except Exception as e:
            print(f"❌ 文件加密失败: {e}")
            return False
    
    # =========================================================================
    # 快速通道 (FastPath) - 非加密数据透传
    # =========================================================================
    
    def send_fastpath(self, data: bytes, dst_port: int = 80) -> bool:
        """
        使用FastPath快速通道发送数据 (不加密)
        
        使用方法:
        >>> # 发送HTTP请求 (端口80，不加密)
        >>> driver.send_fastpath(b"GET / HTTP/1.1\r\n\r\n", dst_port=80)
        
        适用场景:
        - 普通网络流量 (HTTP, HTTPS等)
        - 不需要加密的数据
        
        Args:
            data: 要发送的数据
            dst_port: 目标端口
        
        Returns:
            bool: 是否成功
        """
        # FastPath规则:
        # 1. dst_port != CRYPTO (0x1234) && != CONFIG (0x4321)
        # 2. !drop_flag (未被ACL拦截)
        # 3. payload_len合法且16字节对齐
        
        if dst_port == CRYPTO_PORT or dst_port == CONFIG_PORT:
            print(f"❌ FastPath不支持端口 {dst_port:#x}，请使用encrypt()")
            return False
        
        # 构建FastPath包
        src_port = 0x1000.to_bytes(2, 'big')
        dst_port_bytes = dst_port.to_bytes(2, 'big')
        length = len(data).to_bytes(2, 'big')
        
        packet = src_port + dst_port_bytes + length + data
        
        success, _ = self._send_packet(DATA_PORT, packet)
        
        if success:
            print(f"✅ FastPath发送成功: {len(data)} 字节到端口 {dst_port}")
            return True
        return False
    
    # =========================================================================
    # 状态查询
    # =========================================================================
    
    def get_status(self) -> Dict:
        """
        获取SmartNIC状态
        
        使用方法:
        >>> status = driver.get_status()
        >>> print(f"加密包数: {status['encrypted_packets']}")
        >>> print(f"加密字节: {status['encrypted_bytes']}")
        >>> print(f"FastPath包数: {status['fastpath_packets']}")
        
        Returns:
            Dict: 状态信息字典
        """
        # 发送状态查询包
        query_packet = b'\x00' * 8  # 简化查询
        
        success, response = self._send_packet(0x1000, query_packet)
        
        if success and response and len(response) >= 16:
            return {
                'encrypted_packets': int.from_bytes(response[0:4], 'big'),
                'encrypted_bytes': int.from_bytes(response[4:8], 'big'),
                'fastpath_packets': int.from_bytes(response[8:12], 'big'),
                'dropped_packets': int.from_bytes(response[12:16], 'big'),
                'algorithm': 'AES-128-CBC' if self.config['algo'] == CryptoAlgorithm.AES_128_CBC else 'SM4-CBC',
                'local_ip': self.ip_addr,
                'local_port': self.fpga_port,
            }
        else:
            return {
                'encrypted_packets': self.packet_count,
                'encrypted_bytes': self.byte_count,
                'fastpath_packets': 0,
                'dropped_packets': 0,
                'algorithm': 'AES-128-CBC' if self.config['algo'] == CryptoAlgorithm.AES_128_CBC else 'SM4-CBC',
                'local_ip': self.ip_addr,
                'local_port': self.fpga_port,
            }
    
    def get_statistics(self) -> str:
        """
        获取统计信息并格式化输出
        
        使用方法:
        >>> print(driver.get_statistics())
        """
        status = self.get_status()
        
        info = """
╔══════════════════════════════════════╗
║        SmartNIC 状态统计              ║
╠══════════════════════════════════════╣
║  加密算法:     {}                     
║  加密包数:     {:,}                   
║  加密字节:     {:,}                   
║  FastPath:     {:,}                   
║  丢弃包数:     {:,}                   
╠══════════════════════════════════════╣
║  目标IP:       {}:{}                 
╚══════════════════════════════════════╝
""".format(
            status['algorithm'],
            status['encrypted_packets'],
            status['encrypted_bytes'],
            status['fastpath_packets'],
            status['dropped_packets'],
            status['local_ip'],
            status['local_port']
        )
        return info
    
    # =========================================================================
    # 内部方法
    # =========================================================================
    
    def _send_packet(self, port: int, data: bytes):
        """
        发送UDP包到SmartNIC
        
        Args:
            port: 目标端口
            data: 数据载荷
        
        Returns:
            Tuple[bool, bytes]: (是否成功, 响应数据)
        """
        if not self.sock:
            print("❌ 未连接SmartNIC，请先调用connect()")
            return False, b''
        
        try:
            self.sock.sendto(data, (self.ip_addr, port))
            response, addr = self.sock.recvfrom(65535)
            return True, response
        except socket.timeout:
            print(f"⏰ 通信超时 (端口 {port:#x})")
            return False, b''
        except Exception as e:
            print(f"❌ 通信错误: {e}")
            return False, b''


# ==============================================================================
# 简单使用示例
# ==============================================================================

def demo():
    """演示SmartNIC的基本使用方法"""
    
    print("=" * 60)
    print("SmartNIC 驱动程序演示")
    print("=" * 60)
    
    # 创建驱动实例
    driver = SmartNICDriver(ip_addr='192.168.1.10', fpga_port=8080)
    
    # 连接
    if not driver.connect():
        return
    
    # 1. 配置AES加密
    print("\n[1] 配置AES-128-CBC加密:")
    driver.set_aes()
    
    # 2. 加密数据
    print("\n[2] 加密数据:")
    plaintext = b"Hello, SmartNIC! " * 4  # 64字节，16的倍数
    print(f"   明文: {plaintext[:32]}... ({len(plaintext)} 字节)")
    
    ciphertext = driver.encrypt(plaintext)
    if ciphertext:
        print(f"   密文: {ciphertext[:32]}... ({len(ciphertext)} 字节)")
    
    # 3. 切换到SM4加密
    print("\n[3] 切换到SM4-CBC加密:")
    driver.set_sm4()
    
    # 4. 使用SM4加密
    print("\n[4] SM4加密:")
    plaintext2 = b"SM4 Test Data    " * 4  # 64字节
    ciphertext2 = driver.encrypt(plaintext2)
    if ciphertext2:
        print(f"   明文: {plaintext2[:32]}...")
        print(f"   密文: {ciphertext2[:32]}...")
    
    # 5. FastPath透传
    print("\n[5] FastPath快速通道:")
    driver.send_fastpath(b"GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n", dst_port=80)
    
    # 6. 查看状态
    print("\n[6] 状态统计:")
    print(driver.get_statistics())
    
    # 断开连接
    driver.disconnect()
    
    print("\n" + "=" * 60)
    print("演示完成!")
    print("=" * 60)


# ==============================================================================
# 命令行接口
# ==============================================================================

def main():
    """命令行入口"""
    import argparse
    
    parser = argparse.ArgumentParser(description='SmartNIC Driver')
    parser.add_argument('--ip', default='192.168.1.10', help='SmartNIC IP地址')
    parser.add_argument('--port', type=int, default=8080, help='端口号')
    parser.add_argument('--algo', choices=['aes', 'sm4'], default='aes', help='加密算法')
    parser.add_argument('--encrypt', '-e', metavar='TEXT', help='加密文本')
    parser.add_argument('--file', '-f', metavar='INPUT', help='加密文件')
    parser.add_argument('--output', '-o', metavar='OUTPUT', help='输出文件')
    parser.add_argument('--demo', action='store_true', help='运行演示')
    parser.add_argument('--status', action='store_true', help='查询状态')
    
    args = parser.parse_args()
    
    if args.demo:
        demo()
        return
    
    # 创建驱动
    driver = SmartNICDriver(ip_addr=args.ip, fpga_port=args.port)
    
    if not driver.connect():
        return
    
    # 配置算法
    if args.algo == 'aes':
        driver.set_aes()
    else:
        driver.set_sm4()
    
    # 加密文本
    if args.encrypt:
        ciphertext = driver.encrypt(args.encrypt.encode())
        if ciphertext:
            print(f"密文: {ciphertext.hex()}")
    
    # 加密文件
    if args.file and args.output:
        driver.encrypt_file(args.file, args.output)
    
    # 查询状态
    if args.status:
        print(driver.get_statistics())
    
    driver.disconnect()


if __name__ == '__main__':
    main()
