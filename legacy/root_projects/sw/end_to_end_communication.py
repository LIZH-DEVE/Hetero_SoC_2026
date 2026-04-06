#!/usr/bin/env python3
"""
SmartNIC 端到端通信示例
实现: 发送端加密数据 -> SmartNIC -> 接收端解密

系统架构:
┌──────────────┐                    ┌──────────────┐
│   发送端      │                    │   接收端      │
│  (PC/Server) │                    │  (PC/Server) │
│              │                    │              │
│  加密数据     │  ─── UDP 网络 ──▶  │  接收数据     │
│  发送给      │     (以太网)        │  等待接收     │
│  SmartNIC    │◀──────────────────  │  发送给      │
│              │     (加密结果)      │  SmartNIC    │
└──────────────┘                    └──────────────┘
       │                                   │
       │          UDP Socket               │
       └──────────────┬────────────────────┘
                      │
                      ▼
            ┌──────────────────┐
            │   SmartNIC       │
            │   (FPGA加速卡)   │
            │                  │
            │  加密: AES/SM4   │
            │  端口: 8080      │
            │  IP: 192.168.1.10│
            └──────────────────┘

使用场景:
1. 发送端: 输入明文 -> SmartNIC加密 -> 发送到网络
2. 接收端: 从网络接收 -> SmartNIC解密 -> 输出明文

注意: SmartNIC是硬件加速卡，插在服务器上
      发送端和接收端都需要与SmartNIC通信
"""

import socket
import struct
import time
import random
import os
from typing import Tuple, Optional, Dict, List
from enum import Enum
import threading
import queue

# ==============================================================================
# 常量定义
# ==============================================================================

# SmartNIC配置
SMARTNIC_IP = '192.168.1.10'  # SmartNIC的IP地址
SMARTNIC_PORT = 8080          # SmartNIC的通信端口

# 加密端口
CRYPTO_PORT = 0x1234          # 加密服务端口
CONFIG_PORT = 0x4321          # 配置端口

# 加密算法
class CryptoAlgorithm(Enum):
    AES_128_CBC = 0
    SM4_CBC = 1

# ==============================================================================
# SmartNIC驱动类
# ==============================================================================

class SmartNICDriver:
    """SmartNIC驱动程序"""
    
    def __init__(self, smartnic_ip: str = SMARTNIC_IP, smartnic_port: int = SMARTNIC_PORT):
        self.smartnic_ip = smartnic_ip
        self.smartnic_port = smartnic_port
        self.sock = None
        self.config = {
            'algo': CryptoAlgorithm.AES_128_CBC,
            'key': bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c'),
            'iv': bytes.fromhex('000102030405060708090a0b0c0d0e0f'),
            'timeout': 5.0,
        }
    
    def connect(self) -> bool:
        """连接到SmartNIC"""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.settimeout(self.config['timeout'])
            self.sock.connect((self.smartnic_ip, self.smartnic_port))
            print(f"✅ 已连接到 SmartNIC ({self.smartnic_ip}:{self.smartnic_port})")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False
    
    def disconnect(self):
        """断开连接"""
        if self.sock:
            self.sock.close()
            self.sock = None
            print("🔌 已断开与SmartNIC的连接")
    
    def set_aes(self, key: Optional[bytes] = None, iv: Optional[bytes] = None) -> bool:
        """配置AES加密"""
        default_key = bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c')
        default_iv = bytes.fromhex('000102030405060708090a0b0c0d0e0f')
        return self._set_config(CryptoAlgorithm.AES_128_CBC, key or default_key, iv or default_iv)
    
    def set_sm4(self, key: Optional[bytes] = None, iv: Optional[bytes] = None) -> bool:
        """配置SM4加密"""
        default_key = bytes.fromhex('0123456789abcdeffedcba9876543210')
        default_iv = bytes.fromhex('00000000000000000000000000000000')
        return self._set_config(CryptoAlgorithm.SM4_CBC, key or default_key, iv or default_iv)
    
    def _set_config(self, algo: CryptoAlgorithm, key: bytes, iv: bytes) -> bool:
        """内部配置方法"""
        self.config['algo'] = algo
        self.config['key'] = key
        self.config['iv'] = iv
        
        magic = 0xDEADBEEF.to_bytes(4, 'big')
        seq_id = random.randint(1, 65535).to_bytes(2, 'big')
        algo_byte = bytes([algo.value])
        
        config_packet = magic + seq_id + algo_byte + key + iv
        
        try:
            self.sock.sendto(config_packet, (self.smartnic_ip, self.smartnic_port))
            response, _ = self.sock.recvfrom(65535)
            print(f"🔐 已配置 {algo.name} 加密")
            return True
        except Exception as e:
            print(f"❌ 配置失败: {e}")
            return False
    
    def encrypt(self, plaintext: bytes) -> Optional[bytes]:
        """加密数据"""
        # 自动填充
        if len(plaintext) % 16 != 0:
            padding_len = 16 - (len(plaintext) % 16)
            plaintext = plaintext + bytes([padding_len] * padding_len)
        
        # 构建数据包
        src_port = 0x1000.to_bytes(2, 'big')
        dst_port = CRYPTO_PORT.to_bytes(2, 'big')
        length = len(plaintext).to_bytes(2, 'big')
        packet = src_port + dst_port + length + plaintext
        
        try:
            self.sock.sendto(packet, (self.smartnic_ip, self.smartnic_port))
            response, _ = self.sock.recvfrom(65535)
            
            if len(response) >= 3:
                status = response[0]
                if status == 0:
                    result_len = int.from_bytes(response[1:3], 'big')
                    return response[3:3+result_len]
            return None
        except Exception as e:
            print(f"❌ 加密失败: {e}")
            return None
    
    def decrypt(self, ciphertext: bytes) -> Optional[bytes]:
        """解密数据 (模拟，实际SmartNIC可能不支持)"""
        # 注意: 这个函数是模拟的
        # 实际使用中，如果SmartNIC支持解密，调用相同接口
        # 这里使用Python密码库进行演示
        try:
            from Crypto.Cipher import AES
            key = self.config['key']
            iv = self.config['iv']
            
            if self.config['algo'] == CryptoAlgorithm.AES_128_CBC:
                cipher = AES.new(key, AES.MODE_CBC, iv)
                decrypted = cipher.decrypt(ciphertext)
                
                # 去除填充
                padding_len = decrypted[-1]
                if padding_len <= 16:
                    decrypted = decrypted[:-padding_len]
                    return decrypted
            return None
        except Exception as e:
            print(f"❌ 解密失败: {e}")
            return None


