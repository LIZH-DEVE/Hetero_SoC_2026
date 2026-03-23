# Board Acceptance Checklist

## Goal
- Validate the current non-DMA control-plane baseline on the stable hardware line.
- Do not change bitstream line during this validation.

## Oracle rule
- `run_udp_crypto_acceptance.py` is the only total-system acceptance gate.
- Any mismatch between Python expected output and board output is a board-side defect until proven otherwise.
- Do not patch Python acceptance scripts to accommodate a porting-side deviation.

## Boot composition
- FSBL:
  - official `06_net_test` `fsbl.elf`
- Bitstream:
  - backup working `design_1_wrapper.bit`
- Application:
  - current `ws_2` `ax7020_udp_gateway_app.elf`

## Pre-checks
- Serial console must show:
  - bind success for `4660`, `4661`, `4662`
- Basic networking:
  - `ping 192.168.1.20`

## Minimal staged acceptance order
1. `ping`
2. unauthorized absolute denial
3. `HELLO + SET_KEY`
4. authorized single-block AES/SM4
5. authorized `1472-byte` AES/SM4
6. full control-plane regression
7. acceptance report generation

## Control-plane validation
### 1. HELLO
```powershell
py -3 HCS_SOC\udp_crypto_control.py --ip 192.168.1.20 --source-ip 192.168.1.11 hello
```
- Expect:
  - `session_id=...`
  - `binding_id=0x41583702`

### 2. SET_KEY
```powershell
py -3 HCS_SOC\udp_crypto_control.py --ip 192.168.1.20 --source-ip 192.168.1.11 set-key --session-id <session_id> --binding-id 0x41583702 --algo aes
```
- Expect:
  - success exit code
  - no auth or replay failure

### 3. STATUS
```powershell
py -3 HCS_SOC\udp_crypto_control.py --ip 192.168.1.20 --source-ip 192.168.1.11 status --session-id <session_id> --binding-id 0x41583702
```
- Expect:
  - `authorized_mask` matches prior authorization
  - `locked=0`

## Data-plane validation
### Unauthorized rejection
```powershell
py -3 HCS_SOC\send_udp_crypto_test.py --algo aes --skip-control-session --expect-timeout
py -3 HCS_SOC\send_udp_crypto_test.py --algo sm4 --skip-control-session --expect-timeout
```
- Expect:
  - timeout is treated as pass
  - serial log contains `drop unauthorized`
  - no `job_start` appears for those packets

### Authorized AES and SM4
```powershell
py -3 HCS_SOC\send_udp_crypto_test.py --algo aes
py -3 HCS_SOC\send_udp_crypto_test.py --algo aes --payload-hex <32-byte repeated AES block>
py -3 HCS_SOC\run_udp_crypto_length_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11 --algo aes --lengths 1472 --skip-invalid --skip-stress --timeout 6 --send-interval-ms 1

py -3 HCS_SOC\send_udp_crypto_test.py --algo sm4
py -3 HCS_SOC\send_udp_crypto_test.py --algo sm4 --payload-hex <32-byte repeated SM4 block>
py -3 HCS_SOC\run_udp_crypto_length_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11 --algo sm4 --lengths 1472 --skip-invalid --skip-stress --timeout 6 --send-interval-ms 1
```
- Expect:
  - `expected_match=1`
  - `result=PASS`
  - `attempt=1` success for `1472`

## Replay validation
```powershell
py -3 HCS_SOC\run_udp_crypto_control_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11
```
- Expect:
  - `CASE replay`
  - `replay_drop=1`
  - control regression exits with success

## Lock and unlock validation
- Within `run_udp_crypto_control_regression.py`, verify:
  - `CASE lock/unlock`
  - `locked=1`
  - `locked_after_unlock=0`
- After unlock, run `SET_KEY` again before using the data plane.

## BENCH validation
```powershell
py -3 HCS_SOC\run_udp_crypto_control_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11 --bench-repeats 8
```
- Expect both AES and SM4 records:
  - `len=16`
  - `len=32`
  - `len=128`
  - `len=512`
  - `len=1472`
- Each record must contain:
  - `sw_us`
  - `hw_us`

## Serial log keywords
- Successful control path:
  - control bind for `4662`
- Successful data path:
  - `rx_callback entry`
  - `queued`
  - `job_start`
  - `job_complete`
  - `response sent`
- Expected rejection path:
  - `drop invalid`
  - `drop unauthorized`

## Failure triage
- `BAD_MAGIC` or `BAD_VERSION`
  - host and board control header mismatch
- `AUTH_FAIL`
  - binding-id or auth-tag mismatch
- `REPLAY`
  - repeated `seq_id` or stale session state
- data timeout after authorization
  - check control session was established for the same source IP
  - check lock state with `STATUS`
  - check serial log for `drop unauthorized` or crypto timeout
- BENCH failure
  - inspect returned status code first
  - then inspect serial timeout/failure lines

## One-click acceptance
```powershell
py -3 HCS_SOC\run_udp_crypto_acceptance.py --ip 192.168.1.20 --source-ip 192.168.1.11 --timeout 3 --length-timeout 6 --bench-timeout 10 --bench-repeats 8
```
- The script must fail fast:
  - any failed stage stops the pipeline immediately
  - exit code must be non-zero
- On success:
  - exit code `0`
  - prints `ACCEPTANCE_PASS`
  - emits `raw_log=...`
  - emits `report_md=...`

## Acceptance criteria
- `4662` control plane fully usable
- unauthorized data plane is rejected
- authorized AES/SM4 still pass at `16`, `32`, and `1472`
- replay attempts are rejected
- lock makes data plane unusable
- unlock plus re-authorization restores service
- BENCH returns both software and hardware timings
