# Golden Vectors And Acceptance Rules

## Oracle rule
- These vectors are interpreted by the Python host-side scripts in `tools/`.
- If board-side output differs from these values under the same session and input conditions, board-side logic is wrong by default.

## Fixed defaults
- `binding_id = 0x41583702`
- KDF/auth serialization:
  - `binding_id` is big-endian
- Data plane remains ECB-only

## AES single-block binding-aware vector
- User key:
  - `2b7e151628aed2a6abf7158809cf4f3c`
- Plaintext:
  - `3243f6a8885a308d313198a2e0370734`
- Effective key after `derive_effective_key(user_key, binding_id, AES)`:
  - `f79bcb65cdb7b7a3f497dea53c693557`
- Expected ciphertext:
  - `8f823d9b4747ca31d5a64c9986747ea8`

## SM4 single-block binding-aware vector
- User key:
  - `0123456789abcdeffedcba9876543210`
- Plaintext:
  - `0123456789abcdeffedcba9876543210`
- Effective key after `derive_effective_key(user_key, binding_id, SM4)`:
  - `c14a71382ec8b239e68ddf0f04aa172e`
- Expected ciphertext:
  - `aa2860c400ce76a659ab940e7866cda1`

## Unauthorized rule
- `HELLO` alone does not authorize the data plane.
- If data packets are sent after `HELLO` but before `SET_KEY`, expected result is:
  - sender timeout treated as `PASS`
  - board-side `drop_unauthorized` increments
  - no `job_start`

## 1472-byte rule
- `1472-byte` AES and SM4 traffic must:
  - succeed on `attempt=1`
  - produce `expected_match=1`
  - produce `result=PASS`
- This is the required MTU-path acceptance condition for the current baseline.

## Final gate
- `tools/run_udp_crypto_acceptance.py` is the only total-system acceptance gate.
- `tools/run_udp_crypto_acceptance_report.py` is the reporting wrapper around that gate.