# ==============================================================================
# 接收端类 (等待并解密数据)
# ==============================================================================

class SmartNICReceiver:
    """接收端 - 监听网络端口，接收加密数据，解密后显示"""
    
    def __init__(self, listen_port: int = 9000, smartnic_driver: SmartNICDriver = None):
        self.listen_port = listen_port
        self.smartnic = smartnic_driver
        self.sock = None
        self.running = False
        self.message_queue = queue.Queue()
    
    def start(self):
        """开始监听"""
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(('0.0.0.0', self.listen_port))
        self.sock.settimeout(0.5)
        
        self.running = True
        print(f"🎧 开始监听端口 {self.listen_port}...")
        print("   按 Ctrl+C 停止监听")
        
        # 启动接收线程
        self.receive_thread = threading.Thread(target=self._receive_loop)
        self.receive_thread.start()
    
    def _receive_loop(self):
        """接收循环"""
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
                print(f"\n📥 收到来自 {addr[0]}:{addr[1]} 的数据")
                print(f"   数据长度: {len(data)} 字节")
                
                if self.smartnic:
                    # 解密
                    decrypted = self.smartnic.decrypt(data)
                    if decrypted:
                        print(f"✅ 解密成功!")
                        print(f"   明文: {decrypted.decode('utf-8', errors='ignore')}")
                        
                        # 尝试解析JSON
                        try:
                            import json
                            json_data = json.loads(decrypted)
                            print("   JSON解析:")
                            print(f"   {json.dumps(json_data, indent=8, ensure_ascii=False)}")
                        except:
                            pass
                    else:
                        print(f"❌ 解密失败")
                        print(f"   原始数据: {data.hex()[:64]}...")
                else:
                    print(f"   数据: {data.hex()[:64]}...")
                
                print(f"\n🎧 继续监听...")
                
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"❌ 接收错误: {e}")
    
    def stop(self):
        """停止监听"""
        self.running = False
        if self.sock:
            self.sock.close()
        print("⏹️  已停止监听")


# ==============================================================================
# 发送端类 (加密并发送数据)
# ==============================================================================

