# Robeieda Porting Pack

## Purpose
- This directory is the only teammate-facing entrypoint for the current non-DMA UDP crypto gateway migration.
- It packages the frozen protocol contract, the Python oracle, the required bring-up order, and the one-click acceptance pipeline.
- Original source files remain in their original locations and are not modified by this pack.

## Non-negotiable oracle
- Python host-side scripts are the only Golden Vector oracle for this baseline.
- If `robeieda` board output differs from Python expected output, treat the board-side implementation as wrong first.
- Do not modify Python tests to make a drifting board implementation pass.
- Porting is not a protocol-upgrade phase. Only an intentional protocol revision may update host and board together.

## Fixed contract
- `4660/UDP` = AES-128 ECB encrypt
- `4661/UDP` = SM4 encrypt
- `4662/UDP` = control plane
- Data plane:
  - raw ECB block payload only
  - `0 < len <= 1472`
  - `len % 16 == 0`
- `binding_id = 0x41583702`
- `binding_id` remains big-endian in:
  - key-derivation material
  - `auth_tag` material

## Required bring-up order
- `UDP Echo -> Header Parser -> HELLO -> SET_KEY -> Replay -> Lock/Unlock -> Data Plane -> BENCH`
- Do not skip ahead.
- If a stage fails, fix that stage before enabling the next one.

## Pack layout
- `docs/`
  - protocol truth, migration notes, acceptance checklist, bring-up checklist
- `tools/`
  - control client, sender, regression, acceptance, and report scripts
- `oracle/`
  - frozen golden vectors and acceptance semantics
- `examples/`
  - copyable commands for teammate bring-up and acceptance
- `tests/`
  - pack-local tests for acceptance/report tooling

## Primary commands
### One-click acceptance
```powershell
py -3 .\tools\run_udp_crypto_acceptance.py --ip 192.168.1.20 --source-ip 192.168.1.11 --timeout 3 --length-timeout 6 --bench-timeout 10 --bench-repeats 8
```

### Acceptance report wrapper
```powershell
py -3 .\tools\run_udp_crypto_acceptance_report.py --output-dir .\logs --ip 192.168.1.20 --source-ip 192.168.1.11 --timeout 3 --length-timeout 6 --bench-timeout 10 --bench-repeats 8
```

## Success definition
- `robeieda` porting is successful only when:
  - the one-click acceptance script runs end to end
  - it exits with code `0`
  - it prints `ACCEPTANCE_PASS`

## Reading order
1. `docs/ROBEIEDA_BRINGUP_CHECKLIST.md`
2. `docs/CONTROL_PROTOCOL.md`
3. `oracle/GOLDEN_VECTORS.md`
4. `docs/BOARD_ACCEPTANCE.md`
