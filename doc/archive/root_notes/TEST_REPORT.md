# 加密引擎错误修复与测试报告

## 一、修复工作总结

### 1. 已完成的修复

| 问题 | 文件 | 修复内容 | 状态 |
|------|------|----------|------|
| AES密钥位序错误 | `crypto_engine.sv:172` | 将`.key({128'd0, key})`改为`.key({key, 128'd0})` | ✅ 完成 |
| SM4 done信号问题 | `sm4_encdec.v:214-222` | 在IDLE状态时清零`reg_tmp` | ✅ 完成 |
| AES模块timescale | `aes_*.v` | 添加`timescale 1ns/1ps` | ✅ 完成 |
| SM4密钥扩展时序 | `key_expansion.v:206` | 修复`data_for_round`使用`user_key_in` | ✅ 完成 |

### 2. 测试验证结果

#### AES-128 加密/解密: 全部通过 ✅

```
Key:        2b7e151628aed2a6abf7158809cf4f3c
Plaintext:  3243f6a8885a308d313198a2e0370734
Ciphertext: 3925841d02dc09fbdc118597196a0b32
-> [PASS] AES-128 encryption correct!

Key:        2b7e151628aed2a6abf7158809cf4f3c
Ciphertext: 3925841d02dc09fbdc118597196a0b32
Plaintext:  3243f6a8885a308d313198a2e0370734
-> [PASS] AES-128 decryption correct!
```

**结论**: AES-128加密和解密功能完全正确，符合FIPS 197标准测试向量。

#### SM4 加密/解密: 字节序问题 ⚠️

```
Key:        0123456789abcdeffedcba9876543210
Plaintext:  0123456789abcdeffedcba9876543210
Expected:   681edf34d206965e86b3e94f536e4246
Result:     abee7cb0f2298f31cd3849034ef09779
```

**分析**:
- `result_31 = 4ef09779cd384903f2298f31abee7cb0`
- 实际输出 = `abee7cb0f2298f31cd3849034ef09779` (字节序反转)

这表明SM4加密算法本身可能是正确的，但字节序处理存在问题。

---

## 二、发现的问题

### 问题1: AES密钥位序错误 ✅ 已修复

**位置**: `rtl/core/crypto/crypto_engine.sv:172`

**原因**: 
- `crypto_engine.sv` 将密钥放在低128位: `.key({128'd0, key})`
- `aes_key_mem.v` 取高128位作为密钥: `key_mem_new = key[255:128]`
- 结果：AES实际使用的是零作为密钥

**修复**: 将密钥连接改为 `.key({key, 128'd0})`

### 问题2: SM4 done信号持续问题 ✅ 已修复

**位置**: `rtl/core/crypto/sm4_encdec.v:214-222`

**原因**: 
- `ready_out` (done信号) 在加密完成后保持高电平
- 新操作开始时，`ready_out` 仍为高
- `reg_tmp` 没有在新操作开始时清零

**修复**: 在IDLE状态时清零 `reg_tmp`

### 问题3: SM4字节序问题 ⚠️ 待修复

**现象**: SM4加密结果与标准值不匹配，但结果呈现字节序反转特征

**可能原因**:
1. 轮密钥的字节序处理
2. 数据输入/输出的字节序处理
3. SM4标准使用大端序，而实现可能使用小端序

---

## 三、测试用例详情

### AES测试用例

| 测试项 | 输入 | 期望输出 | 实际输出 | 结果 |
|--------|------|----------|----------|------|
| AES-128加密 | 3243f6a8885a308d313198a2e0370734 | 3925841d02dc09fbdc118597196a0b32 | 3925841d02dc09fbdc118597196a0b32 | PASS |
| AES-128解密 | 3925841d02dc09fbdc118597196a0b32 | 3243f6a8885a308d313198a2e0370734 | 3243f6a8885a308d313198a2e0370734 | PASS |

### SM4测试用例

| 测试项 | 输入 | 期望输出 | 实际输出 | 结果 |
|--------|------|----------|----------|------|
| SM4加密 | 0123456789abcdeffedcba9876543210 | 681edf34d206965e86b3e94f536e4246 | abee7cb0f2298f31cd3849034ef09779 | FAIL |
| SM4解密 | 681edf34d206965e86b3e94f536e4246 | 0123456789abcdeffedcba9876543210 | 未测试 | - |

---

## 四、下一步工作

### 高优先级

1. **修复SM4字节序问题**
   - 检查`sm4_top.v`中的数据输入/输出处理
   - 检查`key_expansion.v`中的轮密钥字节序
   - 检查`sm4_encdec.v`中的结果输出处理

2. **验证SM4解密功能**
   - 修复字节序问题后测试解密

### 中优先级

1. **添加边界条件测试**
   - 全零输入测试
   - 全F输入测试

2. **性能测试**
   - 吞吐量测量
   - 延迟测量

---

## 五、文件修改记录

| 文件 | 修改类型 | 描述 |
|------|----------|------|
| `rtl/core/crypto/crypto_engine.sv` | 修改 | 修复AES密钥位序 |
| `rtl/core/crypto/sm4_encdec.v` | 修改 | 修复done信号问题 |
| `rtl/core/crypto/aes_encipher_block.v` | 修改 | 添加timescale |
| `rtl/core/crypto/aes_decipher_block.v` | 修改 | 添加timescale |
| `rtl/core/crypto/aes_key_mem.v` | 修改 | 添加timescale |
| `rtl/core/crypto/aes_sbox.v` | 修改 | 添加timescale |
| `rtl/core/crypto/aes_inv_sbox.v` | 修改 | 添加timescale |
| `rtl/core/crypto/key_expansion.v` | 修改 | 修复密钥扩展时序 |

---

## 六、结论

### 成功完成
- ✅ AES-128加密功能完全正确
- ✅ AES-128解密功能完全正确
- ✅ AES密钥位序问题已修复
- ✅ SM4 done信号问题已修复
- ✅ SM4密钥扩展时序问题已修复

### 待解决问题
- ⚠️ SM4字节序问题需要修复
- ⚠️ SM4加密/解密输出不正确

### 建议
1. 优先解决SM4字节序问题
2. 完成后运行完整的回归测试
3. 添加更多边界条件测试用例

---

*报告更新时间: 2026-02-22*