class SmartNICSender:
    """发送端 - 加密数据并发送到网络"""
    
    def __init__(self, smartnic_driver: SmartNICDriver, target_ip: str, target_port: int):
        self.smartnic = smartnic_driver
        self.target_ip = target_ip
        self.target_port = target_port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    def send_text(self, text: str) -> bool:
        """发送文本"""
        plaintext = text.encode('utf-8')
        return self._send_data(plaintext)
    
    def send_json(self, data: dict) -> bool:
        """发送JSON数据"""
        json_str = json.dumps(data, ensure_ascii=False)
        return self.send_text(json_str)
    
    def send_file(self, filename: str) -> bool:
        """发送文件"""
        try:
            with open(filename, 'rb') as f:
                content = f.read()
            
            # 分块发送
            chunk_size = 1024  # 1KB每块
            total = len(content)
            sent = 0
            
            for i in range(0, total, chunk_size):
                chunk = content[i:i+chunk_size]
                if self._send_data(chunk):
                    sent += len(chunk)
                    print(f"\r   发送进度: {sent}/{total} 字节 ({sent*100//total}%)", end='')
            
            print()  # 换行
            print(f"✅ 文件发送完成: {sent} 字节")
            return True
        except Exception as e:
            print(f"❌ 文件发送失败: {e}")
            return False
    
    def _send_data(self, data: bytes) -> bool:
        """内部发送方法"""
        # 先加密
        ciphertext = self.smartnic.encrypt(data)
        if not ciphertext:
            print("❌ 加密失败")
            return False
        
        # 发送到目标
        try:
            self.sock.sendto(ciphertext, (self.target_ip, self.target_port))
            print(f"✅ 已发送 {len(data)} 字节 -> {self.target_ip}:{self.target_port}")
            return True
        except Exception as e:
            print(f"❌ 发送失败: {e}")
            return False


# ==============================================================================
# 模拟SmartNIC服务器 (用于测试，没有实际硬件时使用)
# ==============================================================================

class SimulatedSmartNIC:
    """模拟SmartNIC服务器 (用于测试)"""
    
    def __init__(self, ip: str = '127.0.0.1', port: int = 8080):
        self.ip = ip
        self.port = port
        self.sock = None
        self.running = False
        self.algo = CryptoAlgorithm.AES_128_CBC
        self.key = bytes.fromhex('2b7e151628aed2a6abf7158809cf4f3c')
        self.iv = bytes.fromhex('000102030405060708090a0b0c0d0e0f')
    
    def start(self):
        """启动模拟SmartNIC"""
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((self.ip, self.port))
        self.sock.settimeout(0.5)
        
        self.running = True
        print(f"🔧 模拟SmartNIC已启动 ({self.ip}:{self.port})")
        
        self.thread = threading.Thread(target=self._handle_requests)
        self.thread.start()
    
    def _handle_requests(self):
        """处理请求"""
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
                
                if len(data) < 8:
                    continue
                
                # 解析端口
                src_port = int.from_bytes(data[0:2], 'big')
                dst_port = int.from_bytes(data[2:4], 'big')
                length = int.from_bytes(data[4:6], 'big')
                payload = data[6:6+length]
                
                print(f"🔧 收到请求: src={src_port}, dst={dst_port}, len={length}")
                
                if dst_port == CONFIG_PORT:
                    # 配置请求
                    if len(data) >= 40:
                        magic = int.from_bytes(data[6:10], 'big')
                        if magic == 0xDEADBEEF:
                            algo_byte = data[12]
                            self.algo = CryptoAlgorithm(algo_byte)
                            self.key = data[13:29]
                            self.iv = data[29:45]
                            print(f"   配置: {self.algo.name}")
                    
                    # 发送响应
                    self.sock.sendto(bytes([0]), addr)
                
                elif dst_port == CRYPTO_PORT:
                    # 加密请求
                    ciphertext = self._encrypt_data(payload)
                    
                    # 发送响应
                    response = bytes([0]) + len(ciphertext).to_bytes(2, 'big') + ciphertext
                    self.sock.sendto(response, addr)
                    print(f"   加密完成: {len(payload)} -> {len(ciphertext)} 字节")
                
                else:
                    # 其他端口，直接透传
                    self.sock.sendto(data[6:], addr)
            
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"❌ 处理错误: {e}")
    
    def _encrypt_data(self, data: bytes) -> bytes:
        """模拟加密"""
        # 实际使用中，这里会调用FPGA硬件加密
        # 这里使用Python密码库模拟
        
        try:
            from Crypto.Cipher import AES
            from Crypto.Util.Padding import pad
            
            if self.algo == CryptoAlgorithm.AES_128_CBC:
                cipher = AES.new(self.key, AES.MODE_CBC, self.iv)
                return cipher.encrypt(pad(data, 16))
            else:
                # SM4 简化模拟 (实际需要SM4库)
                cipher = AES.new(self.key, AES.MODE_CBC, self.iv)
                return cipher.encrypt(pad(data, 16))
                
        except ImportError:
            # 如果没有pycryptodome，简单异或模拟
            result = bytes([b ^ 0x55 for b in data])
            return result
    
    def stop(self):
        """停止"""
        self.running = False
        if self.sock:
            self.sock.close()
        print("🔧 模拟SmartNIC已停止")


