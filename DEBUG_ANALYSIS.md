问题分析报告：

## 问题描述

仿真在等待 DMA Done 信号时卡住，`dma_done` 信号从未被设置为 1。

## 可能的原因分析

1. **PBM 数据写入问题**：测试台在注入数据时没有正确等待 `rx_wr_ready` 信号
   - 测试台代码：
     ```systemverilog
     for (int i=1; i<=8; i++) begin
         rx_wr_valid = 1;
         rx_wr_data = i * 32'h1111_1111;
         rx_wr_last = (i == 8);
         @(posedge clk);  // 问题：没有等待 rx_wr_ready
     end
     ```
   - 如果 PBM 的 `o_wr_ready` 不是一直为 1，数据可能没有被正确写入

2. **加密桥状态机问题**：
   - `crypto_bridge_top` 的状态机可能卡在某个状态
   - 需要检查 mid-fifo 和 gearbox 之间的握手机制

3. **DMA Engine 启动问题**：
   - `dma_master_engine` 可能没有正确接收到启动信号
   - 或者状态机在某个状态下卡住

4. **Fetcher 描述符读取问题**：
   - `dma_desc_fetcher` 可能没有正确读取描述符
   - 或者描述符格式不正确

## 建议的修复方案

### 修复 1：在测试台中添加正确的握手逻辑

修改测试台的数据注入部分，添加 `rx_wr_ready` 检查：

```systemverilog
for (int i=1; i<=8; i++) begin
    rx_wr_valid = 1;
    rx_wr_data = i * 32'h1111_1111;
    rx_wr_last = (i == 8);

    @(posedge clk);
    wait(rx_wr_ready);  // 等待 PBM 准备好
    $display("[TB] Wrote data %d: %h", i, rx_wr_data);
end
rx_wr_valid = 0; rx_wr_last = 0;
```

### 修复 2：检查描述符格式

确保描述符的格式正确：
- Word 0: 目标地址
- Word 1: 控制信息（长度 + 算法位）

### 修复 3：添加调试输出

在各个模块中添加 $display 语句，跟踪状态机转换。

### 修复 4：简化测试流程

先测试一个简单的场景，不使用 Fetcher，直接使用 CSR 控制模式：
1. 设置 ring_size = 0（使用 CSR 模式）
2. 写入地址和长度
3. 触发启动

这样可以隔离问题，确定是在 Fetcher 还是 DMA Engine。
