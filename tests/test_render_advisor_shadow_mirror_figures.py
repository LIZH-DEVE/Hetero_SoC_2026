import pathlib
import subprocess
import unittest
import uuid


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = REPO_ROOT.parent
PYTHON_EXE = pathlib.Path(r"D:\Python\python.exe")
SCRIPT_PATH = WORKSPACE_ROOT / "tools" / "render_advisor_shadow_mirror_figures.py"
TMP_ROOT = WORKSPACE_ROOT / ".tmp" / "advisor-figure-tests"


class TestRenderAdvisorShadowMirrorFigures(unittest.TestCase):
    def test_script_renders_expected_svg_files(self):
        output_dir = TMP_ROOT / str(uuid.uuid4())
        output_dir.mkdir(parents=True, exist_ok=True)

        result = subprocess.run(
            [str(PYTHON_EXE), str(SCRIPT_PATH), "--outdir", str(output_dir)],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(
            result.returncode,
            0,
            msg=f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}",
        )

        expected = {
            "novelty_boundary_matrix.svg": (
                "Novelty Boundary Matrix",
                "Packet-Atomic Visibility",
            ),
            "sm4_software_reference_compare.svg": (
                "SM4 Software Reference Comparison",
                "Kwon IEEE Access 2021",
            ),
            "abnormal_path_flow.svg": (
                "Abnormal-Path Flow",
                "downstream visibility only after commit",
            ),
        }

        for name, tokens in expected.items():
            path = output_dir / name
            self.assertTrue(path.exists(), f"missing output: {path}")
            text = path.read_text(encoding="utf-8")
            for token in tokens:
                self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
