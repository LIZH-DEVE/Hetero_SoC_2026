package dma_csr_pkg;

  localparam int unsigned DMA_CONTRACT_VERSION = 2;

  localparam logic [31:0] DMA_CSR_CTRL = 32'h00000000;
  localparam logic [31:0] DMA_CSR_STATUS = 32'h00000004;
  localparam logic [31:0] DMA_CSR_CACHE_CTRL = 32'h00000040;
  localparam logic [31:0] DMA_CSR_LOOPBACK_MODE = 32'h00000048;
  localparam logic [31:0] DMA_CSR_RING_DOORBELL = 32'h0000004C;
  localparam logic [31:0] DMA_CSR_RING_BASE = 32'h00000050;
  localparam logic [31:0] DMA_CSR_RING_HW_HEAD = 32'h00000054;
  localparam logic [31:0] DMA_CSR_RING_SW_TAIL = 32'h00000058;
  localparam logic [31:0] DMA_CSR_RING_SIZE = 32'h0000005C;
  localparam logic [31:0] DMA_CSR_IRQ_ENABLE = 32'h00000060;
  localparam logic [31:0] DMA_CSR_IRQ_STATUS = 32'h00000064;
  localparam logic [31:0] DMA_CSR_IRQ_ACK = 32'h00000068;
  localparam logic [31:0] DMA_CSR_IRQ_COALESCE_COUNT = 32'h0000006C;
  localparam logic [31:0] DMA_CSR_IRQ_COALESCE_TIMEOUT = 32'h00000070;
  localparam logic [31:0] DMA_CSR_DEBUG_STATUS = 32'h000000D4;
  localparam logic [31:0] DMA_CSR_DEBUG_SOURCE_PROGRESS = 32'h000000D8;
  localparam logic [31:0] DMA_CSR_DEBUG_SINK_PROGRESS = 32'h000000DC;
  localparam logic [31:0] DMA_CSR_DEBUG_PLAINTEXT_WORD0 = 32'h000000E0;
  localparam logic [31:0] DMA_CSR_DEBUG_PLAINTEXT_WORD1 = 32'h000000E4;
  localparam logic [31:0] DMA_CSR_DEBUG_PLAINTEXT_WORD2 = 32'h000000E8;
  localparam logic [31:0] DMA_CSR_DEBUG_PLAINTEXT_WORD3 = 32'h000000EC;
  localparam logic [31:0] DMA_CSR_DEBUG_KEY_WORD0 = 32'h000000F0;
  localparam logic [31:0] DMA_CSR_DEBUG_KEY_WORD1 = 32'h000000F4;
  localparam logic [31:0] DMA_CSR_DEBUG_KEY_WORD2 = 32'h000000F8;
  localparam logic [31:0] DMA_CSR_DEBUG_KEY_WORD3 = 32'h000000FC;
  localparam logic [31:0] DMA_CSR_RING_DOORBELL_KICK = 32'h00000001;

  localparam int unsigned DMA_CTRL_BIT_START = 0;
  localparam logic [31:0] DMA_CTRL_START = 32'h00000001 << DMA_CTRL_BIT_START;
  localparam int unsigned DMA_CTRL_BIT_HW_INIT = 1;
  localparam logic [31:0] DMA_CTRL_HW_INIT = 32'h00000001 << DMA_CTRL_BIT_HW_INIT;
  localparam int unsigned DMA_CTRL_BIT_ALGO_SM4 = 2;
  localparam logic [31:0] DMA_CTRL_ALGO_SM4 = 32'h00000001 << DMA_CTRL_BIT_ALGO_SM4;
  localparam int unsigned DMA_CTRL_BIT_ENCRYPT = 3;
  localparam logic [31:0] DMA_CTRL_ENCRYPT = 32'h00000001 << DMA_CTRL_BIT_ENCRYPT;
  localparam int unsigned DMA_CTRL_BIT_S2MM_EN = 4;
  localparam logic [31:0] DMA_CTRL_S2MM_EN = 32'h00000001 << DMA_CTRL_BIT_S2MM_EN;
  localparam int unsigned DMA_CTRL_BIT_MM2S_EN = 5;
  localparam logic [31:0] DMA_CTRL_MM2S_EN = 32'h00000001 << DMA_CTRL_BIT_MM2S_EN;
  localparam int unsigned DMA_CTRL_BIT_AUTH_EN = 6;
  localparam logic [31:0] DMA_CTRL_AUTH_EN = 32'h00000001 << DMA_CTRL_BIT_AUTH_EN;
  localparam int unsigned DMA_CTRL_BIT_ACL_EN = 7;
  localparam logic [31:0] DMA_CTRL_ACL_EN = 32'h00000001 << DMA_CTRL_BIT_ACL_EN;
  localparam int unsigned DMA_CTRL_BIT_DNA_LOCK_EN = 8;
  localparam logic [31:0] DMA_CTRL_DNA_LOCK_EN = 32'h00000001 << DMA_CTRL_BIT_DNA_LOCK_EN;
  localparam int unsigned DMA_CTRL_BIT_SOFT_RESET = 10;
  localparam logic [31:0] DMA_CTRL_SOFT_RESET = 32'h00000001 << DMA_CTRL_BIT_SOFT_RESET;

  localparam int unsigned DMA_DESC_SIZE_BYTES = 32;
  localparam int unsigned DMA_DESC_WORD_BYTES = 4;

  localparam int unsigned DMA_DESC_DST_ADDR_BYTE_OFFSET = 0;
  localparam int unsigned DMA_DESC_SRC_ADDR_BYTE_OFFSET = 4;
  localparam int unsigned DMA_DESC_CTRL_LEN_ALGO_BYTE_OFFSET = 8;
  localparam int unsigned DMA_DESC_RESERVED0_BYTE_OFFSET = 12;
  localparam int unsigned DMA_DESC_CSW_BYTE_OFFSET = 16;
  localparam int unsigned DMA_DESC_ACTUAL_LEN_BYTE_OFFSET = 20;
  localparam int unsigned DMA_DESC_RESERVED2_BYTE_OFFSET = 24;
  localparam int unsigned DMA_DESC_RESERVED3_BYTE_OFFSET = 28;

  localparam int unsigned DMA_DESC_CTRL_BIT_STREAM_TLAST = 30;
  localparam logic [31:0] DMA_DESC_CTRL_STREAM_TLAST = 32'h00000001 << DMA_DESC_CTRL_BIT_STREAM_TLAST;
  localparam int unsigned DMA_DESC_CTRL_BIT_ALGO = 31;
  localparam logic [31:0] DMA_DESC_CTRL_ALGO = 32'h00000001 << DMA_DESC_CTRL_BIT_ALGO;
  localparam logic [31:0] DMA_DESC_CTRL_MASK_LEN = 32'h00FFFFFF;

  localparam int unsigned DMA_DESC_CSW_BIT_OWNER = 31;
  localparam logic [31:0] DMA_DESC_CSW_OWNER = 32'h00000001 << DMA_DESC_CSW_BIT_OWNER;
  localparam int unsigned DMA_DESC_CSW_BIT_DONE = 30;
  localparam logic [31:0] DMA_DESC_CSW_DONE = 32'h00000001 << DMA_DESC_CSW_BIT_DONE;
  localparam int unsigned DMA_DESC_CSW_BIT_ERR = 29;
  localparam logic [31:0] DMA_DESC_CSW_ERR = 32'h00000001 << DMA_DESC_CSW_BIT_ERR;
  localparam logic [31:0] DMA_DESC_CSW_MASK_STS = 32'h00000003;
  localparam logic [31:0] DMA_DESC_CSW_STS_MASK = DMA_DESC_CSW_MASK_STS;
  localparam logic [31:0] DMA_DESC_CSW_STS_OK = 32'h00000000;
  localparam logic [31:0] DMA_DESC_CSW_STS_AXI_RESP = 32'h00000001;
  localparam logic [31:0] DMA_DESC_CSW_STS_OVERFLOW_OR_MISSING_TLAST = 32'h00000002;
  localparam logic [31:0] DMA_DESC_CSW_STS_INTERNAL = 32'h00000003;

  localparam int unsigned DMA_CACHELINE_BYTES = 32;
  localparam int unsigned DMA_ALIGNMENT_BYTES = 32;
  localparam int unsigned DMA_RAW_COPY_LEN_MULTIPLE = 32;
  localparam int unsigned DMA_RAW_COPY_FIFO_DEPTH = 32;
  localparam string DMA_RAW_COPY_FIFO_MEMORY = "BRAM";
  localparam int unsigned DMA_RAW_COPY_TLAST_WIDTH = 1;

  localparam int unsigned DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_COUNT = 4;
  localparam string DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_0 = "TDATA";
  localparam string DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_1 = "TVALID";
  localparam string DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_2 = "TREADY";
  localparam string DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL_3 = "TLAST";

  typedef struct packed {
    logic [31:0] reserved3;
    logic [31:0] reserved2;
    logic [31:0] actual_len;
    logic [31:0] csw;
    logic [31:0] reserved0;
    logic [31:0] ctrl_len_algo;
    logic [31:0] src_addr;
    logic [31:0] dst_addr;
  } dma_desc_t;

  localparam int unsigned DMA_SUBMISSION_STEP_COUNT = 5;
  localparam string DMA_SUBMISSION_STEP_0 = "flush_desc_and_src";
  localparam string DMA_SUBMISSION_STEP_1 = "dsb";
  localparam string DMA_SUBMISSION_STEP_2 = "write_sw_tail";
  localparam string DMA_SUBMISSION_STEP_3 = "dsb";
  localparam string DMA_SUBMISSION_STEP_4 = "write_doorbell";

  localparam int unsigned DMA_VALIDATION_STEP_COUNT = 4;
  localparam string DMA_VALIDATION_STEP_0 = "poll_csw_success";
  localparam string DMA_VALIDATION_STEP_1 = "invalidate_dst";
  localparam string DMA_VALIDATION_STEP_2 = "dsb";
  localparam string DMA_VALIDATION_STEP_3 = "memcmp";

  localparam int unsigned DMA_SOFT_RESET_CLEAR_COUNT = 2;
  localparam string DMA_SOFT_RESET_CLEAR_0 = "dma_state_machine";
  localparam string DMA_SOFT_RESET_CLEAR_1 = "axis_fifo";

  localparam int unsigned DMA_SOFT_RESET_RETRY_REQUIREMENT_COUNT = 3;
  localparam string DMA_SOFT_RESET_RETRY_REQUIREMENT_0 = "fifo_empty";
  localparam string DMA_SOFT_RESET_RETRY_REQUIREMENT_1 = "s2mm_no_pending_beat";
  localparam string DMA_SOFT_RESET_RETRY_REQUIREMENT_2 = "fresh_csw_observation";

  localparam int unsigned DMA_IRQ_ENABLE_BIT_DONE = 0;
  localparam logic [31:0] DMA_IRQ_ENABLE_DONE = 32'h00000001 << DMA_IRQ_ENABLE_BIT_DONE;
  localparam int unsigned DMA_IRQ_STATUS_BIT_DONE_PENDING = 0;
  localparam logic [31:0] DMA_IRQ_STATUS_DONE_PENDING = 32'h00000001 << DMA_IRQ_STATUS_BIT_DONE_PENDING;
  localparam int unsigned DMA_IRQ_ACK_BIT_DONE_ACK = 0;
  localparam logic [31:0] DMA_IRQ_ACK_DONE_ACK = 32'h00000001 << DMA_IRQ_ACK_BIT_DONE_ACK;

  localparam int unsigned DMA_IRQ_DEFAULT_COALESCE_COUNT = 8;
  localparam int unsigned DMA_IRQ_DEFAULT_COALESCE_TIMEOUT_CYCLES = 5000;

  localparam int unsigned DMA_IRQ_COMPLETION_EVENT_REQUIREMENT_COUNT = 3;
  localparam string DMA_IRQ_COMPLETION_EVENT_REQUIREMENT_0 = "payload_wb_b_handshake_complete";
  localparam string DMA_IRQ_COMPLETION_EVENT_REQUIREMENT_1 = "actual_len_wb_b_handshake_complete";
  localparam string DMA_IRQ_COMPLETION_EVENT_REQUIREMENT_2 = "csw_wb_b_handshake_complete";

endpackage
