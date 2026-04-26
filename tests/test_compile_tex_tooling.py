import pathlib
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = REPO_ROOT.parent
COMPILE_PS1 = WORKSPACE_ROOT / "tools" / "compile-tex.ps1"
COMPILE_CMD = WORKSPACE_ROOT / "tools" / "compile-tex.cmd"


class TestCompileTexTooling(unittest.TestCase):
    def test_compile_tex_ps1_defaults_to_active_jsa_main_draft(self):
        text = COMPILE_PS1.read_text(encoding="utf-8")

        for token in (
            "function Resolve-DefaultTexPath",
            'Join-Path $workspaceRoot "Hetero_SoC_2026\\doc\\jsa_paper\\paper_jsa_frontend_contract.tex"',
            "$TexPath = Resolve-DefaultTexPath",
        ):
            self.assertIn(token, text)

    def test_compile_tex_ps1_does_not_force_interactive_path_prompt(self):
        text = COMPILE_PS1.read_text(encoding="utf-8")

        self.assertNotIn("$TexPath = Read-Host 'Enter the full path to the .tex file'", text)
        self.assertIn("Read-Host 'Enter the full path to the .tex file (press Enter to use the default)'", text)

    def test_compile_tex_cmd_launches_noninteractive_default_build(self):
        text = COMPILE_CMD.read_text(encoding="utf-8")

        self.assertNotIn("-NoExit", text)
        self.assertIn("paper_jsa_frontend_contract.tex", text)
        self.assertIn("-TexPath", text)


if __name__ == "__main__":
    unittest.main()
