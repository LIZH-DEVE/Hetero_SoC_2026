from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


AUTHORITATIVE_RELATIVE_BIT = Path("HCS_SOC.runs") / "impl_1" / "design_1_wrapper.bit"
LAUNCH_JSON_PATH = Path("crypto_test_app") / "_ide" / ".theia" / "launch.json"
DOWNLOAD_TCL_PATH = Path("download_bitstream.tcl")
PUBLISHED_LATEST_RELATIVE_BIT = (
    Path("artifacts") / "bitstreams" / "latest" / "design_1_wrapper.bit"
)
PUBLISHED_ARCHIVE_DIR = Path("artifacts") / "bitstreams" / "archive"
LEGACY_COPY_PATHS = [
    Path("platform") / "export" / "platform" / "hw" / "design_1_wrapper.bit",
    Path("crypto_test_app") / "_ide" / "bitstream" / "design_1_wrapper.bit",
]
EXPECTED_LAUNCH_BITSTREAM = (
    r"${workspaceFolder}\HCS_SOC.runs\impl_1\design_1_wrapper.bit"
)
TCL_SET_PATTERN = re.compile(
    r'^\s*set\s+([A-Za-z_][A-Za-z0-9_]*)\s+"([^"]+)"\s*$'
)
TCL_FPGA_PATTERN = re.compile(r"^\s*fpga\s+-f\s+(.+?)\s*$")


@dataclass
class VerificationIssue:
    message: str


@dataclass
class VerificationReport:
    workspace: Path
    authoritative_bit: Path
    launch_json: Path
    download_tcl: Path
    authoritative_hash: str | None = None
    errors: list[VerificationIssue] = field(default_factory=list)
    warnings: list[VerificationIssue] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


@dataclass
class PublishResult:
    authoritative_bit: Path
    latest_bit: Path
    archive_bit: Path


def _normalize_path_string(value: str) -> str:
    return value.strip().strip('"').replace("\\", "/").rstrip("/").lower()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_launch_bitstream(launch_json_path: Path) -> str | None:
    data = json.loads(launch_json_path.read_text(encoding="utf-8"))
    for config in data.get("configurations", []):
        target_setup = config.get("targetSetup", {})
        bitstream_file = target_setup.get("bitstreamFile")
        if isinstance(bitstream_file, str):
            return bitstream_file
    return None


def _extract_download_bitstream(download_tcl_path: Path) -> str | None:
    variables: dict[str, str] = {}
    for raw_line in download_tcl_path.read_text(encoding="utf-8").splitlines():
        set_match = TCL_SET_PATTERN.match(raw_line)
        if set_match:
            variables[set_match.group(1)] = set_match.group(2)
            continue

        fpga_match = TCL_FPGA_PATTERN.match(raw_line)
        if not fpga_match:
            continue

        value = fpga_match.group(1).strip()
        if value.startswith("$"):
            return variables.get(value[1:])
        return value.strip('"')
    return None


def _expected_download_bitstream(workspace: Path) -> str:
    return (workspace / AUTHORITATIVE_RELATIVE_BIT).resolve().as_posix()


def verify_workspace(workspace: Path | str) -> VerificationReport:
    workspace_path = Path(workspace).resolve()
    authoritative_bit = workspace_path / AUTHORITATIVE_RELATIVE_BIT
    launch_json = workspace_path / LAUNCH_JSON_PATH
    download_tcl = workspace_path / DOWNLOAD_TCL_PATH

    report = VerificationReport(
        workspace=workspace_path,
        authoritative_bit=authoritative_bit,
        launch_json=launch_json,
        download_tcl=download_tcl,
    )

    if not authoritative_bit.exists():
        report.errors.append(
            VerificationIssue(
                f"authoritative bitstream is missing: {authoritative_bit}"
            )
        )
        return report

    report.authoritative_hash = _sha256(authoritative_bit)

    if not launch_json.exists():
        report.errors.append(
            VerificationIssue(f"launch.json is missing: {launch_json}")
        )
    else:
        actual_launch_bitstream = _load_launch_bitstream(launch_json)
        if actual_launch_bitstream != EXPECTED_LAUNCH_BITSTREAM:
            report.errors.append(
                VerificationIssue(
                    "launch.json bitstreamFile does not point to "
                    f"{EXPECTED_LAUNCH_BITSTREAM}: {actual_launch_bitstream}"
                )
            )

    if not download_tcl.exists():
        report.errors.append(
            VerificationIssue(f"download_bitstream.tcl is missing: {download_tcl}")
        )
    else:
        actual_download_bitstream = _extract_download_bitstream(download_tcl)
        expected_download_bitstream = _expected_download_bitstream(workspace_path)
        if actual_download_bitstream is None:
            report.errors.append(
                VerificationIssue(
                    "download_bitstream.tcl does not contain an fpga -f bitstream path"
                )
            )
        elif _normalize_path_string(actual_download_bitstream) != _normalize_path_string(
            expected_download_bitstream
        ):
            report.errors.append(
                VerificationIssue(
                    "download_bitstream.tcl fpga -f path does not point to the "
                    f"authoritative impl_1 bitstream: {actual_download_bitstream}"
                )
            )

    latest_bit = workspace_path / PUBLISHED_LATEST_RELATIVE_BIT
    if latest_bit.exists():
        latest_hash = _sha256(latest_bit)
        if latest_hash != report.authoritative_hash:
            report.errors.append(
                VerificationIssue(
                    "published latest bitstream hash does not match the "
                    f"authoritative bitstream: {latest_bit}"
                )
            )
    else:
        report.warnings.append(
            VerificationIssue(
                f"published latest bitstream is not present yet: {latest_bit}"
            )
        )

    for legacy_copy in LEGACY_COPY_PATHS:
        legacy_path = workspace_path / legacy_copy
        if not legacy_path.exists():
            continue
        legacy_hash = _sha256(legacy_path)
        if legacy_hash != report.authoritative_hash:
            report.warnings.append(
                VerificationIssue(
                    "legacy copy differs from the authoritative impl_1 bitstream "
                    f"(expected unless you explicitly republish it): {legacy_path}"
                )
            )

    return report


