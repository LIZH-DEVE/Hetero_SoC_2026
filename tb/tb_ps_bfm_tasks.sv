package tb_ps_bfm_tasks_pkg;
  import dma_csr_pkg::*;

  typedef logic [31:0] dma_word_t;
  typedef dma_word_t dma_word_mem_t[longint unsigned];

  task automatic dma_bfm_ring_init(
    ref dma_word_mem_t csr_space,
    input logic [31:0] ring_base_addr,
    input logic [31:0] ring_size
  );
    csr_space[DMA_CSR_RING_BASE >> 2] = ring_base_addr;
    csr_space[DMA_CSR_RING_SIZE >> 2] = ring_size;
    csr_space[DMA_CSR_RING_HW_HEAD >> 2] = '0;
    csr_space[DMA_CSR_RING_SW_TAIL >> 2] = '0;
    csr_space[DMA_CSR_RING_DOORBELL >> 2] = '0;
  endtask

  task automatic dma_bfm_publish_tail(
    ref dma_word_mem_t csr_space,
    input logic [31:0] sw_tail
  );
    csr_space[DMA_CSR_RING_SW_TAIL >> 2] = sw_tail;
  endtask

  task automatic dma_bfm_submit_raw_copy(
    ref dma_word_mem_t csr_space,
    ref dma_word_mem_t ddr_words,
    input logic [31:0] desc_base_addr,
    input logic [31:0] src_addr,
    input logic [31:0] dst_addr,
    input logic [31:0] len_bytes,
    input logic [31:0] sw_tail
  );
    longint unsigned desc_word_base;
    logic [31:0] ctrl_word;
    begin
      if ((len_bytes % DMA_RAW_COPY_LEN_MULTIPLE) != 0) begin
        $fatal(1, "dma_bfm_submit_raw_copy len_bytes=0x%08x is not %0d-byte aligned",
               len_bytes, DMA_RAW_COPY_LEN_MULTIPLE);
      end
      desc_word_base = desc_base_addr >> 2;
      ctrl_word = len_bytes & DMA_DESC_CTRL_MASK_LEN;
      ddr_words[desc_word_base + (DMA_DESC_DST_ADDR_BYTE_OFFSET >> 2)] = dst_addr;
      ddr_words[desc_word_base + (DMA_DESC_SRC_ADDR_BYTE_OFFSET >> 2)] = src_addr;
      ddr_words[desc_word_base + (DMA_DESC_CTRL_LEN_ALGO_BYTE_OFFSET >> 2)] = ctrl_word;
      ddr_words[desc_word_base + (DMA_DESC_RESERVED0_BYTE_OFFSET >> 2)] = 32'h0;
      ddr_words[desc_word_base + (DMA_DESC_CSW_BYTE_OFFSET >> 2)] = DMA_DESC_CSW_OWNER;
        ddr_words[desc_word_base + (DMA_DESC_ACTUAL_LEN_BYTE_OFFSET >> 2)] = 32'h0;
      ddr_words[desc_word_base + (DMA_DESC_RESERVED2_BYTE_OFFSET >> 2)] = 32'h0;
      ddr_words[desc_word_base + (DMA_DESC_RESERVED3_BYTE_OFFSET >> 2)] = 32'h0;
      dma_bfm_publish_tail(csr_space, sw_tail);
      dma_bfm_ring_doorbell(csr_space);
    end
  endtask

  task automatic dma_bfm_ring_doorbell(
    ref dma_word_mem_t csr_space,
    input logic [31:0] doorbell_value = DMA_CSR_RING_DOORBELL_KICK
  );
    csr_space[DMA_CSR_RING_DOORBELL >> 2] = doorbell_value;
  endtask

  task automatic dma_bfm_poll_csw_done(
    ref dma_word_mem_t ddr_words,
    input logic [31:0] desc_base_addr,
    output logic [31:0] csw_value,
    input int unsigned max_polls = 1024
  );
    longint unsigned csw_index;
    int unsigned poll_count;
    logic [31:0] sts_value;
    logic err_seen;
    begin
      csw_index = (desc_base_addr + DMA_DESC_CSW_BYTE_OFFSET) >> 2;
      csw_value = '0;
      for (poll_count = 0; poll_count < max_polls; poll_count++) begin
        csw_value = ddr_words[csw_index];
        err_seen = ((csw_value & DMA_DESC_CSW_ERR) != 32'h0);
        sts_value = (csw_value & DMA_DESC_CSW_MASK_STS);
        if (((csw_value & DMA_DESC_CSW_OWNER) == 32'h0) &&
            ((csw_value & DMA_DESC_CSW_DONE) != 32'h0)) begin
          return;
        end
      end
      $fatal(1,
             "dma_bfm_poll_csw_done timeout desc_base=0x%08x csw=0x%08x err=%0d sts=0x%08x",
             desc_base_addr,
             csw_value,
             err_seen,
             sts_value);
    end
  endtask

  task automatic dma_bfm_validate_raw_copy(
    ref dma_word_mem_t ddr_words,
    input logic [31:0] src_addr,
    input logic [31:0] dst_addr,
    input logic [31:0] len_bytes
  );
    longint unsigned src_word_base;
    longint unsigned dst_word_base;
    int unsigned word_count;
    int unsigned word_idx;
    begin
      if ((len_bytes % DMA_RAW_COPY_LEN_MULTIPLE) != 0) begin
        $fatal(1, "dma_bfm_validate_raw_copy len_bytes=0x%08x is not %0d-byte aligned",
               len_bytes, DMA_RAW_COPY_LEN_MULTIPLE);
      end
      src_word_base = src_addr >> 2;
      dst_word_base = dst_addr >> 2;
      word_count = len_bytes / DMA_DESC_WORD_BYTES;
      for (word_idx = 0; word_idx < word_count; word_idx++) begin
        if (ddr_words[src_word_base + word_idx] !== ddr_words[dst_word_base + word_idx]) begin
          $fatal(1,
                 "dma_bfm_validate_raw_copy mismatch idx=%0d src=0x%08x dst=0x%08x",
                 word_idx,
                 ddr_words[src_word_base + word_idx],
                 ddr_words[dst_word_base + word_idx]);
        end
      end
    end
  endtask

  task automatic dma_bfm_soft_reset_clean_retry(
    ref dma_word_mem_t csr_space,
    ref dma_word_mem_t ddr_words,
    input logic [31:0] desc_base_addr,
    input logic [31:0] sw_tail
  );
    longint unsigned csw_index;
    begin
      csw_index = (desc_base_addr + DMA_DESC_CSW_BYTE_OFFSET) >> 2;
      csr_space[DMA_CSR_CTRL >> 2] = DMA_CTRL_SOFT_RESET;
      csr_space[DMA_CSR_CTRL >> 2] = 32'h0;
      ddr_words[csw_index] = DMA_DESC_CSW_OWNER;
      dma_bfm_publish_tail(csr_space, sw_tail);
      dma_bfm_ring_doorbell(csr_space);
    end
  endtask

endpackage