# ==============================================================================
# 主程序 - 选择运行模式
# ==============================================================================

import json

def print_menu():
    """打印菜单"""
    print("\n" + "="*60)
    print("   SmartNIC 端到端通信演示")
    print("="*60)
    print()
    print("  模式选择:")
    print("  1. 发送端模式 - 加密并发送数据到指定地址")
    print("  2. 接收端模式 - 监听端口并解密数据")
    print("  3. 双向模式 - 同时发送和接收")
    print("  4. 模拟模式 - 使用软件模拟SmartNIC")
    print("  5. 交互模式 - 命令行交互")
    print()
    print("  加密算法:")
    print("  A. AES-128-CBC (国际标准)")
    print("  S. SM4-CBC (中国国密)")
    print()
    print("  0. 退出")
    print()
    print("="*60)

def run_sender_mode(driver, target_ip: str, target_port: int):
    """发送端模式"""
    print("\n" + "="*60)
    print("   发送端模式")
    print("="*60)
    
    sender = SmartNICSender(driver, target_ip, target_port)
    
    while True:
        print("\n发送选项:")
        print("  1. 发送文本消息")
        print("  2. 发送JSON数据")
        print("  3. 发送文件")
        print("  4. 发送心跳包")
        print("  0. 返回主菜单")
        
        choice = input("\n请选择: ").strip()
        
        if choice == '1':
            text = input("输入消息: ")
            sender.send_text(text)
        
        elif choice == '2':
            data = {
                "type": "message",
                "content": input("输入消息内容: "),
                "sender": "SmartNIC Sender",
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
            }
            sender.send_json(data)
        
        elif choice == '3':
            filename = input("输入文件名: ")
            sender.send_file(filename)
        
        elif choice == '4':
            heartbeat = {
                "type": "heartbeat",
                "sender": "SmartNIC Sender",
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
            }
            sender.send_json(heartbeat)
            print("💓 心跳包已发送")
        
        elif choice == '0':
            break

def run_receiver_mode(driver, listen_port: int):
    """接收端模式"""
    print("\n" + "="*60)
    print("   接收端模式")
    print("="*60)
    
    receiver = SmartNICReceiver(listen_port, driver)
    
    try:
        receiver.start()
        print("\n等待数据... (按 Ctrl+C 停止)")
        
        # 保持运行
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n")
        receiver.stop()

def run_simulated_mode():
    """模拟模式"""
    print("\n" + "="*60)
    print("   模拟模式 (不需要实际SmartNIC硬件)")
    print("="*60)
    
    # 启动模拟SmartNIC
    sim_snic = SimulatedSmartNIC()
    sim_snic.start()
    
    # 等待模拟SmartNIC启动
    time.sleep(1)
    
    # 使用127.0.0.1作为SmartNIC地址
    driver = SmartNICDriver(smartnic_ip='127.0.0.1', smartnic_port=8080)
    driver.connect()
    
    # 选择加密算法
    algo_choice = input("选择加密算法 (A/S): ").strip().upper()
    if algo_choice == 'S':
        driver.set_sm4()
    else:
        driver.set_aes()
    
    # 发送测试数据
    print("\n发送测试数据...")
    
    plaintext = b"Hello from Simulated SmartNIC! " * 4
    print(f"原文: {plaintext[:32]}... ({len(plaintext)} 字节)")
    
    ciphertext = driver.encrypt(plaintext)
    if ciphertext:
        print(f"加密: {ciphertext[:32]}... ({len(ciphertext)} 字节)")
        
        # 解密验证
        decrypted = driver.decrypt(ciphertext)
        if decrypted:
            print(f"解密: {decrypted[:32]}... ({len(decrypted)} 字节)")
            
            if decrypted == plaintext:
                print("✅ 加解密验证成功!")
            else:
                print("❌ 加解密验证失败")
        else:
            print("❌ 解密失败")
    else:
        print("❌ 加密失败")
    
    driver.disconnect()
    sim_snic.stop()

