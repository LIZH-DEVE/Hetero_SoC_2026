# Delivery Repo Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the repository into a handoff-ready, GitHub-shareable layout without changing the active shadow-mirror build path.

**Architecture:** Keep the active shadow-mirror code and Vivado project roots stable, then move only logs, scratch files, temp workdirs, and historical non-active project families into explicit `archive/` and `legacy/` trees. Update the repository structure docs and layout tests to match the new organization.

**Tech Stack:** PowerShell, Git, Markdown docs, Python unittest

---

### Task 1: Create delivery archive and legacy roots

**Files:**
- Create: `legacy/`
- Create: `legacy/root_projects/`
- Create: `legacy/root_tools/`
- Create: `archive/root_temp_workdirs/`
- Create: `HCS_SOC/legacy/`
- Create: `HCS_SOC/legacy/apps/`
- Create: `HCS_SOC/legacy/platforms/`
- Create: `HCS_SOC/legacy/sd_boot/`
- Create: `HCS_SOC/legacy/artifacts/`

- [ ] **Step 1: Create the directory roots**

Run:

```powershell
New-Item -ItemType Directory -Force -Path `
  'legacy', `
  'legacy/root_projects', `
  'legacy/root_tools', `
  'archive/root_temp_workdirs', `
  'HCS_SOC/legacy', `
  'HCS_SOC/legacy/apps', `
  'HCS_SOC/legacy/platforms', `
  'HCS_SOC/legacy/sd_boot', `
  'HCS_SOC/legacy/artifacts' | Out-Null
```

- [ ] **Step 2: Verify the roots exist**

Run:

```powershell
Get-ChildItem legacy, archive\root_temp_workdirs, HCS_SOC\legacy | Select-Object FullName
```

Expected: each new directory is listed.

### Task 2: Move root logs, scratch files, and temp workdirs

**Files:**
- Modify: repository root directory layout
- Archive into: `archive/root_runtime_logs/serial/`
- Archive into: `archive/root_debug_scripts/`
- Archive into: `archive/root_tool_logs/`
- Archive into: `archive/root_temp_workdirs/`

- [ ] **Step 1: Move root temp workdirs**

Run:

```powershell
$targets = @(
  'temp_xsa_extract',
  'tmp',
  'tmp_design1_xsa_after_fix',
  'tmp_perf_demo',
  'tmp_rawcopy_xsa',
  'tmp_rawcopy_xsa_after_fix',
  'tmp_vendor_xsa',
  '.codex_sim',
  '.gen',
  '.srcs',
  '.pytest_cache',
  '__pycache__',
  'xsim.dir',
  '.Xil',
  'timing_summary.rpt',
  '-file',
  'report_timing_summary'
)
foreach ($name in $targets) {
  if (Test-Path $name) {
    Move-Item -LiteralPath $name -Destination 'archive/root_temp_workdirs' -Force
  }
}
```

- [ ] **Step 2: Move root scratch scripts and spillover files**

Run:

```powershell
$debug = @(
  '_tmp_build.py',
  '_tmp_check_status.tcl',
  '_tmp_probe_stage1.tcl',
  '_tmp_stage1_regs.tcl',
  'debug_uart.tcl',
  'restore_uart_complete.tcl',
  'restore_uart_working.tcl',
  'simple_uart.tcl',
  'tmp_dma_debug.tcl',
  'extract_pdf.py',
  'extract_pdf2.py',
  'tmp_pdf_extract.py',
  'verify_elf.py',
  'test_aes_mismatch.py'
)
foreach ($name in $debug) {
  if (Test-Path $name) {
    Move-Item -LiteralPath $name -Destination 'archive/root_debug_scripts' -Force
  }
}

