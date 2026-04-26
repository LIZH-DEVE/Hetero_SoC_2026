import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"

UART_DIAG_MAIN = HCS_SOC / "ax7020_dma_raw_copy_uart_diag_app" / "src" / "main.c"
UART_DIAG_BUILD_BOOT = HCS_SOC / "build_ax7020_dma_raw_copy_uart_diag_boot.ps1"
UART_DIAG_DEPLOY = HCS_SOC / "deploy_ax7020_dma_raw_copy_uart_diag_to_sd.ps1"
UART_DIAG_BOOT_BIF = HCS_SOC / "sd_boot" / "ax7020_dma_raw_copy_uart_diag" / "boot.bif"


class TestDmaRawCopyUartDiagRelease(unittest.TestCase):
    def test_uart_only_app_contract_if_present(self):
        if not UART_DIAG_MAIN.exists():
            self.skipTest(f"UART-only diag app not present yet: {UART_DIAG_MAIN}")

        text = UART_DIAG_MAIN.read_text(encoding="ascii")
        self.assertNotIn('dma_hw_regs.h', text)
        self.assertNotIn('dma_mvp_ps_driver_ref.h', text)
        self.assertNotIn("0x40000000", text)
        self.assertIn("RAWCOPY UART DIAG", text)
        self.assertIn("RAWCOPY_PLATFORM_OK", text)
        self.assertIn("RAWCOPY_UART_HEARTBEAT", text)

    def test_boot_release_contract_if_files_exist(self):
        existing = [
            path for path in (UART_DIAG_BUILD_BOOT, UART_DIAG_DEPLOY, UART_DIAG_BOOT_BIF)
            if path.exists()
        ]
        if not existing:
            self.skipTest("UART diag boot/deploy artifacts not present yet")

        for required in (UART_DIAG_BUILD_BOOT, UART_DIAG_DEPLOY, UART_DIAG_BOOT_BIF):
            self.assertTrue(required.exists(), f"Expected staged UART diag artifact missing: {required}")

        lines = [
            line.strip()
            for line in UART_DIAG_BOOT_BIF.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.strip().startswith("//")
        ]
        self.assertEqual(lines[0], "the_ROM_image:")
        self.assertEqual(lines[1], "{")
        self.assertEqual(lines[-1], "}")
        payload = lines[2:-1]
        self.assertEqual(len(payload), 3)
        self.assertTrue(payload[0].startswith("[bootloader] "))
        self.assertTrue(payload[1].endswith(".bit"))
        self.assertTrue(payload[2].endswith(".elf"))


if __name__ == "__main__":
    unittest.main()
