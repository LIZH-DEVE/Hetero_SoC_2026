import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
HCS_SOC = REPO_ROOT / "HCS_SOC"
SCRIPT = HCS_SOC / "generate_ax7020_standalone_platform.ps1"
BUILD_BOOT = HCS_SOC / "build_ax7020_udp_gateway_shadow_mirror_boot.ps1"


class TestGenerateAx7020StandalonePlatformContract(unittest.TestCase):
    def test_script_exists(self):
        self.assertTrue(SCRIPT.exists(), f"Missing standalone platform generator: {SCRIPT}")

    def test_script_contains_shadow_platform_generation_flow(self):
        text = SCRIPT.read_text(encoding="ascii")
        for token in (
            'Join-Path $workspace "ax7020_udp_gateway_shadow_mirror_platform_xsct\\workspace"',
            "platform create -name $platform_name -hw $xsa_path -proc ps7_cortexa9_0 -os standalone",
            "platform active $platform_name",
            "platform generate",
            '"$PlatformName\\zynq_fsbl\\zynq_fsbl_bsp\\ps7_cortexa9_0"',
            "zynq_fsbl_bsp",
            "make.exe",
            "Makefile",
            "fsbl.elf",
            "include\\\\xparameters.h",
            "libxil.a",
        ):
            self.assertIn(token, text)

        self.assertNotIn("& $makeExe clean", text)
        self.assertIn("Remove-Item -Force -LiteralPath", text)

    def test_boot_build_references_platform_generator(self):
        text = BUILD_BOOT.read_text(encoding="ascii")
        self.assertIn("generate_ax7020_standalone_platform.ps1", text)


if __name__ == "__main__":
    unittest.main()
