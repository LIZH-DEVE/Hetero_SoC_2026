## 修复方案

### 1. AES修复 - 添加IV支持

**修改文件**: `crypto_engine.sv`
- 添加`i_iv`输入端口
- 修改`r_iv`初始化逻辑，使用外部IV

**修改文件**: `tb_decrypt_verification.sv`
- 使用正确的测试向量IV

### 2. SM4修复 - 轮密钥顺序问题

**修改文件**: `crypto_engine.sv`
- 添加`encdec`变化检测逻辑
- 当`encdec`变化时，强制重新执行密钥扩展
- 确保`encdec_sel_in`在密钥扩展过程中稳定

### 3. 创建全面测试用例

**新增文件**: `tb_crypto_comprehensive.sv`
- AES-128-ECB单块加密/解密测试
- AES-128-CBC模式测试（使用正确IV）
- SM4单块加密/解密测试
- 加解密往返测试
- 边界条件测试

### 4. 预期结果

- AES加密/解密功能正确
- SM4加密/解密功能正确
- 加解密往返一致性验证通过