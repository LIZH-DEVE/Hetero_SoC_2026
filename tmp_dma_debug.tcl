run 50 us
puts "TIME=[current_time]"
puts "rx_wr_valid=[examine rx_wr_valid] rx_wr_ready=[examine rx_wr_ready]"
puts "auth_tvalid=[examine dut.auth_tvalid] auth_tready=[examine dut.auth_tready]"
puts "ingress_tvalid=[examine dut.ingress_tvalid] ingress_tready=[examine dut.ingress_tready]"
puts "aclf_tvalid=[examine dut.aclf_tvalid] pbm_wr_ready=[examine dut.pbm_wr_ready]"
puts "acl_hit_count=[examine dut.acl_hit_count] acl_miss_count=[examine dut.acl_miss_count]"
puts "pbm_write_beat_count=[examine pbm_write_beat_count] drop_pulses=[examine acl_drop_pulse_count]"
puts "buffer_usage=[examine dut.u_pbm.o_buffer_usage] rollback=[examine dut.u_pbm.o_rollback_active]"
puts "auth_en=[examine dut.auth_en] acl_en=[examine dut.acl_en]"
puts "auth_acl_state=[examine dut.auth_acl_state]"
quit