def _unique_archive_path(workspace: Path, timestamp: str) -> Path:
    archive_dir = workspace / PUBLISHED_ARCHIVE_DIR
    archive_dir.mkdir(parents=True, exist_ok=True)

    candidate = archive_dir / f"design_1_wrapper_{timestamp}.bit"
    if not candidate.exists():
        return candidate

    suffix = 1
    while True:
        candidate = archive_dir / f"design_1_wrapper_{timestamp}_{suffix}.bit"
        if not candidate.exists():
            return candidate
        suffix += 1


def publish_bitstream(workspace: Path | str) -> PublishResult:
    workspace_path = Path(workspace).resolve()
    authoritative_bit = workspace_path / AUTHORITATIVE_RELATIVE_BIT
    if not authoritative_bit.exists():
        raise FileNotFoundError(f"authoritative bitstream is missing: {authoritative_bit}")

    latest_bit = workspace_path / PUBLISHED_LATEST_RELATIVE_BIT
    latest_bit.parent.mkdir(parents=True, exist_ok=True)

    source_mtime = datetime.fromtimestamp(authoritative_bit.stat().st_mtime)
    archive_bit = _unique_archive_path(
        workspace_path,
        source_mtime.strftime("%Y%m%d_%H%M%S"),
    )

    shutil.copy2(authoritative_bit, latest_bit)
    shutil.copy2(authoritative_bit, archive_bit)

    return PublishResult(
        authoritative_bit=authoritative_bit,
        latest_bit=latest_bit,
        archive_bit=archive_bit,
    )


def _resolve_workspace(value: str | None) -> Path:
    if value:
        return Path(value).resolve()

    cwd = Path.cwd().resolve()
    if (cwd / "HCS_SOC.xpr").exists():
        return cwd
    if (cwd / "HCS_SOC" / "HCS_SOC.xpr").exists():
        return (cwd / "HCS_SOC").resolve()
    return cwd


def _print_report(report: VerificationReport) -> None:
    print(f"workspace: {report.workspace}")
    print(f"authoritative bit: {report.authoritative_bit}")
    if report.authoritative_hash:
        print(f"authoritative sha256: {report.authoritative_hash}")

    if report.errors:
        print("errors:")
        for issue in report.errors:
            print(f"  - {issue.message}")
    else:
        print("errors: none")

    if report.warnings:
        print("warnings:")
        for issue in report.warnings:
            print(f"  - {issue.message}")
    else:
        print("warnings: none")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Manage and verify the authoritative design_1_wrapper.bit flow."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    verify_parser = subparsers.add_parser("verify", help="verify active bitstream sources")
    verify_parser.add_argument(
        "--workspace",
        help="HCS_SOC workspace path",
    )

    publish_parser = subparsers.add_parser("publish", help="publish an external latest/archive copy")
    publish_parser.add_argument(
        "--workspace",
        help="HCS_SOC workspace path",
    )

    args = parser.parse_args()
    workspace = _resolve_workspace(args.workspace)

    if args.command == "verify":
        report = verify_workspace(workspace)
        _print_report(report)
        return 0 if report.ok else 1

    publish_result = publish_bitstream(workspace)
    print(f"authoritative bit: {publish_result.authoritative_bit}")
    print(f"latest bit: {publish_result.latest_bit}")
    print(f"archive bit: {publish_result.archive_bit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
