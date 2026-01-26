interface axi_stream_if #(
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 2
)
(
    input logic clk,
    input logic rst_n
);

    // 1. 信号定义：总线的“物理线路” 
    logic                    tvalid; // Master 发起传输请求
    logic                    tready; // Slave 响应接收请求
    logic [DATA_WIDTH-1:0]   tdata;  // 数据位
    logic [DATA_WIDTH/8-1:0] tkeep;  // 字节有效标志（处理非对齐数据）
    logic                    tlast;  // 数据包分界线 
    logic [ID_WIDTH-1:0]     tid;    // 路由ID（多核调度核心） 

    // 2. 角色定义：谁输出信号，谁输入信号 
    modport Master (
        output tvalid, tdata, tkeep, tlast, tid,
        input  tready
    );

    modport Slave (
        input  tvalid, tdata, tkeep, tlast, tid,
        output tready
    );

    // 3. 逻辑审计：SVA 断言（Protocol Checker） [cite: 14, 31]
    // 规则：只要 Ready 为低，Master 必须保持 Valid 状态和数据绝对稳定 
    property p_stable_on_backpressure;
        @(posedge clk) disable iff (!rst_n)
        (tvalid && !tready) |-> $stable(tdata) && $stable(tlast) && $stable(tid);
    endproperty

    ASSERT_STABLE: assert property (p_stable_on_backpressure)
        else $error("AXI-Stream Violation: Data changed during backpressure!");

endinterface