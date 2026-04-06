# Zero-Copy FastPath Egress Step 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose a real `tx_axis_*` egress from `dma_gateway_hybrid_board_wrapper`, wire it to `crypto_dma_subsystem`, and keep the path alive through the shadow-mirror export flow.

**Architecture:** This step is intentionally limited to interface exposure and build-flow synchronization. It does not yet reroute `FastPath` hit traffic away from `TXCAP`; it only creates the physical egress path, propagates external `tready`, and updates the export flow so Vivado BD refresh can see and preserve the new ports.

**Tech Stack:** SystemVerilog, Verilog, Vivado BD/module_ref flow, Python `unittest`, PowerShell/Tcl export scripts.

---

## File Map

- Modify: `rtl/top/dma_gateway_hybrid_board_wrapper.v`
- Modify: `HCS_SOC/export_udp_gateway_shadow_mirror_xsa.tcl`
- Modify: `tests/test_dma_gateway_hybrid_contracts.py`
- Modify: `tests/test_udp_gateway_shadow_mirror_release.py`

### Task 1: Write Failing Contract Tests For Real TX Egress Exposure

**Files:**
- Modify: `tests/test_dma_gateway_hybrid_contracts.py`
- Modify: `tests/test_udp_gateway_shadow_mirror_release.py`
- Test: `tests/test_dma_gateway_hybrid_contracts.py`
- Test: `tests/test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Add a failing wrapper contract for top-level TX egress ports**

Add assertions to `tests/test_dma_gateway_hybrid_contracts.py` that require:

```python
for token in (
    "output wire [31:0]             o_tx_axis_tdata",
    "output wire                    o_tx_axis_tvalid",
    "output wire                    o_tx_axis_tlast",
    "output wire [3:0]              o_tx_axis_tkeep",
    "input  wire                    i_tx_axis_tready",
    "wire [31:0]                    fastpath_tx_axis_tdata;",
    "wire                           fastpath_tx_axis_tvalid;",
    "wire                           fastpath_tx_axis_tlast;",
    "wire [3:0]                     fastpath_tx_axis_tkeep;",
    ".tx_axis_tdata(fastpath_tx_axis_tdata)",
    ".tx_axis_tvalid(fastpath_tx_axis_tvalid)",
    ".tx_axis_tlast(fastpath_tx_axis_tlast)",
    ".tx_axis_tkeep(fastpath_tx_axis_tkeep)",
    ".tx_axis_tready(i_tx_axis_tready)",
    "assign o_tx_axis_tdata = fastpath_tx_axis_tdata;",
    "assign o_tx_axis_tvalid = fastpath_tx_axis_tvalid;",
    "assign o_tx_axis_tlast = fastpath_tx_axis_tlast;",
    "assign o_tx_axis_tkeep = fastpath_tx_axis_tkeep;",
):
    self.assertIn(token, text)
```

- [ ] **Step 2: Add a failing export-flow contract for BD refresh support**

Add assertions to `tests/test_udp_gateway_shadow_mirror_release.py` that require:

```python
for token in (
    "open_bd_design $raw_bd",
    "validate_bd_design",
    "save_bd_design",
    "generate_target all $raw_bd_obj",
    "export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet",
):
    self.assertIn(token, export_tcl)
```

and require at least one explicit TX externalization hook marker that we will add:

```python
self.assertIn("ZERO_COPY_FASTPATH_EGRESS_STEP1", export_tcl)
```

- [ ] **Step 3: Run the targeted tests and verify they fail for the right reason**

Run:

```powershell
py -3 -m unittest tests.test_dma_gateway_hybrid_contracts tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:

- failure in `test_hybrid_wrapper_uses_stage1_classifier_and_crypto_dma_windows`
- failure in the new release-contract assertion for `ZERO_COPY_FASTPATH_EGRESS_STEP1`

- [ ] **Step 4: Commit after the failing test is observed**

```powershell
git add tests/test_dma_gateway_hybrid_contracts.py tests/test_udp_gateway_shadow_mirror_release.py
git commit -m "test: add zero-copy fastpath egress step1 contracts"
```

### Task 2: Expose Real TX Egress Ports In The Wrapper

**Files:**
- Modify: `rtl/top/dma_gateway_hybrid_board_wrapper.v`
- Test: `tests/test_dma_gateway_hybrid_contracts.py`

- [ ] **Step 1: Add real top-level TX egress ports to the wrapper module**

In `rtl/top/dma_gateway_hybrid_board_wrapper.v`, add:

```verilog
    output wire [31:0]             o_tx_axis_tdata,
    output wire                    o_tx_axis_tvalid,
    output wire                    o_tx_axis_tlast,
    output wire [3:0]              o_tx_axis_tkeep,
    input  wire                    i_tx_axis_tready,
```

