import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"
COMMON = HCS_SOC / "ftdi_jtag_common.ps1"
CHECK = HCS_SOC / "check_ax7020_ftdi_jtag.ps1"
START = HCS_SOC / "start_ax7020_ft_prog_recovery.ps1"
VERIFY = HCS_SOC / "verify_ax7020_ft_prog_recovery.ps1"


class TestAx7020FtdiJtagRecoveryContracts(unittest.TestCase):
    def test_common_script_supports_get_pnpdevice_cim_and_pnputil_fallback_chain(self):
        text = COMMON.read_text(encoding="utf-8")

        for token in (
            "function New-FtdiDeviceRecord",
            "function Get-PresentPnpDevices",
            "Get-PnpDevice -PresentOnly",
            "Get-CimInstance Win32_PnPEntity",
            "pnputil /enum-devices /connected",
            "function Get-FtdiUsbDevicesFromPnputil",
            "function Convert-CimPnPEntityToDeviceRecord",
            "function Convert-PnpDeviceToDeviceRecord",
            "function Get-PnpDriverSnapshotFromPnputil",
            "Win32_PnPSignedDriver",
            "VID_0403&PID_6014",
        ):
            self.assertIn(token, text)

    def test_common_script_keeps_device_shape_stable_for_callers(self):
        text = COMMON.read_text(encoding="utf-8")

        for token in (
            "Status",
            "Class",
            "FriendlyName",
            "InstanceId",
            "DeviceName",
            "Manufacturer",
            "DriverProviderName",
            "DriverVersion",
            "InfName",
            "Get-TopLevelFtdiUsbDevices",
            "Get-Ax7020BoardFtdiDevice",
            "Export-Ax7020FtdiSnapshot",
        ):
            self.assertIn(token, text)

    def test_common_script_builds_program_ftdi_runtime_with_tcl85_alias_compat(self):
        text = COMMON.read_text(encoding="utf-8")

        for token in (
            'Join-Path $VivadoRoot "lib\\win64.o\\tcl86t.dll"',
            'Name = "tcl85t.dll"',
            'Join-Path $runtimeRoot $item.Name',
            'Get-ProgramFtdiRuntimeStatus',
            '"tcl85t.dll"',
            '"tcl86t.dll"',
        ):
            self.assertIn(token, text)

    def test_entry_scripts_continue_to_use_common_layer_and_keep_read_only_boundary(self):
        check_text = CHECK.read_text(encoding="utf-8")
        start_text = START.read_text(encoding="utf-8")
        verify_text = VERIFY.read_text(encoding="utf-8")

        self.assertIn('. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")', check_text)
        self.assertIn('. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")', start_text)
        self.assertIn('. (Join-Path $PSScriptRoot "ftdi_jtag_common.ps1")', verify_text)

        for token in (
            "Get-FtdiUsbDevices",
            "Get-TopLevelFtdiUsbDevices",
            "Get-Ax7020BoardFtdiDevice",
            "Invoke-XsdbTargetsCheck",
        ):
            self.assertIn(token, check_text + start_text + verify_text)

        self.assertIn('[switch]$NoLaunch', start_text)
        self.assertIn('if (-not $NoLaunch)', start_text)
        self.assertIn('Write-Host ("FT_Prog backup target: {0}" -f $backupPath)', start_text)
        self.assertIn('Write-Host ("FT_Prog Payload A target: {0}" -f $payloadAPath)', start_text)
        self.assertNotIn('Invoke-ProgramFtdi -Arguments @("-write"', start_text)

    def test_start_and_verify_scripts_handle_missing_user_area_helper_without_abort(self):
        start_text = START.read_text(encoding="utf-8")
        verify_text = VERIFY.read_text(encoding="utf-8")

        for token in (
            "Resolve-FtdiUserAreaRepairScript",
            "User area repair script",
        ):
            self.assertIn(token, start_text + verify_text)

        self.assertIn("if ($repairScript) {", start_text)
        self.assertIn("else {", start_text)
        self.assertIn("D2XX snapshot was skipped", verify_text)


if __name__ == "__main__":
    unittest.main()