$toolLogs = @(
  'vivado.jou',
  'vivado.log',
  'vivado_11584.backup.jou',
  'vivado_11584.backup.log',
  'vivado_36220.backup.jou',
  'vivado_36220.backup.log',
  'vivado_37188.backup.jou',
  'vivado_37188.backup.log',
  'vivado_8568.backup.jou',
  'vivado_8568.backup.log',
  'hs_err_pid8764.dmp'
)
foreach ($name in $toolLogs) {
  if (Test-Path $name) {
    Move-Item -LiteralPath $name -Destination 'archive/root_tool_logs' -Force
  }
}
```

- [ ] **Step 3: Verify the root no longer shows the moved clutter**

Run:

```powershell
Get-ChildItem -Force | Select-Object Name | Sort-Object Name
```

Expected: the listed temp and spillover items no longer appear at root.

### Task 3: Group historical root project families

**Files:**
- Modify: repository root directory layout
- Move to: `legacy/root_projects/`
- Move to: `legacy/root_tools/`

- [ ] **Step 1: Move historical root project directories**

Run:

```powershell
$projects = @(
  'crypto_hw_platform',
  'crypto_perf_test',
  'crypto_test_app',
  'sim',
  'sim_output',
  'sw',
  'uart_test_package',
  'rollback_packages',
  'open_checkpoint',
  'logs',
  'NA'
)
foreach ($name in $projects) {
  if (Test-Path $name) {
    Move-Item -LiteralPath $name -Destination 'legacy/root_projects' -Force
  }
}
```

- [ ] **Step 2: Move historical root helper files**

Run:

```powershell
$tools = @(
  'create_complete_backup.bat',
  'run_crypto_bench.bat',
  'run_sim.bat',
  'run_tb_dma_system.tcl',
  'day14_capture.pcap',
  'tmp_crypto_compile.prj',
  'tmp_spec.docx'
)
foreach ($name in $tools) {
  if (Test-Path $name) {
    Move-Item -LiteralPath $name -Destination 'legacy/root_tools' -Force
  }
}
```

- [ ] **Step 3: Verify the new legacy roots contain the moved families**

Run:

```powershell
Get-ChildItem legacy\root_projects, legacy\root_tools | Select-Object FullName
```

Expected: moved root families now live under `legacy/`.

### Task 4: Group historical HCS_SOC app, platform, sd_boot, and artifacts

**Files:**
- Modify: `HCS_SOC/` directory layout
- Move to: `HCS_SOC/legacy/apps/`
- Move to: `HCS_SOC/legacy/platforms/`
- Move to: `HCS_SOC/legacy/sd_boot/`
- Move to: `HCS_SOC/legacy/artifacts/`

- [ ] **Step 1: Move historical HCS_SOC app and platform families**

Run:

```powershell
$activeKeep = @(
  'ax7020_udp_gateway_shadow_mirror_app',
  'ax7020_udp_gateway_shadow_mirror_platform_xsct'
)
Get-ChildItem HCS_SOC -Directory | Where-Object {
  $_.Name -like 'ax7020_*' -and
  $_.Name -notin $activeKeep -and
  $_.Name -notlike 'ax7020_udp_gateway_shadow_mirror*'
} | ForEach-Object {
  $dest = if ($_.Name -like '*platform*' -or $_.Name -like '*xsct*') { 'HCS_SOC/legacy/platforms' } else { 'HCS_SOC/legacy/apps' }
  Move-Item -LiteralPath $_.FullName -Destination $dest -Force
}
```

- [ ] **Step 2: Move historical HCS_SOC sd_boot families**

Run:

```powershell
Get-ChildItem HCS_SOC\sd_boot -Directory | Where-Object {
  $_.Name -ne 'ax7020_udp_gateway_shadow_mirror'
} | ForEach-Object {
  Move-Item -LiteralPath $_.FullName -Destination 'HCS_SOC/legacy/sd_boot' -Force
}
```

- [ ] **Step 3: Move historical standalone HCS_SOC xsa/bit artifacts**

Run:

```powershell
Get-ChildItem HCS_SOC -File | Where-Object {
  ($_.Extension -in '.xsa', '.bit') -and
  $_.Name -notin @('udp_gateway_shadow_mirror_wrapper.xsa')
} | ForEach-Object {
  Move-Item -LiteralPath $_.FullName -Destination 'HCS_SOC/legacy/artifacts' -Force
}
```

- [ ] **Step 4: Verify active shadow-mirror HCS path remains present**

Run:

```powershell
Get-ChildItem HCS_SOC | Select-Object Name | Sort-Object Name
```

Expected: `ax7020_udp_gateway_shadow_mirror_app`, `ax7020_udp_gateway_shadow_mirror_platform_xsct`, `sd_boot`, and the active project roots still exist at top level.

### Task 5: Update repository structure docs and verification

**Files:**
- Modify: `doc/REPO_STRUCTURE.md`
- Create: `doc/DELIVERY_LAYOUT.md`
- Test: `tests/test_repository_layout_contracts.py`

- [ ] **Step 1: Update the repository structure doc to document `legacy/`**

Add explicit sections covering:

- `legacy/root_projects/`
- `legacy/root_tools/`
- `HCS_SOC/legacy/apps/`
- `HCS_SOC/legacy/platforms/`
- `HCS_SOC/legacy/sd_boot/`
- `HCS_SOC/legacy/artifacts/`

- [ ] **Step 2: Write a concise delivery layout guide**

Create `doc/DELIVERY_LAYOUT.md` describing:

- where active shadow-mirror code lives
- where logs and evidence live
- where historical experiments live
- what should be used for current release work

- [ ] **Step 3: Update layout tests if required**

Adjust `tests/test_repository_layout_contracts.py` only if the new `legacy/` roots need explicit assertions.

- [ ] **Step 4: Run verification**

Run:

```powershell
py -3 -m unittest tests.test_repository_layout_contracts -v
```

Expected: all tests pass.

- [ ] **Step 5: Review final layout**

Run:

```powershell
Get-ChildItem -Force | Select-Object Mode,Name | Sort-Object Name | Format-Table -AutoSize
Get-ChildItem -Force HCS_SOC | Select-Object Mode,Name | Sort-Object Name | Format-Table -AutoSize
git status --short
```

Expected: root and `HCS_SOC/` are visibly cleaner, active paths remain obvious, and changes are limited to layout/doc updates rather than active RTL behavior.
