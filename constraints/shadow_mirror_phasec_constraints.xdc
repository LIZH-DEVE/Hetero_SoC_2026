# Phase C shadow_mirror implementation constraints
# Keep this file to pure XDC syntax. Vivado's XDC parser does not support
# general Tcl control flow.

# Restore timing visibility for the divided device-DNA shift clock.
create_generated_clock \
  -name shadow_dna_clk \
  -source [get_pins udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/dna_clk_reg/C] \
  -divide_by 32 \
  [get_pins udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/dna_clk_reg/Q]

# Preserve synchronizer intent on the DNA completion crossing.
set_property ASYNC_REG TRUE \
  [get_cells -hierarchical -quiet -filter {NAME =~ */u_device_dna_reader/dna_done_sync_ff* && IS_SEQUENTIAL}]

# Floorplan the three dominant islands by resource band:
# 1) live crypto compute island in the top slice band
# 2) shadow datapath island across the bottom full-width band plus the middle BRAM-adjacent band
# 3) shadow service island in the narrow middle-right control pocket

create_pblock live_crypto_region
add_cells_to_pblock [get_pblocks live_crypto_region] [get_cells -quiet [list \
  udp_gateway_shadow_mirror_i/crypto_accel_axi_0/inst \
]]
resize_pblock [get_pblocks live_crypto_region] -add { \
  SLICE_X24Y99:SLICE_X113Y149 \
}
set_property IS_SOFT TRUE [get_pblocks live_crypto_region]

create_pblock shadow_data_region
add_cells_to_pblock [get_pblocks shadow_data_region] [get_cells -quiet [list \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/i_hybrid_dma \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_shadow_acl_filter \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_classifier \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_ctrl_csr.u_shadow_ctrl_csr \
]]
add_cells_to_pblock [get_pblocks shadow_data_region] [get_cells -quiet -hierarchical -filter {NAME =~ udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata*}]
resize_pblock [get_pblocks shadow_data_region] -add { \
  SLICE_X0Y0:SLICE_X113Y49 \
  SLICE_X26Y50:SLICE_X95Y98 \
  RAMB36_X3Y0:RAMB36_X5Y11 \
}
set_property IS_SOFT TRUE [get_pblocks shadow_data_region]

create_pblock shadow_ctrl_region
add_cells_to_pblock [get_pblocks shadow_ctrl_region] [get_cells -quiet [list \
  udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/gen_shadow_inject_only.u_shadow_inject \
]]
add_cells_to_pblock [get_pblocks shadow_ctrl_region] [get_cells -quiet -hierarchical -filter {NAME =~ udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/* && NAME !~ udp_gateway_shadow_mirror_i/dma_gateway_hybrid_0/inst/u_device_dna_reader/s_axil_rdata*}]
resize_pblock [get_pblocks shadow_ctrl_region] -add { \
  SLICE_X96Y50:SLICE_X113Y98 \
  RAMB18_X3Y24:RAMB18_X3Y31 \
}
set_property IS_SOFT TRUE [get_pblocks shadow_ctrl_region]
