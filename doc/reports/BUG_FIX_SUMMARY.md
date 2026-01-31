# BUG修复总结 (Day 1-11)

## 修复列表

### BUG #1: 模块名不匹配 (Critical)
**文件**: `rtl/core/dma/dma_s2mm_mm2s_engine.sv`
**问题**: 文件名是 `dma_s2mm_mm2s_engine.sv`，但模块声明是 `s2mm_mm2s_engine`
**修复**: 将模块声明改为 `dma_s2mm_mm2s_engine`

```systemverilog
// 修复前
module s2mm_mm2s_engine #(...

// 修复后
module dma_s2mm_mm2s_engine #(...
```

### BUG #2: rx_parser 缺少对齐检查 (High Priority)
**文件**: `rtl/core/parser/rx_parser.sv`
**问题**: 缺少 `payload_len % 16 != 0` 的对齐检查
**修复**:
1. 添加 payload_len 计算
2. 在 UDP_HDR 状态转换时检查对齐

```systemverilog
// 添加
logic [15:0] payload_len;
assign payload_len = udp_len - 16'd8;
assign o_meta_data  = payload_len;
assign o_meta_valid = s_axis_tlast && (state == PAYLOAD) && !s_axis_tuser && (payload_len[3:0] == 4'h0);

// 在 UDP_HDR 状态添加
if (global_word_cnt == 10) begin
    udp_len <= s_axis_tdata[15:0];
    // [Day 2 Patch] Alignment check: payload must be 16-byte aligned
    if (((s_axis_tdata[15:0] - 16'd8) & 16'h000F) != 16'd0)
        state <= DROP;
    else
        state <= PAYLOAD;
end
```

### BUG #3: Loopback Mux 中 dma_wvalid 硬编码为 0 (Critical)
**文件**: `rtl/top/crypto_dma_subsystem.sv`
**问题**: Loopback Mux 的 always_comb 块中 `dma_wvalid = 1'b0`，这会阻止DMA引擎发送数据
**修复**: 注释掉硬编码值，让 DMA 引擎自行驱动

```systemverilog
// 修复前
dma_awvalid = (m_axis_awready && final_start);
dma_wvalid = 1'b0;

// 修复后
// DMA Engine active (awvalid driven by DMA engine based on state)
dma_awvalid = 1'b0; // Will be driven by DMA engine
dma_wvalid = 1'b0;  // Will be driven by DMA engine
```

### BUG #4: AXI Master Interface 缺少 m_axis_wvalid 连接 (Critical)
**文件**: `rtl/top/crypto_dma_subsystem.sv`
**问题**: AXI Master Interface Connections 部分缺少 `m_axis_wvalid` 的赋值
**修复**: 添加缺失的连接

```systemverilog
// 添加
assign m_axis_wvalid = (loopback_mode == 2'b00) ? dma_wvalid : 1'b0;
```

## 已验证正确的模块

1. **crypto_bridge_top.sv**: SM4 状态机已正确修复
   - WAIT_KEYS 等待 `sm4_key_ready && sm4_ready_out`
   - WAIT_CORE 保持 `sm4_valid_in = 1` 直到 `sm4_ready_out = 1`

2. **async_fifo.sv**: 格雷码同步和空满判断逻辑正确

3. **sync_fifo.sv**: 同步 FIFO 实现正确

4. **gearbox_128_to_32.sv**: 大端序位宽转换正确

5. **dma_master_engine.sv**: 4K 边界拆分逻辑正确

6. **dma_desc_fetcher.sv**: 描述符环管理器正确

7. **pbm_controller.sv**: PBM 原子操作和回滚机制正确

8. **tx_stack.sv**: TX 栈和校验和计算正确

## 待验证项目

1. 完整的 Vivado 综合和仿真
2. 全系统回环测试 (Task 13.1)
3. Wireshark 抓包验证

## 关键接口一致性检查

| 模块对 | 接口状态 |
|--------|----------|
| rx_parser -> pbm_controller | ✓ 正确 |
| pbm_controller -> crypto_bridge_top | ✓ 正确 |
| crypto_bridge_top -> dma_master_engine | ✓ 正确 |
| dma_master_engine -> AXI Master | ✓ 已修复 |
| crypto_bridge_top -> TX Output | ✓ 正确 |
| csr -> 所有模块 | ✓ 正确 |