Place them after the AXI fetcher interface block so the board wrapper now has a real external TX path.

- [ ] **Step 2: Add internal wires for the `crypto_dma_subsystem` egress**

Add:

```verilog
    wire [31:0]                    fastpath_tx_axis_tdata;
    wire                           fastpath_tx_axis_tvalid;
    wire                           fastpath_tx_axis_tlast;
    wire [3:0]                     fastpath_tx_axis_tkeep;
```

- [ ] **Step 3: Replace the discarded subsystem TX connection with real wiring**

Replace:

```verilog
        .tx_axis_tdata(),
        .tx_axis_tvalid(),
        .tx_axis_tlast(),
        .tx_axis_tkeep(),
        .tx_axis_tready(1'b0),
```

with:

```verilog
        .tx_axis_tdata(fastpath_tx_axis_tdata),
        .tx_axis_tvalid(fastpath_tx_axis_tvalid),
        .tx_axis_tlast(fastpath_tx_axis_tlast),
        .tx_axis_tkeep(fastpath_tx_axis_tkeep),
        .tx_axis_tready(i_tx_axis_tready),
```

- [ ] **Step 4: Export the subsystem TX path directly to the new wrapper ports**

Add:

```verilog
    assign o_tx_axis_tdata = fastpath_tx_axis_tdata;
    assign o_tx_axis_tvalid = fastpath_tx_axis_tvalid;
    assign o_tx_axis_tlast = fastpath_tx_axis_tlast;
    assign o_tx_axis_tkeep = fastpath_tx_axis_tkeep;
```

This step does not yet change the `FastPath` hit route. It only makes the egress physically present and backpressure-reachable.

- [ ] **Step 5: Run targeted tests and verify they pass**

Run:

```powershell
py -3 -m unittest tests.test_dma_gateway_hybrid_contracts -v
```

Expected:

- wrapper contract test passes

- [ ] **Step 6: Commit the wrapper port exposure**

```powershell
git add rtl/top/dma_gateway_hybrid_board_wrapper.v tests/test_dma_gateway_hybrid_contracts.py
git commit -m "feat: expose real zero-copy fastpath tx egress ports"
```

### Task 3: Keep The Path Alive Through The Shadow-Mirror Export Flow

**Files:**
- Modify: `HCS_SOC/export_udp_gateway_shadow_mirror_xsa.tcl`
- Test: `tests/test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Mark and preserve the BD refresh point for the new module_ref ports**

In `HCS_SOC/export_udp_gateway_shadow_mirror_xsa.tcl`, add a comment marker:

```tcl
# ZERO_COPY_FASTPATH_EGRESS_STEP1: refresh module_ref ports after wrapper TX egress exposure
```

Place it immediately before the `open_bd_design $raw_bd` / `validate_bd_design` / `save_bd_design` sequence that regenerates the cloned shadow design.

- [ ] **Step 2: Force a fresh wrapper generation after BD validation**

Keep and rely on this path:

```tcl
validate_bd_design
save_bd_design
generate_target all $raw_bd_obj
export_ip_user_files -of_objects $raw_bd_obj -sync -force -quiet
...
set wrapper_files [make_wrapper -files $raw_bd_obj -top -force]
```

This step is successful only if the module_ref refresh path remains explicit and the regenerated wrapper sees the new top-level TX ports.

- [ ] **Step 3: Run release-contract tests and verify they pass**

Run:

```powershell
py -3 -m unittest tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:

- release-contract tests pass

- [ ] **Step 4: Commit the export-flow sync update**

```powershell
git add HCS_SOC/export_udp_gateway_shadow_mirror_xsa.tcl tests/test_udp_gateway_shadow_mirror_release.py
git commit -m "build: refresh shadow export flow for tx egress exposure"
```

### Task 4: Verify The Step 1 Increment

**Files:**
- Modify: none
- Test: `tests/test_dma_gateway_hybrid_contracts.py`
- Test: `tests/test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Run the combined repository checks**

Run:

```powershell
py -3 -m unittest tests.test_dma_gateway_hybrid_contracts tests.test_udp_gateway_shadow_mirror_release -v
```

Expected:

- all tests pass

- [ ] **Step 2: Run a lightweight export dry-run if available**

Run:

```powershell
$env:UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN = "1"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\HCS_SOC\export_udp_gateway_shadow_mirror_xsa.ps1
Remove-Item Env:\UDP_GATEWAY_SHADOW_MIRROR_EXPORT_DRY_RUN
```

Expected:

- the export script reaches the dry-run path without immediate module_ref sync failure

- [ ] **Step 3: Commit the verified Step 1 state**

```powershell
git add .
git commit -m "chore: complete zero-copy fastpath egress step1"
```

