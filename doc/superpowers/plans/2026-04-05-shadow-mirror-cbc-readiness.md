# Shadow Mirror CBC Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the active `udp_gateway_shadow_mirror_wrapper` datapath packet-aware enough to support a real CBC mode later, without pretending that the current block-only crypto path already satisfies CBC requirements.

**Architecture:** Do not wire CBC directly into the current active bridge. First introduce a packet-aware admission/staging layer, define an in-band IV contract, and enforce packet-level backpressure so CBC can serialize blocks within a packet without deadlocking the upstream DMA/PBM path. Only after those foundations exist should CBC XOR/chaining logic be added to the active crypto path.

**Tech Stack:** SystemVerilog RTL, PowerShell board scripts, Python host control/data-plane helpers, Python `unittest`.

---

## File Structure

**Create:**
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_shadow_mirror_cbc_readiness_contracts.py`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\shadow_mirror_cbc_architecture_notes.md`

**Modify:**
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\udp_dma_ingress_classifier.sv`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\top\crypto_dma_subsystem.sv`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\crypto\crypto_bridge_top.sv`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\udp_crypto_control.py`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\handoff\robeieda_porting_pack\tools\udp_crypto_control.py`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\handoff\robeieda_porting_pack\tools\send_udp_crypto_test.py`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_runtime_contracts.py`
- `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`

**Why these files:**
- `udp_dma_ingress_classifier.sv` is the earliest active point that still knows packet boundaries and UDP length.
- `crypto_dma_subsystem.sv` is where packet metadata must be carried into the active crypto datapath.
- `crypto_bridge_top.sv` is the current active block cruncher and must become packet-aware before CBC can be real.
- Host control/data helpers must define the on-wire CBC packet format and validation behavior.
- New and existing tests must lock the packet/IV/backpressure contract before RTL changes.

## CBC Readiness Contract

1. **CBC packet format is in-band.**
   - Packet payload format is fixed as:
   - `IV[16B] + DATA[16B * N]`
   - `N >= 1`
   - AXI-Lite per-packet IV programming is forbidden.

2. **Tail blocks are not supported in Phase 1.**
   - No padding hardware.
   - No `TKEEP`-based partial block handling.
   - A packet is rejected if `(udp_payload_bytes - 16) % 16 != 0`.

3. **CBC mode is packet-atomic.**
   - One active CBC packet at a time per crypto instance.
   - The next packet is not admitted until the current packet completes.
   - Backpressure propagates to the classifier when packet staging is occupied.

4. **Performance reporting must split ECB-style aggregate throughput from CBC single-flow throughput.**
   - CBC single-flow theoretical ceiling:
   - `T_single_flow_max = (16 bytes * f_clk) / C_block`
   - Do not reuse current ECB-style benchmark claims as CBC claims.

## Task 1: Lock the Readiness Contract in Tests

**Files:**
- Create: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_shadow_mirror_cbc_readiness_contracts.py`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_runtime_contracts.py`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Write the failing readiness tests**

```python
import pathlib
import unittest


REPO = pathlib.Path(r"D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026")
CLASSIFIER = REPO / "rtl/core/dma/udp_dma_ingress_classifier.sv"
SUBSYSTEM = REPO / "rtl/top/crypto_dma_subsystem.sv"
BRIDGE = REPO / "rtl/core/crypto/crypto_bridge_top.sv"


class TestShadowMirrorCBCReadinessContracts(unittest.TestCase):
    def test_classifier_exposes_cbc_packet_length_guard(self):
        text = CLASSIFIER.read_text(encoding="utf-8")
        self.assertIn("CBC payload requires a 16-byte IV plus 16-byte aligned data", text)
        self.assertIn("o_drop_cbc_length_invalid_count", text)

    def test_subsystem_carries_packet_metadata_into_bridge(self):
        text = SUBSYSTEM.read_text(encoding="utf-8")
        self.assertIn("bridge_pkt_start", text)
        self.assertIn("bridge_pkt_end", text)
        self.assertIn("bridge_pkt_cbc_mode", text)

    def test_bridge_declares_packet_atomic_cbc_mode(self):
        text = BRIDGE.read_text(encoding="utf-8")
        self.assertIn("CBC mode is packet-atomic on the active shadow path", text)
        self.assertIn("cbc_pkt_active", text)
        self.assertIn("cbc_iv_header", text)
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts -v
```

Expected:
- `FAIL`
- Missing `o_drop_cbc_length_invalid_count`
- Missing packet metadata names
- Missing packet-atomic CBC markers in the bridge

- [ ] **Step 3: Extend existing runtime/release contracts to require the new packet contract**

Add checks like:

```python
self.assertIn("IV[16B] + DATA[16B * N]", notes_text)
self.assertIn("CBC single-flow theoretical ceiling", notes_text)
self.assertIn("No AXI-Lite per-packet IV programming", notes_text)
```

- [ ] **Step 4: Run the focused contract suite**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts tests.test_udp_gateway_shadow_runtime_contracts tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:
- `FAIL`
- Only CBC-readiness contract assertions fail

- [ ] **Step 5: Commit**

```powershell
git add tests/test_shadow_mirror_cbc_readiness_contracts.py tests/test_udp_gateway_shadow_runtime_contracts.py tests/test_udp_gateway_shadow_mirror_release.py
git commit -m "test: lock shadow mirror CBC readiness contracts"
```

## Task 2: Add Packet-Aware Metadata to the Active Ingress Path

**Files:**
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\dma\udp_dma_ingress_classifier.sv`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\top\crypto_dma_subsystem.sv`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_shadow_mirror_cbc_readiness_contracts.py`

