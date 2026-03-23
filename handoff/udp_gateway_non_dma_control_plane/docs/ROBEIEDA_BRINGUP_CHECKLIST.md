# Robeieda Bring-up Checklist

## Rule zero
- Do not start by debugging the full control-plane state machine.
- First prove the transport path works.
- Then prove the parser works.
- Then prove the session protocol works.

## Stage 1: UDP Echo on `4662`
- Goal:
  - prove MAC, IP, UDP, interrupt/DMA, and basic socket plumbing are alive
- Required behavior:
  - bind `4662/UDP`
  - echo the received payload byte-for-byte
- Do not do yet:
  - 24-byte control-header parsing
  - session allocation
  - replay checks
  - KDF
  - auth tags

### Pass condition
- A network debug tool or a tiny Python sender sends bytes to `4662`
- `robeieda` returns the exact same bytes
- No board-side protocol logic is involved

## Stage 2: 24-byte Header Parser
- Replace pure echo with header parsing.
- Use the fixed packed header from `CONTROL_PROTOCOL.md`.
- At this stage only parse and print:
  - `magic`
  - `version`
  - `msg_type`
  - `session_id`
  - `seq_id`

### Pass condition
- Known test packets decode to the expected field values
- `HELLO` may still return a hard-coded `binding_id = 0x41583702`

## Stage 3: HELLO and Session Allocation
- Implement:
  - source-IP keyed session table
  - `HELLO -> session_id`
  - fixed `binding_id = 0x41583702`
- Do not start data plane until this stage is stable.

### Pass condition
- `udp_crypto_control.py hello` returns:
  - `session_id`
  - `binding_id=0x41583702`

## Stage 4: Security Control Plane
- Add in this order:
  1. `SET_KEY`
  2. replay window
  3. `LOCK/UNLOCK`
  4. `STATUS`
  5. `BENCH`

### Pass condition
- `run_udp_crypto_control_regression.py` reaches `CONTROL_REGRESSION_PASS`

## Stage 5: Data Plane
- Add data-plane authorization gate before crypto work on:
  - `4660`
  - `4661`
- Preserve raw ECB payload semantics:
  - no control header in data packets
  - no replay fields in data packets

### Pass condition
- Unauthorized data packets timeout and increment `drop_unauthorized`
- Authorized AES/SM4 single-block and `1472-byte` cases pass

## Final gate
- `run_udp_crypto_acceptance.py` is the only total-system acceptance entry.
- Porting is successful only when:
  - the script runs end to end
  - it exits `0`
  - it prints `ACCEPTANCE_PASS`
