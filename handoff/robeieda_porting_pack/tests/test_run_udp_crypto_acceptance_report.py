import unittest
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import run_udp_crypto_acceptance_report as report


SAMPLE_OUTPUT = """
=== PING ===
$ ping 192.168.1.20 -n 4
exit_code=0

=== CONTROL_REGRESSION ===
$ py run_udp_crypto_control_regression.py --bench-timeout 10
CASE hello
CASE bench aes
algo=aes repeats=8
len=16 sw_us=266 hw_us=58
len=1472 sw_us=19181 hw_us=3497
CASE bench sm4
algo=sm4 repeats=8
len=16 sw_us=142 hw_us=55
len=1472 sw_us=7048 hw_us=3132
CONTROL_REGRESSION_PASS
exit_code=0

ACCEPTANCE_PASS
"""


class AcceptanceReportTests(unittest.TestCase):
    def test_parse_acceptance_output_extracts_bench_and_pass(self) -> None:
        summary = report.parse_acceptance_output(SAMPLE_OUTPUT)

        self.assertEqual(summary["overall"], "PASS")
        self.assertTrue(summary["control_regression_pass"])
        self.assertEqual(summary["bench"]["aes"][0]["length"], 16)
        self.assertEqual(summary["bench"]["aes"][1]["hw_us"], 3497)
        self.assertEqual(summary["bench"]["sm4"][1]["sw_us"], 7048)

    def test_render_markdown_includes_speedup(self) -> None:
        summary = report.parse_acceptance_output(SAMPLE_OUTPUT)

        markdown = report.render_markdown(summary, ["py", "run_udp_crypto_acceptance.py"], raw_log_path=__import__("pathlib").Path("raw.log"))

        self.assertIn("# AX7020 UDP Crypto Acceptance Report", markdown)
        self.assertIn("| 1472 | 19181 | 3497 | 5.48x |", markdown)
        self.assertIn("| 1472 | 7048 | 3132 | 2.25x |", markdown)


if __name__ == "__main__":
    unittest.main()