- [ ] **Step 1: Extend the failing test for packet metadata ports**

```python
self.assertIn("output logic                  m_axis_dma_pkt_start", text)
self.assertIn("output logic                  m_axis_dma_pkt_end", text)
self.assertIn("output logic                  m_axis_dma_cbc_mode", text)
self.assertIn("output logic [127:0]          m_axis_dma_iv_header", text)
```

- [ ] **Step 2: Run the specific test and verify it fails**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts.TestShadowMirrorCBCReadinessContracts.test_classifier_exposes_cbc_packet_length_guard -v
```

Expected:
- `FAIL`
- Port names or contract comments absent

- [ ] **Step 3: Modify the classifier to detect CBC packets and reject invalid CBC length**

Implementation requirements:

```systemverilog
// CBC payload requires a 16-byte IV plus 16-byte aligned data.
// Drop if payload_bytes < 16 or if (payload_bytes - 16) is not 16-byte aligned.
output logic                  m_axis_dma_pkt_start,
output logic                  m_axis_dma_pkt_end,
output logic                  m_axis_dma_cbc_mode,
output logic [127:0]          m_axis_dma_iv_header,
output logic [31:0]           o_drop_cbc_length_invalid_count
```

Rules:
- `pkt_start` marks the first accepted payload beat of a packet.
- `pkt_end` marks the accepted `TLAST`.
- `cbc_mode` is asserted only when the packet format matches `IV + aligned data`.
- `iv_header` is assembled from the first 4 accepted payload beats.
- Invalid CBC packet length increments `o_drop_cbc_length_invalid_count` and drops the packet before DMA admission.

- [ ] **Step 4: Modify the subsystem to preserve the metadata into the bridge**

Implementation requirements:

```systemverilog
logic         bridge_pkt_start;
logic         bridge_pkt_end;
logic         bridge_pkt_cbc_mode;
logic [127:0] bridge_iv_header;
```

Wire the classifier outputs into these signals and then into the bridge instance.

- [ ] **Step 5: Run the focused tests**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts -v
```

Expected:
- `PASS`

- [ ] **Step 6: Commit**

```powershell
git add rtl/core/dma/udp_dma_ingress_classifier.sv rtl/top/crypto_dma_subsystem.sv tests/test_shadow_mirror_cbc_readiness_contracts.py
git commit -m "feat: add CBC packet metadata to active ingress path"
```

## Task 3: Make the Active Bridge Packet-Aware Before CBC Logic

**Files:**
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\rtl\core\crypto\crypto_bridge_top.sv`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_shadow_mirror_cbc_readiness_contracts.py`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_runtime_contracts.py`

- [ ] **Step 1: Write the failing bridge packet-atomic tests**

```python
self.assertIn("cbc_pkt_active", text)
self.assertIn("cbc_pkt_block_count", text)
self.assertIn("cbc_pkt_done", text)
self.assertIn("CBC mode is packet-atomic on the active shadow path", text)
```

- [ ] **Step 2: Run the bridge contract test to verify it fails**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts.TestShadowMirrorCBCReadinessContracts.test_bridge_declares_packet_atomic_cbc_mode -v
```

Expected:
- `FAIL`

- [ ] **Step 3: Add packet-aware staging and admission state to the bridge**

Implementation requirements:

```systemverilog
logic         cbc_pkt_active;
logic [7:0]   cbc_pkt_block_count;
logic [127:0] cbc_iv_header;
logic         cbc_pkt_done;
```

Rules:
- The bridge may not admit a second CBC packet while `cbc_pkt_active` is asserted.
- The bridge must treat CBC mode as packet-atomic, not block-atomic.
- No CBC XOR/chaining datapath is added in this task.
- This task only establishes packet-level admission, state lifetime, and backpressure.

- [ ] **Step 4: Gate upstream reads with packet-level availability**

Implementation requirements:

```systemverilog
// Do not admit a new CBC packet until the current CBC packet fully drains.
assign cbc_can_admit_pkt = !cbc_pkt_active && packet_staging_has_capacity;
```

Ensure this gate ultimately suppresses `o_pbm_rd_en` when a CBC packet is already active and staging cannot accept another packet.

