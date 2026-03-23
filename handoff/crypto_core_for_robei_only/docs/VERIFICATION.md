# Verification Notes

## Robei-ready RTL syntax check
The files under `rtl_robei_ready/` were compiled with Vivado 2024.1 `xvlog`.

Command used:

```powershell
cmd /c "call D:\Xilinx\Vivado\2024.1\settings64.bat && xvlog -nolog <rtl_robei_ready *.v>"
```

Result:
- All `.v` files in `rtl_robei_ready/` compiled successfully.
- No `.sv` files are present in `rtl_robei_ready/`.

## Functional smoke test
The handoff copy of `tb_vivado_only/tb_crypto_simple.sv` was run against `rtl_robei_ready/`.

Command used:

```powershell
cmd /c "call D:\Xilinx\Vivado\2024.1\settings64.bat && xvlog -sv -nolog <rtl_robei_ready *.v> <tb_crypto_simple.sv> && xelab -nolog tb_crypto_simple -s tb_crypto_simple_robei && xsim tb_crypto_simple_robei -runall"
```

Result:
- AES-128 encrypt: PASS
- AES-128 decrypt: PASS
- SM4 encrypt: PASS
- SM4 decrypt: PASS

## Scope of this verification
- This confirms that the simplified Robei handoff path is syntactically clean and functionally alive in a Vivado simulation flow.
- This does not claim Robei tool compatibility beyond the package design constraints:
  - pure `.v` source in `rtl_robei_ready/`
  - no AXI-Lite dependency in the main entry path
  - 32-bit external word interface on `crypto_robei_top`
