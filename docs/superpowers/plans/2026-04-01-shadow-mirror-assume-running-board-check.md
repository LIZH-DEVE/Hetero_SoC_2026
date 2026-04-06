# Shadow Mirror Assume Running Board Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a JTAG-friendly `-AssumeRunning` mode to the shadow mirror board-check scripts so daily development can skip misleading power-cycle prompts and fixed boot waits while preserving the existing SD/cold-boot default flow.

**Architecture:** Keep each script's existing capture, control, and evidence collection behavior intact. Add one new switch parameter to the five shadow mirror board-check entry points and gate only the user prompt plus fixed `Start-Sleep` block behind that switch.

**Tech Stack:** PowerShell, Python helper wrappers, unittest release-contract tests

---

### Task 1: Lock the new CLI contract in tests

**Files:**
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`

- [ ] **Step 1: Write the failing test**

```python
def test_shadow_board_checks_support_assume_running_mode(self):
    for script_path in (ACL_CHECK, FASTPATH_CHECK, SECURITY_CHECK, PERF_CHECK, BOARD_CHECK):
        script_text = script_path.read_text(encoding="ascii")
        self.assertIn('[switch]$AssumeRunning', script_text)
        self.assertIn('if ($AssumeRunning)', script_text)
        self.assertIn('Assuming board is already running; skipping power-cycle prompt and boot wait.', script_text)
        self.assertIn('Power-cycle the board now: turn power off for 3 seconds, then power it back on.', script_text)
        self.assertIn('Start-Sleep -Seconds $BootLeadSeconds', script_text)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `py -3 -m unittest tests.test_udp_gateway_shadow_mirror_release.TestUdpGatewayShadowMirrorRelease.test_shadow_board_checks_support_assume_running_mode -v`
Expected: FAIL because the scripts do not expose `-AssumeRunning` yet.

- [ ] **Step 3: Write minimal implementation**

```powershell
[switch]$AssumeRunning

Write-Host ("UART capture started. Log path: {0}" -f $uartLogPath)
if ($AssumeRunning) {
    Write-Host "Assuming board is already running; skipping power-cycle prompt and boot wait."
}
else {
    Write-Host "Power-cycle the board now: turn power off for 3 seconds, then power it back on."
    Write-Host ("Waiting {0} seconds before sending ... traffic..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `py -3 -m unittest tests.test_udp_gateway_shadow_mirror_release.TestUdpGatewayShadowMirrorRelease.test_shadow_board_checks_support_assume_running_mode -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/test_udp_gateway_shadow_mirror_release.py HCS_SOC/run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1 HCS_SOC/run_ax7020_udp_gateway_shadow_mirror_security_check.ps1 HCS_SOC/run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1 HCS_SOC/run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1 HCS_SOC/run_ax7020_udp_gateway_shadow_mirror_board_check.ps1 docs/superpowers/plans/2026-04-01-shadow-mirror-assume-running-board-check.md
git commit -m "feat: add assume-running mode for board checks"
```

### Task 2: Apply the switch uniformly across board-check entry points

**Files:**
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_security_check.ps1`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1`
- Modify: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_board_check.ps1`

- [ ] **Step 1: Add the switch parameter**

```powershell
[switch]$AssumeRunning
```

- [ ] **Step 2: Gate the power-cycle prompt and wait**

```powershell
if ($AssumeRunning) {
    Write-Host "Assuming board is already running; skipping power-cycle prompt and boot wait."
}
else {
    Write-Host "Power-cycle the board now: turn power off for 3 seconds, then power it back on."
    Write-Host ("Waiting {0} seconds before sending ... traffic..." -f $BootLeadSeconds)
    Start-Sleep -Seconds $BootLeadSeconds
}
```

- [ ] **Step 3: Preserve the rest of each script unchanged**

```powershell
$hello = Invoke-ControlCommandWithRetry ...
$result = Invoke-PythonLogged ...
Wait-Process -Id $captureProc.Id
```

- [ ] **Step 4: Parse-check the modified scripts**

Run:
- `powershell -NoLogo -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1',[ref]$null,[ref]$errors) > $null; if ($errors.Count -eq 0) { 'ACL_CHECK_PS1_PARSE_OK' } else { $errors | % ToString; exit 1 }"`
- `powershell -NoLogo -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_security_check.ps1',[ref]$null,[ref]$errors) > $null; if ($errors.Count -eq 0) { 'SECURITY_CHECK_PS1_PARSE_OK' } else { $errors | % ToString; exit 1 }"`
- `powershell -NoLogo -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_fastpath_board_check.ps1',[ref]$null,[ref]$errors) > $null; if ($errors.Count -eq 0) { 'FASTPATH_CHECK_PS1_PARSE_OK' } else { $errors | % ToString; exit 1 }"`
- `powershell -NoLogo -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_performance_check.ps1',[ref]$null,[ref]$errors) > $null; if ($errors.Count -eq 0) { 'PERF_CHECK_PS1_PARSE_OK' } else { $errors | % ToString; exit 1 }"`
- `powershell -NoLogo -NoProfile -Command "$errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_board_check.ps1',[ref]$null,[ref]$errors) > $null; if ($errors.Count -eq 0) { 'BOARD_CHECK_PS1_PARSE_OK' } else { $errors | % ToString; exit 1 }"`

Expected: each command prints its `_PS1_PARSE_OK` marker.

### Task 3: Verify release-contract coverage stays green

**Files:**
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_mirror_release.py`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\tests\test_udp_gateway_shadow_runtime_contracts.py`
- Test: `D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\tests\test_shadow_mirror_jtag_launcher.py`

- [ ] **Step 1: Run the release and runtime regression suite**

```bash
py -3 -m unittest tests.test_udp_gateway_shadow_mirror_release tests.test_udp_gateway_shadow_runtime_contracts HCS_SOC/tests/test_shadow_mirror_jtag_launcher.py -v
```

- [ ] **Step 2: Confirm green output**

Expected: all tests pass with no failures or errors.

- [ ] **Step 3: Optional live smoke for JTAG workflow**

```bash
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File D:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\HCS_SOC\run_ax7020_udp_gateway_shadow_mirror_acl_check.ps1 -AssumeRunning
```

Expected: skips the power-cycle prompt, does not sleep for boot, and proceeds directly into HELLO/control flow.