def run_interactive_mode():
    """交互模式"""
    print("\n" + "="*60)
    print("   交互模式")
    print("="*60)
    print("输入命令进行操作 (help查看帮助)")
    
    driver = SmartNICDriver()
    driver.connect()
    
    # 默认使用AES
    driver.set_aes()
    
    sender = SmartNICSender(driver, '192.168.1.100', 9000)
    receiver = SmartNICReceiver(9000, driver)
    
    while True:
        try:
            cmd = input("\n>>> ").strip().lower()
            
            if not cmd:
                continue
            
            if cmd in ['exit', 'quit', '0']:
                break
            
            elif cmd == 'help':
                print("""
可用命令:
  send <消息>     - 发送文本消息
  sendjson        - 发送示例JSON
  sendfile <文件> - 发送文件
  receive <端口>  - 开始监听
  stop            - 停止监听
  aes             - 切换到AES加密
  sm4             - 切换到SM4加密
  status          - 查看状态
  help            - 显示此帮助
  exit            - 退出
""")
            
            elif cmd.startswith('send '):
                message = cmd[5:]
                sender.send_text(message)
            
            elif cmd == 'sendjson':
                data = {
                    "message": "Hello, SmartNIC!",
                    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
                    "data": [1, 2, 3, 4, 5]
                }
                sender.send_json(data)
            
            elif cmd.startswith('sendfile '):
                filename = cmd[9:]
                sender.send_file(filename)
            
            elif cmd.startswith('receive '):
                port = int(cmd[8:])
                receiver.listen_port = port
                receiver.start()
            
            elif cmd == 'stop':
                receiver.stop()
            
            elif cmd == 'aes':
                driver.set_aes()
            
            elif cmd == 'sm4':
                driver.set_sm4()
            
            elif cmd == 'status':
                print(driver.get_statistics())
            
            else:
                print(f"未知命令: {cmd}")
                print("输入 help 查看帮助")
        
        except KeyboardInterrupt:
            print("\n退出")
            break
        except Exception as e:
            print(f"错误: {e}")
    
    receiver.stop()
    driver.disconnect()

def main():
    """主函数"""
    while True:
        print_menu()
        
        # 选择模式
        choice = input("请选择运行模式 (1-5): ").strip()
        
        if choice == '0':
            print("再见!")
            break
        
        # 选择加密算法
        algo_choice = input("选择加密算法 (A/S): ").strip().upper()
        
        # 创建驱动
        driver = SmartNICDriver()
        if not driver.connect():
            print("无法连接到SmartNIC，是否使用模拟模式? (y/n)")
            if input().strip().lower() == 'y':
                run_simulated_mode()
                continue
            else:
                break
        
        # 配置加密
        if algo_choice == 'S':
            driver.set_sm4()
        else:
            driver.set_aes()
        
        # 根据选择运行
        if choice == '1':
            target_ip = input("目标IP地址 (默认 192.168.1.100): ").strip() or '192.168.1.100'
            target_port = int(input("目标端口 (默认 9000): ").strip() or '9000')
            run_sender_mode(driver, target_ip, target_port)
        
        elif choice == '2':
            listen_port = int(input("监听端口 (默认 9000): ").strip() or '9000')
            run_receiver_mode(driver, listen_port)
        
        elif choice == '3':
            target_ip = input("目标IP地址 (默认 192.168.1.100): ").strip() or '192.168.1.100'
            target_port = int(input("目标端口 (默认 9000): ").strip() or '9000')
            listen_port = int(input("监听端口 (默认 9001): ").strip() or '9001')
            
            # 启动接收线程
            receiver = SmartNICReceiver(listen_port, driver)
            receiver.start()
            
            # 主线程作为发送端
            sender = SmartNICSender(driver, target_ip, target_port)
            
            print("\n双向模式已启动:")
            print(f"  发送目标: {target_ip}:{target_port}")
            print(f"  监听端口: {listen_port}")
            print("按 Ctrl+C 停止")
            
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\n")
                receiver.stop()
        
        elif choice == '4':
            run_simulated_mode()
        
        elif choice == '5':
            run_interactive_mode()
        
        # 断开连接
        driver.disconnect()


if __name__ == '__main__':
    main()
