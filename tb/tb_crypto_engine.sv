`timescale 1ns / 1ps

/**
 * 模块名称: tb_crypto_engine
 * 版本: Day 07 - Ultimate Edition
 * 描述: 集成自动超时检测、动态结果队列与封装化断言的架构级 Testbench。
 */

module tb_crypto_engine();

    // ========================================================
    // 1. 参数与常量定义
    // ========================================================
    localparam CLK_PERIOD = 10; 
    
    // Golden Vector (AES-128-CBC)
    localparam [127:0] TEST_KEY   = 128'h2b7e151628aed2a6abf7158809cf4f3c;
    localparam [127:0] TEST_BLOCK = 128'h6bc1bee22e409f96e93d7e117393172a;
    localparam [511:0] GOLDEN_CIPHERTEXT = 512'h7649abac8119b246cee98e9b12e9197d4cbbc858756b358125529e9698a38f449f6f0796ee3e47b0d87c761b20527f78070134085f02751755efca3b4cdc7d62;

    // ========================================================
    // 2. 接口信号
    // ========================================================
    logic           clk, rst_n;
    logic           algo_sel, start, done, busy;
    logic [31:0]    i_total_len;
    logic [7:0]     s_axil_araddr;
    logic [31:0]    s_axil_rdata;
    logic [127:0]   key, din, dout;

    // ========================================================
    // 3. DUT 实例化
    // ========================================================
    crypto_engine u_dut (
        .clk(clk), .rst_n(rst_n),
        .algo_sel(algo_sel), .start(start), .i_total_len(i_total_len),
        .done(done), .busy(busy),
        .s_axil_araddr(s_axil_araddr), .s_axil_rdata(s_axil_rdata),
        .key(key), .din(din), .dout(dout)
    );

    // 时钟生成
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ========================================================
    // 4. 高级验证任务库 (Verification Tasks)
    // ========================================================

    // [基础任务] 系统复位
    task system_reset();
        begin
            rst_n = 0; start = 0; algo_sel = 0;
            i_total_len = 0; s_axil_araddr = 0;
            key = TEST_KEY; din = 0;
            #100 rst_n = 1;
            #20;
        end
    endtask

    // [基础任务] 驱动数据包
    task drive_packet(input [127:0] data_in);
        begin
            wait(!busy); // 阻塞直到空闲
            @(posedge clk);
            din   <= data_in;
            start <= 1;
            @(posedge clk);
            start <= 0;
        end
    endtask

    // [高级任务] 带超时机制的等待
    task wait_done_with_timeout(input integer max_cycles);
        begin
            fork
                begin : wait_loop
                    wait(done);
                end
                begin : timeout_monitor
                    repeat(max_cycles) @(posedge clk);
                    $display("\n[FATAL] Timeout waiting for DONE signal!");
                    $stop;
                end
            join_any
            disable fork; // 任何一个完成即退出
        end
    endtask

    // [高级任务] CSR 自动校验
    task check_csr(input [7:0] addr, input [31:0] expected_val, input string msg);
        logic [31:0] read_val;
        begin
            @(posedge clk);
            s_axil_araddr <= addr;
            @(posedge clk); // 模拟总线读延迟
            #1; // 采样窗口微调
            read_val = s_axil_rdata;

            if (read_val === expected_val)
                $display("   -> [PASS] %s: Expected %0d, Got %0d", msg, expected_val, read_val);
            else begin
                $display("   -> [FAIL] %s: Expected %0d, Got %0d", msg, expected_val, read_val);
                $stop;
            end
        end
    endtask

    // ========================================================
    // 5. 测试用例 (Test Cases)
    // ========================================================

    // 用例 1: AES Golden Model 验证
    task test_aes_golden();
        logic [127:0] result_queue[$]; // 动态队列，更灵活
        logic [511:0] assembled_result;
        integer i;
        begin
            $display("\n[TEST 1] AES-CBC Golden Vector Check");
            algo_sel = 0; i_total_len = 64;

            for (i = 0; i < 4; i++) begin
                drive_packet(TEST_BLOCK);
                wait_done_with_timeout(100); // 封装后的超时等待
                
                result_queue.push_back(dout); // 自动入队
                $display("   Block %0d Output: %h", i, dout);
                
                repeat($urandom_range(2, 5)) @(posedge clk);
            end

            // 拼接队列结果 (Block 0 is MSB)
            assembled_result = {result_queue[0], result_queue[1], result_queue[2], result_queue[3]};

            if (assembled_result === GOLDEN_CIPHERTEXT)
                $display("   -> [PASS] Ciphertext Matches Golden Model.");
            else begin
                $display("   -> [FAIL] Mismatch! \n      Exp: %h\n      Got: %h", GOLDEN_CIPHERTEXT, assembled_result);
                $stop;
            end
        end
    endtask

    // 用例 2: 安全特性验证
    task test_security();
        begin
            $display("\n[TEST 2] Security & Error Counting Check");
            
            // 1. 注入不对齐错误 (Len=63)
            i_total_len = 63; 
            din = 128'hDEAD_BEEF;
            
            @(posedge clk); start <= 1; @(posedge clk); start <= 0;
            
            repeat(10) @(posedge clk);
            if (!busy && !done) $display("   -> [PASS] Hardware Interceptor Blocked Invalid Request.");
            else begin $display("   -> [FAIL] Engine Started Unexpectedly!"); $stop; end

            // 2. 检查计数器 = 1
            check_csr(8'h44, 32'd1, "CSR Count (1st Error)");

            // 3. 再次注入错误 (Len=17)
            i_total_len = 17;
            @(posedge clk); start <= 1; @(posedge clk); start <= 0;
            repeat(5) @(posedge clk);

            // 4. 检查计数器 = 2
            check_csr(8'h44, 32'd2, "CSR Count (2nd Error)");
        end
    endtask

    // ========================================================
    // 6. 主程序
    // ========================================================
    initial begin
        $display("\n=== Day 07 Verification Start ===");
        system_reset();
        
        test_aes_golden();
        #50;
        test_security();

        $display("\n=== 🎉 ALL TESTS PASSED SUCCESSFULLY! ===");
        $finish;
    end

endmodule