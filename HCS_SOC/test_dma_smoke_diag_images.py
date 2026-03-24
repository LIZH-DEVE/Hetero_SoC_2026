import unittest
from pathlib import Path


class DmaSmokeDiagImageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parent

    def test_diag_app_and_boot_scripts_exist(self) -> None:
        self.assertTrue((self.root / "ax7020_dma_mvp_diag_app" / "src" / "main.c").exists())
        self.assertTrue((self.root / "build_ax7020_dma_mvp_diag_app.ps1").exists())
        self.assertTrue((self.root / "build_ax7020_dma_mvp_diag_boot.ps1").exists())
        self.assertTrue((self.root / "sd_boot" / "ax7020_dma_mvp_diag_system" / "readme.txt").exists())

    def test_uart_smoke_app_and_boot_scripts_exist(self) -> None:
        self.assertTrue((self.root / "ax7020_system_uart_smoke_app" / "src" / "main.c").exists())
        self.assertTrue((self.root / "build_ax7020_system_uart_smoke_app.ps1").exists())
        self.assertTrue((self.root / "build_ax7020_system_uart_smoke_boot.ps1").exists())
        self.assertTrue((self.root / "sd_boot" / "ax7020_system_uart_smoke_system" / "readme.txt").exists())

    def test_diag_app_has_stage_markers_before_pl_mmio(self) -> None:
        text = (self.root / "ax7020_dma_mvp_diag_app" / "src" / "main.c").read_text(encoding="utf-8")

        self.assertIn('xil_printf("DMA diag image', text)
        self.assertIn('print_stage("main_enter")', text)
        required_markers = [
            'print_stage("before_ring_init")',
            'print_stage("after_ring_init")',
            'print_stage("before_key_program")',
            'print_stage("after_key_program")',
            'print_stage("before_inject_enable")',
            'print_stage("after_inject_enable")',
            'print_stage("before_normal_submit")',
        ]
        for marker in required_markers:
            self.assertIn(marker, text)

        self.assertLess(text.index('xil_printf("DMA diag image'), text.index("dma_ring_init("))

    def test_uart_smoke_app_does_not_touch_dma_csr(self) -> None:
        text = (self.root / "ax7020_system_uart_smoke_app" / "src" / "main.c").read_text(encoding="utf-8")
        self.assertIn("system_wrapper uart smoke", text)
        self.assertIn("uart1 ok", text)
        self.assertNotIn("DMA_CSR_BASE", text)
        self.assertNotIn("dma_ring_init", text)
        self.assertNotIn("Xil_In32", text)
        self.assertNotIn("Xil_Out32", text)


if __name__ == "__main__":
    unittest.main()
