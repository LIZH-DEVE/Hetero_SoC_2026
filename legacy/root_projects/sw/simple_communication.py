#!/usr/bin/env python3
"""
SmartNIC 简化使用示例
两台电脑之间的加密通信

使用场景:
- 电脑A (发送端): 加密数据并发送到电脑B
- 电脑B (接收端): 接收数据并解密

注意: 两台电脑都需要连接到SmartNIC
      SmartNIC的IP地址是 192.168.1.10
"""

import socket
import sys
import time
import os

# 导入SmartNIC驱动
# 确保 sw 目录在Python路径中
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'sw'))
from smartnic_driver import SmartNICDriver

# ==============================================================================
# 配置信息
# ==============================================================================

# SmartNIC的配置
SMARTNIC_IP = '192.168.1.10'  # SmartNIC的IP地址 (固定)
SMARTNIC_PORT = 8080           # SmartNIC的通信端口 (固定)

# 网络配置
MY_IP = '0.0.0.0'              # 本机IP (0.0.0.0表示任意)
LISTEN_PORT = 9000             # 监听端口 (接收数据用)
TARGET_IP = '192.168.1.200'    # 目标IP (对方电脑)
TARGET_PORT = 9000             # 目标端口 (对方监听端口)

# ==============================================================================
# 发送端功能
# ==============================================================================