- [ ] **Step 5: Run the bridge/runtime tests**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts tests.test_udp_gateway_shadow_runtime_contracts -v
```

Expected:
- `PASS`

- [ ] **Step 6: Commit**

```powershell
git add rtl/core/crypto/crypto_bridge_top.sv tests/test_shadow_mirror_cbc_readiness_contracts.py tests/test_udp_gateway_shadow_runtime_contracts.py
git commit -m "feat: make active crypto bridge packet-aware for CBC"
```

## Task 4: Define the Host-Side CBC Packet Contract

**Files:**
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\udp_crypto_control.py`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\handoff\robeieda_porting_pack\tools\udp_crypto_control.py`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\handoff\robeieda_porting_pack\tools\send_udp_crypto_test.py`
- Create: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\doc\reports\shadow_mirror_cbc_architecture_notes.md`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Write the failing host contract tests**

```python
self.assertIn("IV[16B] + DATA[16B * N]", text)
self.assertIn("No AXI-Lite per-packet IV programming", text)
self.assertIn("CBC single-flow theoretical ceiling", text)
```

- [ ] **Step 2: Run the host contract test to verify it fails**

Run:

```powershell
py -3 -m unittest tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:
- `FAIL`

- [ ] **Step 3: Add host-side packet format helpers**

Implementation requirements:

```python
def pack_cbc_payload(iv: bytes, data: bytes) -> bytes:
    if len(iv) != 16:
        raise ValueError("CBC IV must be 16 bytes")
    if len(data) == 0 or (len(data) % 16) != 0:
        raise ValueError("CBC data must be a non-empty multiple of 16 bytes")
    return iv + data
```

Document that this is the only supported Phase 1 on-wire CBC format.

- [ ] **Step 4: Write the architecture note**

The note must include:
- `IV[16B] + DATA[16B * N]`
- `No AXI-Lite per-packet IV programming`
- `CBC mode is packet-atomic on the active path`
- `T_single_flow_max = (16 bytes * f_clk) / C_block`

- [ ] **Step 5: Run the host/release tests**

Run:

```powershell
py -3 -m unittest tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:
- `PASS`

- [ ] **Step 6: Commit**

```powershell
git add HCS_SOC/udp_crypto_control.py handoff/robeieda_porting_pack/tools/udp_crypto_control.py handoff/robeieda_porting_pack/tools/send_udp_crypto_test.py doc/reports/shadow_mirror_cbc_architecture_notes.md tests/test_udp_gateway_shadow_mirror_release.py
git commit -m "docs: define shadow mirror CBC packet contract"
```

## Task 5: Verification Gate Before Any Real CBC XOR/Chaining RTL

**Files:**
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_shadow_mirror_cbc_readiness_contracts.py`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_runtime_contracts.py`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Run the full readiness suite**

Run:

```powershell
py -3 -m unittest tests.test_shadow_mirror_cbc_readiness_contracts tests.test_udp_gateway_shadow_runtime_contracts tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:
- `PASS`

- [ ] **Step 2: Run existing active-path contract tests**

Run:

```powershell
py -3 -m unittest tests.test_dma_gateway_hybrid_contracts tests.test_shadow_routability_contracts tests.test_shadow_fastpath_txcap_storage_contracts -v
```

Expected:
- `PASS`

- [ ] **Step 3: Record the readiness decision**

Update the architecture note with:
- packet staging present: `yes/no`
- in-band IV contract present: `yes/no`
- packet-atomic backpressure present: `yes/no`
- real CBC XOR/chaining enabled: `no`

- [ ] **Step 4: Commit**

```powershell
git add tests/test_shadow_mirror_cbc_readiness_contracts.py tests/test_udp_gateway_shadow_runtime_contracts.py tests/test_udp_gateway_shadow_mirror_release.py doc/reports/shadow_mirror_cbc_architecture_notes.md
git commit -m "test: gate CBC RTL on packet-aware readiness"
```

## Spec Coverage Review

- `Packet boundary physicalization`: covered by Task 2 and Task 3.
- `IV in-band path, not AXI-Lite`: covered by Task 4.
- `Same-flow serialization and backpressure`: covered by Task 3.
- `Single-flow throughput ceiling`: covered by Task 4 and Task 5.
- `No tail-block padding in Phase 1`: covered by Task 2 and Task 4.

## Placeholder Scan

- No `TODO`, `TBD`, or “implement later” markers remain.
- Each task names exact files and exact commands.
- The plan intentionally stops before real CBC XOR/chaining RTL. That stop is deliberate, not a placeholder.

## Type Consistency

- Packet metadata names are consistently:
  - `pkt_start`
  - `pkt_end`
  - `cbc_mode`
  - `iv_header`
- Bridge packet state names are consistently:
  - `cbc_pkt_active`
  - `cbc_pkt_block_count`
  - `cbc_pkt_done`

## Execution Handoff

Plan complete and saved to `doc/superpowers/plans/2026-04-05-shadow-mirror-cbc-readiness.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
