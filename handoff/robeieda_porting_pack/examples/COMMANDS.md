# Example Commands

## UDP Echo bring-up
- First stage on `robeieda`: implement standalone `4662/UDP` echo before parsing protocol headers.
- The Python pack does not provide an echo-specific client; any UDP tool is acceptable at this stage.

## HELLO
```powershell
py -3 .\tools\udp_crypto_control.py --ip 192.168.1.20 --source-ip 192.168.1.11 hello
```

## Absolute denial
```powershell
py -3 .\tools\send_udp_crypto_test.py --algo aes --ip 192.168.1.20 --source-ip 192.168.1.11 --skip-control-session --expect-timeout
py -3 .\tools\send_udp_crypto_test.py --algo sm4 --ip 192.168.1.20 --source-ip 192.168.1.11 --skip-control-session --expect-timeout
```

## AES and SM4 single-block
```powershell
py -3 .\tools\send_udp_crypto_test.py --algo aes --ip 192.168.1.20 --source-ip 192.168.1.11
py -3 .\tools\send_udp_crypto_test.py --algo sm4 --ip 192.168.1.20 --source-ip 192.168.1.11
```

## 1472-byte path
```powershell
py -3 .\tools\run_udp_crypto_length_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11 --algo aes --lengths 1472 --skip-invalid --skip-stress --timeout 6 --send-interval-ms 1 --hex-preview-chars 48
py -3 .\tools\run_udp_crypto_length_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11 --algo sm4 --lengths 1472 --skip-invalid --skip-stress --timeout 6 --send-interval-ms 1 --hex-preview-chars 48
```

## Full control regression
```powershell
py -3 .\tools\run_udp_crypto_control_regression.py --ip 192.168.1.20 --source-ip 192.168.1.11 --timeout 3 --bench-timeout 10 --bench-repeats 8
```

## One-click acceptance
```powershell
py -3 .\tools\run_udp_crypto_acceptance.py --ip 192.168.1.20 --source-ip 192.168.1.11 --timeout 3 --length-timeout 6 --bench-timeout 10 --bench-repeats 8
```