def sender_mode():
    """发送端: 加密数据并发送"""
    print("\n" + "="*60)
    print("   发送端模式")
    print("="*60)
    
    # 1. 创建驱动
    print("\n[1/5] 创建SmartNIC驱动...")
    driver = SmartNICDriver(
        smartnic_ip=SMARTNIC_IP,
        smartnic_port=SMARTNIC_PORT
    )
    
    # 2. 连接SmartNIC
    print(f"[2/5] 连接到 SmartNIC ({SMARTNIC_IP}:{SMARTNIC_PORT})...")
    if not driver.connect():
        print("❌ 连接失败! 请检查:")
        print("   1. SmartNIC是否已开机")
        print("   2. 网络连接是否正常")
        print("   3. IP地址是否正确")
        return
    print("✅ 连接成功")
    
    # 3. 选择加密方式
    print("\n[3/5] 选择加密方式:")
    print("   A. AES-128-CBC (国际标准)")
    print("   S. SM4-CBC (中国国密)")
    choice = input("   请选择 (A/S): ").strip().upper()
    
    if choice == 'S':
        print("   选择: SM4-CBC")
        if not driver.set_sm4():
            print("❌ SM4配置失败")
            driver.disconnect()
            return
    else:
        print("   选择: AES-128-CBC")
        if not driver.set_aes():
            print("❌ AES配置失败")
            driver.disconnect()
            return
    print("✅ 加密配置完成")
    
    # 4. 输入要发送的数据
    print(f"\n[4/5] 输入要加密并发送的数据:")
    print(f"   目标: {TARGET_IP}:{TARGET_PORT}")
    
    data = input("   请输入消息: ").strip()
    if not data:
        data = "Hello from SmartNIC!"  # 默认消息
    
    plaintext = data.encode('utf-8')
    print(f"   原文: {plaintext}")
    print(f"   长度: {len(plaintext)} 字节")
    
    # 5. 加密并发送
    print(f"\n[5/5] 加密并发送...")
    
    # 5.1 加密
    print("   步骤1: 发送给SmartNIC加密...")
    ciphertext = driver.encrypt(plaintext)
    
    if not ciphertext:
        print("❌ 加密失败!")
        driver.disconnect()
        return
    print(f"✅ 加密完成: {len(plaintext)} -> {len(ciphertext)} 字节")
    
    # 5.2 发送到网络
    print(f"   步骤2: 发送到网络 {TARGET_IP}:{TARGET_PORT}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.sendto(ciphertext, (TARGET_IP, TARGET_PORT))
        print(f"✅ 发送成功!")
    except Exception as e:
        print(f"❌ 发送失败: {e}")
        driver.disconnect()
        return
    
    print("\n" + "-"*60)
    print("发送完成!")
    print(f"  原始数据: {data}")
    print(f"  加密后: {ciphertext.hex()[:40]}...")
    print(f"  发送至: {TARGET_IP}:{TARGET_PORT}")
    print("-"*60)
    
    # 断开连接
    driver.disconnect()

# ==============================================================================
# 接收端功能
# ==============================================================================

def receiver_mode():
    """接收端: 接收数据并解密"""
    print("\n" + "="*60)
    print("   接收端模式")
    print("="*60)
    
    # 1. 创建驱动
    print("\n[1/5] 创建SmartNIC驱动...")
    driver = SmartNICDriver(
        smartnic_ip=SMARTNIC_IP,
        smartnic_port=SMARTNIC_PORT
    )
    
    # 2. 连接SmartNIC
    print(f"[2/5] 连接到 SmartNIC ({SMARTNIC_IP}:{SMARTNIC_PORT})...")
    if not driver.connect():
        print("❌ 连接失败! 请检查:")
        print("   1. SmartNIC是否已开机")
        print("   2. 网络连接是否正常")
        return
    print("✅ 连接成功")
    
    # 3. 选择加密方式 (必须与发送端一致!)
    print("\n[3/5] 选择加密方式 (必须与发送端一致):")
    print("   A. AES-128-CBC (国际标准)")
    print("   S. SM4-CBC (中国国密)")
    choice = input("   请选择 (A/S): ").strip().upper()
    
    if choice == 'S':
        print("   选择: SM4-CBC")
        if not driver.set_sm4():
            print("❌ SM4配置失败")
            driver.disconnect()
            return
    else:
        print("   选择: AES-128-CBC")
        if not driver.set_aes():
            print("❌ AES配置失败")
            driver.disconnect()
            return
    print("✅ 加密配置完成")
    
    # 4. 创建监听socket
    print(f"\n[4/5] 开始监听端口 {LISTEN_PORT}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((MY_IP, LISTEN_PORT))
    sock.settimeout(0.5)  # 0.5秒超时，支持Ctrl+C退出
    
    print(f"✅ 监听中...")
    print(f"   监听地址: {MY_IP}:{LISTEN_PORT}")
    print("   按 Ctrl+C 停止监听")
    print()
    
    # 5. 等待接收数据
    print("[5/5] 等待接收数据...")
    
    try:
        while True:
            try:
                # 接收数据
                data, addr = sock.recvfrom(65535)
                print(f"\n📥 收到来自 {addr[0]}:{addr[1]} 的数据")
                print(f"   数据长度: {len(data)} 字节")
                print(f"   加密数据: {data.hex()[:40]}...")
                
                # 发送给SmartNIC解密
                print("\n   发送给SmartNIC解密...")
                plaintext = driver.decrypt(data)
                
                if plaintext:
                    print(f"✅ 解密成功!")
                    print(f"   明文: {plaintext.decode('utf-8', errors='ignore')}")
                else:
                    print("❌ 解密失败")
                
                print("\n   继续监听...")
                
            except socket.timeout:
                continue
                
    except KeyboardInterrupt:
        print("\n\n停止监听")
    
    # 断开连接
    driver.disconnect()

# ==============================================================================
# 完整通信示例 (单次)
# ==============================================================================

def demo_mode():
    """演示模式: 发送一条消息并接收响应"""
    print("\n" + "="*60)
    print("   演示模式: 发送并接收")
    print("="*60)
    
    # 1. 连接SmartNIC
    print("\n[1] 连接到SmartNIC...")
    driver = SmartNICDriver()
    if not driver.connect():
        return
    driver.set_aes()
    
    # 2. 加密数据
    print("\n[2] 加密测试数据...")
    plaintext = b"Hello, SmartNIC! This is a test message."
    print(f"   原文: {plaintext}")
    
    ciphertext = driver.encrypt(plaintext)
    if not ciphertext:
        print("❌ 加密失败")
        driver.disconnect()
        return
    
    print(f"   密文: {ciphertext.hex()[:40]}...")
    
    # 3. 解密验证
    print("\n[3] 解密验证...")
    decrypted = driver.decrypt(ciphertext)
    
    if decrypted:
        print(f"   解密: {decrypted}")
        if decrypted == plaintext:
            print("✅ 加解密验证成功!")
        else:
            print("❌ 数据不匹配")
    else:
        print("❌ 解密失败 (模拟模式下可能不支持)")
    
    # 4. 断开
    print("\n[4] 断开连接...")
    driver.disconnect()
    
    print("\n" + "="*60)
    print("演示完成!")
    print("="*60)

# ==============================================================================
# 主菜单
# ==============================================================================

def main():
    """主函数"""
    print("\n" + "="*60)
    print("   SmartNIC 通信示例")
    print("="*60)
    print()
    print("  SmartNIC IP:", SMARTNIC_IP)
    print("  SmartNIC Port:", SMARTNIC_PORT)
    print()
    print("  使用说明:")
    print("  - 发送端: 在本机运行，选择发送模式")
    print("  - 接收端: 在另一台电脑运行，选择接收模式")
    print("  - 两台电脑都需要与SmartNIC通信")
    print()
    print("  网络配置:")
    print(f"  - 目标IP: {TARGET_IP}")
    print(f"  - 监听端口: {LISTEN_PORT}")
    print()
    print("-"*60)
    print()
    print("  选择模式:")
    print("  1. 发送端 - 加密数据并发送到网络")
    print("  2. 接收端 - 监听网络端口并解密数据")
    print("  3. 演示模式 - 本地加解密演示 (不需要网络)")
    print("  0. 退出")
    print()
    
    choice = input("请选择 (0-3): ").strip()
    
    if choice == '1':
        sender_mode()
    elif choice == '2':
        receiver_mode()
    elif choice == '3':
        demo_mode()
    elif choice == '0':
        print("再见!")
    else:
        print("无效选择")

if __name__ == '__main__':
    main()
