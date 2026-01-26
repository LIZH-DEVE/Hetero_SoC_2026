interface axi_lite_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    // 1. 写地址通道 (Write Address)
    logic [ADDR_WIDTH-1:0] awaddr;
    logic                  awvalid;
    logic                  awready;

    // 2. 写数据通道 (Write Data)
    logic [DATA_WIDTH-1:0] wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;   // 字节选通，控制写入哪个字节
    logic                  wvalid;
    logic                  wready;

    // 3. 写响应通道 (Write Response)
    logic [1:0]            bresp;   // 状态反馈：00=成功
    logic                  bvalid;
    logic                  bready;

    // 4. 读地址通道 (Read Address)
    logic [ADDR_WIDTH-1:0] araddr;
    logic                  arvalid;
    logic                  arready;

    // 5. 读数据通道 (Read Data)
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid;
    logic                  rready;

    // 视角定义
    modport Master (
        output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready,
        input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
    );

    modport Slave (
        input  awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready,
        output awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid
    );

endinterface