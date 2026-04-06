DMA gateway hybrid perf proof image

Purpose:
- Stage 2 SG proof image for the hybrid DMA/crypto path.
- Freezes the PS-side single-launch descriptor contract before merge-back into shadow_mirror BENCH.
- Uses 1000 repeats by default to amortize launch overhead on short packets.

Current contract:
- single-launch SG batch
- one published sw_tail per batch
- one doorbell per batch
- last descriptor polling for timed completion

Current status:
- The hybrid crypto DMA subsystem now has a descriptor-driven source reader wired into the crypto input path.
- This image now emits UART benchmark rows for AES/SM4 across 16/32/128/512/1472-byte payloads.
- It still needs a rebuilt bitstream and real board capture before Stage 2 can claim AES/SM4 crossover.

Expected UART pass criteria:
- PROOF_AES PASS
- PROOF_SM4 PASS
- DMA gateway hybrid perf proof PASS

Expected artifacts:
- board_bench_report.json
- board_bench_summary.md
