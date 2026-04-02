
`timescale 1 ns / 1 ps

	module crypto_accel_axi_slave_lite_v1_0_S00_AXI #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here

		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 3;
	//----------------------------------------------
	//-- Signals for user logic register space example
	//------------------------------------------------
	//-- Number of Slave Registers 16
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg7;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg8;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg9;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg10;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg11;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg12;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg13;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg14;
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg15;
	integer	 byte_index;

	// I/O Connections assignments

	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	// Implement Write state machine (Replaced with robust Xilinx AXI lite state machine)
	// Robust Decoupled AXI Lite Write/Read Logic
	reg axi_awv_awr_done;
	reg axi_wv_wr_done;
	reg axi_arv_arr_done;

    // Cache registers for decoupled write data
    reg [C_S_AXI_DATA_WIDTH-1:0]    axi_wdata_reg;
    reg [(C_S_AXI_DATA_WIDTH/8)-1:0] axi_wstrb_reg;

	always @(posedge S_AXI_ACLK) begin
	    if (S_AXI_ARESETN == 1'b0) begin
	        axi_awready <= 1'b0;
	        axi_wready  <= 1'b0;
	        axi_arready <= 1'b0;
	        axi_awaddr  <= 0;
	        axi_araddr  <= 0;
	        axi_bvalid  <= 1'b0;
	        axi_rvalid  <= 1'b0;
	        axi_bresp   <= 2'b0;
	        axi_rresp   <= 2'b0;
	        axi_awv_awr_done <= 1'b0;
	        axi_wv_wr_done   <= 1'b0;
	        axi_arv_arr_done <= 1'b0;
            axi_wdata_reg    <= 0;
            axi_wstrb_reg    <= 0;
	    end else begin
	        // 1. Write Address Channel
	        if (~axi_awv_awr_done && S_AXI_AWVALID) begin
	            // Back-pressure: Only for REG_DATA_IN (4'h1)
	            if (S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h1 && pbm_fifo_full) begin
	                axi_awready <= 1'b0;
	            end else begin
	                axi_awready <= 1'b1;
	                axi_awv_awr_done <= 1'b1;
	                axi_awaddr <= S_AXI_AWADDR;
	            end
	        end else begin
	            axi_awready <= 1'b0;
	        end

	        // 2. Write Data Channel
	        if (~axi_wv_wr_done && S_AXI_WVALID) begin
                // Back-pressure: If we already know the address is REG_DATA_IN
                if (axi_awv_awr_done && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h1) && pbm_fifo_full) begin
                    axi_wready <= 1'b0;
                end else begin
                    axi_wready <= 1'b1;
                    axi_wv_wr_done <= 1'b1;
                    axi_wdata_reg <= S_AXI_WDATA; // Latch data
                    axi_wstrb_reg <= S_AXI_WSTRB; // Latch strobes
                end
	        end else begin
	            axi_wready <= 1'b0;
	        end

	        // 3. Write Response Channel (BVALID)
	        if (axi_awv_awr_done && axi_wv_wr_done && ~axi_bvalid) begin
	            axi_bvalid <= 1'b1;
	            axi_bresp  <= 2'b0;
	        end else if (S_AXI_BREADY && axi_bvalid) begin
	            axi_bvalid <= 1'b0;
	            axi_awv_awr_done <= 1'b0;
	            axi_wv_wr_done   <= 1'b0;
	        end

	        // 4. Read Address Channel
	        if (~axi_arv_arr_done && S_AXI_ARVALID) begin
	            axi_arready <= 1'b1;
	            axi_arv_arr_done <= 1'b1;
	            axi_araddr <= S_AXI_ARADDR;
	        end else begin
	            axi_arready <= 1'b0;
	        end

	        // 5. Read Data Channel (RVALID)
	        if (axi_arv_arr_done && ~axi_rvalid) begin
	            axi_rvalid <= 1'b1;
	            axi_rresp  <= 2'b0;
	        end else if (S_AXI_RREADY && axi_rvalid) begin
	            axi_rvalid <= 1'b0;
	            axi_arv_arr_done <= 1'b0;
	        end
	    end
	end

    // 背压挂起周期计数器 (量化背压压力)
    reg [31:0] wready_stall_cnt;
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            wready_stall_cnt <= 32'd0;
        end else begin
            // 只要任一通道在写 REG_DATA_IN 时由于 FIFO 满而被阻塞，就累加
            // AW 阻塞：
            if (S_AXI_AWVALID && (S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h1) && pbm_fifo_full && !axi_awv_awr_done) begin
                wready_stall_cnt <= wready_stall_cnt + 1'b1;
            end
            // W 阻塞 (地址已知为 DATA_IN 且数据已到但 FIFO 满)：
            else if (S_AXI_WVALID && axi_awv_awr_done && (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h1) && pbm_fifo_full && !axi_wv_wr_done) begin
                wready_stall_cnt <= wready_stall_cnt + 1'b1;
            end
        end
    end

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.
	 
    wire slv_reg_wren = axi_awv_awr_done && axi_wv_wr_done && ~axi_bvalid;

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;
	      slv_reg1 <= 0;
	      slv_reg2 <= 0;
	      slv_reg3 <= 0;
	      slv_reg4 <= 0;
	      slv_reg5 <= 0;
	      slv_reg6 <= 0;
	      slv_reg7 <= 0;
	      slv_reg8 <= 0;
	      slv_reg9 <= 0;
	      slv_reg10 <= 0;
	      slv_reg11 <= 0;
	      slv_reg12 <= 0;
	      slv_reg13 <= 0;
	      slv_reg14 <= 0;
	      slv_reg15 <= 0;
	    end 
	  else begin
	    if (slv_reg_wren)
	      begin
	        case ( axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	          4'h0:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg0[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h1:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg1[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h2:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg2[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h3:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg3[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h4:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg4[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h5:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg5[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h6:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg6[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h7:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg7[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h8:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg8[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'h9:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg9[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'hA:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg10[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'hB:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg11[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'hC:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg12[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'hD:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg13[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'hE:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg14[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          4'hF:
	            for ( byte_index = 0; byte_index <= (C_S_AXI_DATA_WIDTH/8)-1; byte_index = byte_index+1 )
	              if ( axi_wstrb_reg[byte_index] == 1 ) begin
	                slv_reg15[(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
	              end  
	          default : begin
	                      slv_reg0 <= slv_reg0;
	                      slv_reg1 <= slv_reg1;
	                      slv_reg2 <= slv_reg2;
	                      slv_reg3 <= slv_reg3;
	                      slv_reg4 <= slv_reg4;
	                      slv_reg5 <= slv_reg5;
	                      slv_reg6 <= slv_reg6;
	                      slv_reg7 <= slv_reg7;
	                      slv_reg8 <= slv_reg8;
	                      slv_reg9 <= slv_reg9;
	                      slv_reg10 <= slv_reg10;
	                      slv_reg11 <= slv_reg11;
	                      slv_reg12 <= slv_reg12;
	                      slv_reg13 <= slv_reg13;
	                      slv_reg14 <= slv_reg14;
	                      slv_reg15 <= slv_reg15;
	                    end
	        endcase
	      end
	  end
	end    

	// Implement Read state machine - Already integrated into the decoupled main block above

	// Implement memory mapped register select and read logic generation
	// assign S_AXI_RDATA = (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2'h0) ? slv_reg0 : (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2'h1) ? slv_reg1 : (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2'h2) ? slv_reg2 : (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 2'h3) ? slv_reg3 :0;  

    // =========================================================
    // 1. 寄存器到引脚的静态映射 (Static Mapping)
    // =========================================================
    
    wire algo_sel   = slv_reg0[0];
    wire encdec     = slv_reg0[1];
    wire aes256_en  = slv_reg0[2];
    
    wire [127:0] combined_key_lo = {slv_reg7, slv_reg6, slv_reg5, slv_reg4};
    wire [127:0] combined_key_hi = {slv_reg11, slv_reg10, slv_reg9, slv_reg8};

    wire        sys_ready;
    wire        tx_empty;
    wire        pbm_rd_en;
    wire [31:0] tx_data_out;

    // =========================================================
    // 2. PBM 写入 FIFO (替换单周期脉冲, 兼容 FIFO 握手协议)
    // =========================================================
    //
    // 根因修复: crypto_bridge_top 的输入 FSM 期望 FIFO 协议:
    //   - i_pbm_empty 在有数据时持续为低
    //   - o_pbm_rd_en 由 FSM 发出读请求
    //   - i_pbm_valid 在读请求后 1 拍拉高, 同时提供 i_pbm_data

    // 2.1 AXI 写命中检测 (写 slv_reg1 = 地址索引 4'h1)
    wire [3:0] current_write_addr = axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];
    wire w_pbm_write_hit = slv_reg_wren && (current_write_addr == 4'h1);

    // 2.2 内嵌 PBM FIFO (深度 8, 宽度 32)
    localparam PBM_FIFO_DEPTH = 8;
    localparam PBM_FIFO_PTR_W = 3;   // log2(8)

    reg [31:0] pbm_fifo_mem [0:PBM_FIFO_DEPTH-1];
    reg [PBM_FIFO_PTR_W:0] pbm_fifo_wr_ptr;  // 额外 1 bit 用于满/空判断
    reg [PBM_FIFO_PTR_W:0] pbm_fifo_rd_ptr;

    wire pbm_fifo_empty = (pbm_fifo_wr_ptr == pbm_fifo_rd_ptr);
    wire pbm_fifo_full  = (pbm_fifo_wr_ptr[PBM_FIFO_PTR_W] != pbm_fifo_rd_ptr[PBM_FIFO_PTR_W]) &&
                          (pbm_fifo_wr_ptr[PBM_FIFO_PTR_W-1:0] == pbm_fifo_rd_ptr[PBM_FIFO_PTR_W-1:0]);

    // FIFO 写端: AXI 写 slv_reg1 → 推入
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            pbm_fifo_wr_ptr <= 0;
        end else begin
            if (w_pbm_write_hit && !pbm_fifo_full) begin
                pbm_fifo_mem[pbm_fifo_wr_ptr[PBM_FIFO_PTR_W-1:0]] <= axi_wdata_reg;
                pbm_fifo_wr_ptr <= pbm_fifo_wr_ptr + 1;
            end
        end
    end

    // FIFO 读端: crypto_bridge_top 的 o_pbm_rd_en → 弹出
    reg        pbm_rd_valid_reg;
    reg [31:0] pbm_rd_data_reg;

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            pbm_fifo_rd_ptr <= 0;
            pbm_rd_valid_reg <= 1'b0;
            pbm_rd_data_reg  <= 32'd0;
        end else begin
            pbm_rd_valid_reg <= 1'b0;
            if (pbm_rd_en && !pbm_fifo_empty) begin
                pbm_rd_data_reg  <= pbm_fifo_mem[pbm_fifo_rd_ptr[PBM_FIFO_PTR_W-1:0]];
                pbm_fifo_rd_ptr  <= pbm_fifo_rd_ptr + 1;
                pbm_rd_valid_reg <= 1'b1;
            end
        end
    end
	
    // 2.3 TX FIFO 数据读出脉冲 (绝对单周期握手, 不变)
    wire slv_reg_rden = S_AXI_ARVALID && S_AXI_ARREADY;
    wire w_tx_read_hit = slv_reg_rden && (S_AXI_ARADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h3);
    
    reg tx_rden_pulse;
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            tx_rden_pulse <= 1'b0;
        end else begin
            tx_rden_pulse <= w_tx_read_hit;
        end
    end

    // =========================================================
    // 3. 覆盖 AXI 默认读取行为 (修复 16 寄存器寻址断层)
    // =========================================================
    reg [C_S_AXI_DATA_WIDTH-1:0]    axi_rdata;
    assign S_AXI_RDATA = axi_rdata;

    reg [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA_OVERRIDE;
    // Debug Mapping: {12'hACE (Fingerprint), 8'd0, pbm_fifo_full, pbm_fifo_empty, pbm_fifo_wr_ptr, pbm_fifo_rd_ptr, tx_empty, sys_ready}
    // Bit 0: sys_ready
    // Bit 1: tx_empty
    // Bit 5-2: rd_ptr (4 bits)
    // Bit 9-6: wr_ptr (4 bits)
    // Bit 10: pbm_fifo_empty
    // Bit 11: pbm_fifo_full
    // Bit 31-20: 0xACE (Hardware Version Fingerprint)
    // Use a register to prevent constant propagation optimization
    // CRITICAL: dont_touch prevents Vivado from optimizing away the constant
    (* dont_touch = "true" *) reg [11:0] hw_fingerprint_reg;
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            hw_fingerprint_reg <= 12'hACE;
        end else begin
            hw_fingerprint_reg <= hw_fingerprint_reg;  // Self-feedback, not constant
        end
    end
    wire [C_S_AXI_DATA_WIDTH-1:0] hw_status_reg = {hw_fingerprint_reg, 8'd0, pbm_fifo_full, pbm_fifo_empty, pbm_fifo_wr_ptr, pbm_fifo_rd_ptr, tx_empty, sys_ready};
    
    always @(*) begin
        case (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
            4'h0: S_AXI_RDATA_OVERRIDE = slv_reg0;
            4'h1: S_AXI_RDATA_OVERRIDE = slv_reg1;
            4'h2: S_AXI_RDATA_OVERRIDE = hw_status_reg; // 硬件状态覆写
            4'h3: S_AXI_RDATA_OVERRIDE = tx_data_out;   // 密文输出覆写
            4'h4: S_AXI_RDATA_OVERRIDE = slv_reg4;
            4'h5: S_AXI_RDATA_OVERRIDE = slv_reg5;
            4'h6: S_AXI_RDATA_OVERRIDE = slv_reg6;
            4'h7: S_AXI_RDATA_OVERRIDE = slv_reg7;
            4'h8: S_AXI_RDATA_OVERRIDE = slv_reg8;
            4'h9: S_AXI_RDATA_OVERRIDE = slv_reg9;
            4'hA: S_AXI_RDATA_OVERRIDE = slv_reg10;
            4'hB: S_AXI_RDATA_OVERRIDE = slv_reg11;
            4'hC: S_AXI_RDATA_OVERRIDE = wready_stall_cnt; // 迁移至 0x30，避开 AES-256 Key 空间
            4'hD: S_AXI_RDATA_OVERRIDE = slv_reg13;
            4'hE: S_AXI_RDATA_OVERRIDE = slv_reg14;
            4'hF: S_AXI_RDATA_OVERRIDE = slv_reg15;
            default: S_AXI_RDATA_OVERRIDE = 0;
        endcase
    end

    // Use standard AXI read register logic
    // 使用 ar done 标记触发数据锁存
    always @(posedge S_AXI_ACLK) begin
      if (S_AXI_ARESETN == 1'b0) begin
        axi_rdata  <= 0;
      end else begin
        if (axi_arv_arr_done && ~axi_rvalid) begin
          axi_rdata <= S_AXI_RDATA_OVERRIDE;
        end
      end
    end

    // =========================================================
    // 4. 核心引擎实例化 (PBM 接口改用 FIFO 信号)
    // =========================================================
    
    crypto_bridge_top #(
        .NUM_INSTANCES(1)
    ) u_crypto_bridge_top (
        .clk             (S_AXI_ACLK),
        .rst_n           (S_AXI_ARESETN),
        .i_algo_sel      (algo_sel),
        .i_encdec        (encdec),
        .i_aes256_en     (aes256_en),
        .i_key           (combined_key_lo),
        .i_key_hi        (combined_key_hi),
        .i_pbm_empty     (pbm_fifo_empty),       // FIFO 空信号 (持续有效)
        .i_pbm_valid     (pbm_rd_valid_reg),      // FIFO 读有效 (rd_en 后 1 拍)
        .i_pbm_data      (pbm_rd_data_reg),       // FIFO 读数据
        .o_pbm_rd_en     (pbm_rd_en),
        .i_tx_rd_en      (tx_rden_pulse),
        .o_tx_data       (tx_data_out),
        .o_tx_empty      (tx_empty),
        .o_system_ready  (sys_ready)
    );

	// User logic ends

	endmodule
