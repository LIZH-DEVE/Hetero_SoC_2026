# Control And Data Plane Protocol

## Protocol authority
- Python host-side validation is the only Golden Vector oracle for this baseline.
- If a board implementation disagrees with the Python scripts, treat the board as wrong first.
- Do not change the Python oracle to match a drifting board implementation during porting.

## External ports
- `4660/UDP`
  - AES-128 ECB encrypt
- `4661/UDP`
  - SM4 encrypt
- `4662/UDP`
  - control plane

## Data-plane contract
- Payload is raw block data only.
- No control header is present on `4660/4661`.
- Valid lengths:
  - greater than `0`
  - less than or equal to `1472`
  - multiple of `16`
- Access rule:
  - source IP must first establish and authorize a control session on `4662`
- Failure behavior:
  - invalid length -> drop
  - unauthorized source -> drop
  - queue full -> drop

## Control-plane header
- Network byte order for all multi-byte fields.
- Fixed header length: `24` bytes
- `binding_id` must remain big-endian in both:
  - key-derivation material
  - `auth_tag` material
- Do not switch to little-endian on one side only.

| Offset | Size | Field |
|---|---:|---|
| `0` | 4 | `magic = 0x4352544C` (`CRTL`) |
| `4` | 1 | `version = 1` |
| `5` | 1 | `msg_type` |
| `6` | 1 | `flags` |
| `7` | 1 | `reserved = 0` |
| `8` | 4 | `session_id` |
| `12` | 4 | `seq_id` |
| `16` | 2 | `payload_len` |
| `18` | 2 | `status_code` |
| `20` | 4 | `auth_tag` |

## Message types
- `1 = HELLO`
  - create or refresh a session for this source IP
  - request carries no auth tag
  - response returns `session_id` and 4-byte `binding_id`
- `2 = SET_KEY`
  - payload length must be `16`
  - binds user key material to one or both algorithms
  - effective key is derived per algorithm using `user_key + binding_id + algo`
- `3 = LOCK`
  - locks this source-IP session
- `4 = UNLOCK`
  - clears lock state and replay/auth failure state
  - does not restore old effective keys automatically
- `5 = STATUS`
  - returns exported counters and session state
- `6 = BENCH`
  - runs software-vs-hardware timing on board

## Flags
- `0x01 = AES authorized / AES bench selection`
- `0x02 = SM4 authorized / SM4 bench selection`
- `SET_KEY`
  - may set one or both bits
- `BENCH`
  - exactly one algorithm bit should be selected

## Status codes
- `0 = OK`
- `1 = BAD_MAGIC`
- `2 = BAD_VERSION`
- `3 = BAD_LENGTH`
- `4 = SESSION_REQUIRED`
- `5 = AUTH_FAIL`
- `6 = REPLAY`
- `7 = LOCKED`
- `8 = NO_SESSION`
- `9 = INTERNAL`
- `10 = UNKNOWN_MSG`
- `11 = NOT_AUTHORIZED`
- `12 = BUSY`

## Auth-tag rule
- `HELLO` is unauthenticated.
- All other control requests require `auth_tag`.
- Current implementation uses an FNV-based tag over:
  - `binding_id`
  - fixed header fields
  - payload
- `binding_id` is packed in big-endian order before hashing.
- This endianness is part of the protocol contract for the current baseline.

## Replay protection
- Scope:
  - control plane only
- Keys:
  - source IP
  - `session_id`
  - `seq_id`
- Window:
  - 32-entry sliding window
- Failure threshold:
  - `3` replay failures trigger session lock

## Auth failure handling
- Scope:
  - control plane only
- Failure threshold:
  - `3` auth failures trigger session lock

## Lock behavior
- Lock clears:
  - AES effective key
  - SM4 effective key
  - authorized algorithm mask
- While locked:
  - data plane is unusable
  - control plane accepts only `STATUS` and `UNLOCK`

## STATUS payload
- Payload size: `14 * 4 = 56` bytes
- Field order:
  1. `binding_id`
  2. `session_id`
  3. `authorized_mask`
  4. `locked`
  5. `rx_ctrl_ok`
  6. `rx_data_ok`
  7. `tx_ok`
  8. `drop_invalid`
  9. `drop_unauthorized`
  10. `drop_replay`
  11. `bind_fail`
  12. `lock_events`
  13. `crypto_timeout`
  14. `crypto_fail`

## BENCH payload
- Header layout:
  - `algo_id : 1 byte`
  - `record_count : 1 byte`
  - `repeats : 2 bytes`
- Record layout, repeated `record_count` times:
  - `length : 2 bytes`
  - `reserved : 2 bytes`
  - `sw_us : 4 bytes`
  - `hw_us : 4 bytes`
- Current record lengths are fixed:
  - `16`
  - `32`
  - `128`
  - `512`
  - `1472`

## Exported behavior versus internal-only behavior
- Exported and stable:
  - ports
  - control header
  - message types
  - status codes
  - STATUS field order
  - BENCH record format
- Internal and replaceable later:
  - FNV-based effective-key derivation
  - placeholder `binding_id`
  - direct-MMIO crypto execution path
  - queue implementation details
  - non-exported counters such as queue-busy and internal completion totals
