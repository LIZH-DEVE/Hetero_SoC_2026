from __future__ import annotations

import json
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
MANIFEST_PATH = THIS_DIR / "dma_contract_manifest.json"
C_HEADER_PATH = THIS_DIR / "dma_hw_regs.h"
SV_PKG_PATH = THIS_DIR.parent / "rtl" / "inc" / "dma_csr_pkg.sv"


def load_manifest(path: Path = MANIFEST_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _hex32(value: int) -> str:
    return f"0x{value:08X}u"


def _hex_sv(value: int) -> str:
    return f"32'h{value:08X}"


def _macro_name(prefix: str, name: str) -> str:
    return f"{prefix}_{name}"


def _emit_string_metadata(lines: list[str], prefix: str, values: list[str], *, c_mode: bool) -> None:
    count_suffix = "u" if c_mode else ""
    if c_mode:
        lines.append(f"#define {prefix}_COUNT {len(values)}{count_suffix}")
        for idx, value in enumerate(values):
            lines.append(f'#define {prefix}_{idx} "{value}"')
    else:
        lines.append(f"  localparam int unsigned {prefix}_COUNT = {len(values)};")
        for idx, value in enumerate(values):
            lines.append(f'  localparam string {prefix}_{idx} = "{value}";')
    lines.append("")


def render_c_header(manifest: dict) -> str:
    csr_offsets = manifest["csr"]["offsets"]
    ctrl_bits = manifest["csr"]["ctrl_bits"]
    write_values = manifest["csr"].get("write_values", {})
    desc = manifest["descriptor"]
    cache = manifest["cache"]
    raw_copy = manifest["raw_copy"]
    submission = manifest["sequences"]["submission"]
    validation = manifest["sequences"]["validation"]
    soft_reset = manifest["soft_reset"]
    irq = manifest.get("irq", {})

    lines: list[str] = []
    lines.append("#ifndef DMA_HW_REGS_H")
    lines.append("#define DMA_HW_REGS_H")
    lines.append("")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.append(f"#define DMA_CONTRACT_VERSION {manifest['contract_version']}u")
    lines.append("")
    for name, value in csr_offsets.items():
        lines.append(f"#define {_macro_name('DMA_CSR', name)} {_hex32(value)}")
    for name, value in write_values.items():
        lines.append(f"#define {_macro_name('DMA_CSR', name)} {_hex32(value)}")
    lines.append("")
    for name, bit in ctrl_bits.items():
        lines.append(f"#define {_macro_name('DMA_CTRL_BIT', name)} {bit}u")
        lines.append(f"#define {_macro_name('DMA_CTRL', name)} (1u << {_macro_name('DMA_CTRL_BIT', name)})")
    lines.append("")
    lines.append(f"#define DMA_DESC_SIZE_BYTES {desc['size_bytes']}u")
    lines.append(f"#define DMA_DESC_WORD_BYTES {desc['word_bytes']}u")
    lines.append("")
    for field in desc["fields"]:
        lines.append(
            f"#define {_macro_name('DMA_DESC', field['name'] + '_BYTE_OFFSET')} {_hex32(field['byte_offset'])}"
        )
    lines.append("")
    for name, bit in desc["ctrl_bits"].items():
        lines.append(f"#define {_macro_name('DMA_DESC_CTRL_BIT', name)} {bit}u")
        lines.append(
            f"#define {_macro_name('DMA_DESC_CTRL', name)} (1u << {_macro_name('DMA_DESC_CTRL_BIT', name)})"
        )
    for name, mask in desc["ctrl_masks"].items():
        lines.append(f"#define {_macro_name('DMA_DESC_CTRL_MASK', name)} {_hex32(mask)}")
    lines.append("")
    for name, bit in desc["csw_bits"].items():
        lines.append(f"#define {_macro_name('DMA_DESC_CSW_BIT', name)} {bit}u")
        lines.append(
            f"#define {_macro_name('DMA_DESC_CSW', name)} (1u << {_macro_name('DMA_DESC_CSW_BIT', name)})"
        )
    for name, mask in desc["csw_masks"].items():
        lines.append(f"#define {_macro_name('DMA_DESC_CSW_MASK', name)} {_hex32(mask)}")
    if "STS" in desc["csw_masks"]:
        lines.append(f"#define DMA_DESC_CSW_STS_MASK DMA_DESC_CSW_MASK_STS")
    for name, value in desc.get("csw_status", {}).items():
        lines.append(f"#define {_macro_name('DMA_DESC_CSW_STS', name)} {_hex32(value)}")
    lines.append("")
    lines.append(f"#define DMA_CACHELINE_BYTES {cache['line_bytes']}u")
    lines.append(f"#define DMA_ALIGNMENT_BYTES {cache['alignment_bytes']}u")
    lines.append(f"#define DMA_RAW_COPY_LEN_MULTIPLE {cache['raw_copy_len_multiple']}u")
    lines.append("")
    lines.append(f"#define DMA_RAW_COPY_FIFO_DEPTH {raw_copy['fifo_depth']}u")
    lines.append(f'#define DMA_RAW_COPY_FIFO_MEMORY "{raw_copy["fifo_memory"]}"')
    lines.append(f"#define DMA_RAW_COPY_TLAST_WIDTH {raw_copy['tlast_width']}u")
    lines.append("")
    _emit_string_metadata(lines, "DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL", raw_copy["required_axis_signals"], c_mode=True)
    _emit_string_metadata(lines, "DMA_SUBMISSION_STEP", submission, c_mode=True)
    _emit_string_metadata(lines, "DMA_VALIDATION_STEP", validation, c_mode=True)
    _emit_string_metadata(lines, "DMA_SOFT_RESET_CLEAR", soft_reset["clears"], c_mode=True)
    _emit_string_metadata(lines, "DMA_SOFT_RESET_RETRY_REQUIREMENT", soft_reset["retry_requires"], c_mode=True)
    if irq:
        for name, bit in irq.get("enable_bits", {}).items():
            lines.append(f"#define {_macro_name('DMA_IRQ_ENABLE_BIT', name)} {bit}u")
            lines.append(
                f"#define {_macro_name('DMA_IRQ_ENABLE', name)} (1u << {_macro_name('DMA_IRQ_ENABLE_BIT', name)})"
            )
        for name, bit in irq.get("status_bits", {}).items():
            lines.append(f"#define {_macro_name('DMA_IRQ_STATUS_BIT', name)} {bit}u")
            lines.append(
                f"#define {_macro_name('DMA_IRQ_STATUS', name)} (1u << {_macro_name('DMA_IRQ_STATUS_BIT', name)})"
            )
        for name, bit in irq.get("ack_bits", {}).items():
            lines.append(f"#define {_macro_name('DMA_IRQ_ACK_BIT', name)} {bit}u")
            lines.append(
                f"#define {_macro_name('DMA_IRQ_ACK', name)} (1u << {_macro_name('DMA_IRQ_ACK_BIT', name)})"
            )
        lines.append("")
        lines.append(f"#define DMA_IRQ_DEFAULT_COALESCE_COUNT {irq['default_coalesce_count']}u")
        lines.append(f"#define DMA_IRQ_DEFAULT_COALESCE_TIMEOUT_CYCLES {irq['default_coalesce_timeout_cycles']}u")
        lines.append("")
        _emit_string_metadata(lines, "DMA_IRQ_COMPLETION_EVENT_REQUIREMENT", irq["completion_event_requires"], c_mode=True)

    lines.append("typedef struct __attribute__((aligned(DMA_ALIGNMENT_BYTES))) dma_desc_s {")
    for field in desc["fields"]:
        lines.append(f"    {field['ctype']} {field['name'].lower()};")
    lines.append("} dma_desc_t;")
    lines.append("")
    lines.append("#endif")
    lines.append("")
    return "\n".join(lines)


def render_sv_package(manifest: dict) -> str:
    csr_offsets = manifest["csr"]["offsets"]
    ctrl_bits = manifest["csr"]["ctrl_bits"]
    write_values = manifest["csr"].get("write_values", {})
    desc = manifest["descriptor"]
    cache = manifest["cache"]
    raw_copy = manifest["raw_copy"]
    submission = manifest["sequences"]["submission"]
    validation = manifest["sequences"]["validation"]
    soft_reset = manifest["soft_reset"]
    irq = manifest.get("irq", {})

    lines: list[str] = []
    lines.append("package dma_csr_pkg;")
    lines.append("")
    lines.append(f"  localparam int unsigned DMA_CONTRACT_VERSION = {manifest['contract_version']};")
    lines.append("")
    for name, value in csr_offsets.items():
        lines.append(f"  localparam logic [31:0] DMA_CSR_{name} = {_hex_sv(value)};")
    for name, value in write_values.items():
        lines.append(f"  localparam logic [31:0] DMA_CSR_{name} = {_hex_sv(value)};")
    lines.append("")
    for name, bit in ctrl_bits.items():
        lines.append(f"  localparam int unsigned DMA_CTRL_BIT_{name} = {bit};")
        lines.append(f"  localparam logic [31:0] DMA_CTRL_{name} = 32'h00000001 << DMA_CTRL_BIT_{name};")
    lines.append("")
    lines.append(f"  localparam int unsigned DMA_DESC_SIZE_BYTES = {desc['size_bytes']};")
    lines.append(f"  localparam int unsigned DMA_DESC_WORD_BYTES = {desc['word_bytes']};")
    lines.append("")
    for field in desc["fields"]:
        lines.append(
            f"  localparam int unsigned DMA_DESC_{field['name']}_BYTE_OFFSET = {field['byte_offset']};"
        )
    lines.append("")
    for name, bit in desc["ctrl_bits"].items():
        lines.append(f"  localparam int unsigned DMA_DESC_CTRL_BIT_{name} = {bit};")
        lines.append(f"  localparam logic [31:0] DMA_DESC_CTRL_{name} = 32'h00000001 << DMA_DESC_CTRL_BIT_{name};")
    for name, mask in desc["ctrl_masks"].items():
        lines.append(f"  localparam logic [31:0] DMA_DESC_CTRL_MASK_{name} = {_hex_sv(mask)};")
    lines.append("")
    for name, bit in desc["csw_bits"].items():
        lines.append(f"  localparam int unsigned DMA_DESC_CSW_BIT_{name} = {bit};")
        lines.append(f"  localparam logic [31:0] DMA_DESC_CSW_{name} = 32'h00000001 << DMA_DESC_CSW_BIT_{name};")
    for name, mask in desc["csw_masks"].items():
        lines.append(f"  localparam logic [31:0] DMA_DESC_CSW_MASK_{name} = {_hex_sv(mask)};")
    if "STS" in desc["csw_masks"]:
        lines.append("  localparam logic [31:0] DMA_DESC_CSW_STS_MASK = DMA_DESC_CSW_MASK_STS;")
    for name, value in desc.get("csw_status", {}).items():
        lines.append(f"  localparam logic [31:0] DMA_DESC_CSW_STS_{name} = {_hex_sv(value)};")
    lines.append("")
    lines.append(f"  localparam int unsigned DMA_CACHELINE_BYTES = {cache['line_bytes']};")
    lines.append(f"  localparam int unsigned DMA_ALIGNMENT_BYTES = {cache['alignment_bytes']};")
    lines.append(f"  localparam int unsigned DMA_RAW_COPY_LEN_MULTIPLE = {cache['raw_copy_len_multiple']};")
    lines.append(f"  localparam int unsigned DMA_RAW_COPY_FIFO_DEPTH = {raw_copy['fifo_depth']};")
    lines.append(f'  localparam string DMA_RAW_COPY_FIFO_MEMORY = "{raw_copy["fifo_memory"]}";')
    lines.append(f"  localparam int unsigned DMA_RAW_COPY_TLAST_WIDTH = {raw_copy['tlast_width']};")
    lines.append("")
    _emit_string_metadata(lines, "DMA_RAW_COPY_REQUIRED_AXIS_SIGNAL", raw_copy["required_axis_signals"], c_mode=False)

    lines.append("  typedef struct packed {")
    for field in reversed(desc["fields"]):
        lines.append(f"    {field['sv_type']} {field['name'].lower()};")
    lines.append("  } dma_desc_t;")
    lines.append("")
    _emit_string_metadata(lines, "DMA_SUBMISSION_STEP", submission, c_mode=False)
    _emit_string_metadata(lines, "DMA_VALIDATION_STEP", validation, c_mode=False)
    _emit_string_metadata(lines, "DMA_SOFT_RESET_CLEAR", soft_reset["clears"], c_mode=False)
    _emit_string_metadata(lines, "DMA_SOFT_RESET_RETRY_REQUIREMENT", soft_reset["retry_requires"], c_mode=False)
    if irq:
        for name, bit in irq.get("enable_bits", {}).items():
            lines.append(f"  localparam int unsigned DMA_IRQ_ENABLE_BIT_{name} = {bit};")
            lines.append(
                f"  localparam logic [31:0] DMA_IRQ_ENABLE_{name} = 32'h00000001 << DMA_IRQ_ENABLE_BIT_{name};"
            )
        for name, bit in irq.get("status_bits", {}).items():
            lines.append(f"  localparam int unsigned DMA_IRQ_STATUS_BIT_{name} = {bit};")
            lines.append(
                f"  localparam logic [31:0] DMA_IRQ_STATUS_{name} = 32'h00000001 << DMA_IRQ_STATUS_BIT_{name};"
            )
        for name, bit in irq.get("ack_bits", {}).items():
            lines.append(f"  localparam int unsigned DMA_IRQ_ACK_BIT_{name} = {bit};")
            lines.append(
                f"  localparam logic [31:0] DMA_IRQ_ACK_{name} = 32'h00000001 << DMA_IRQ_ACK_BIT_{name};"
            )
        lines.append("")
        lines.append(f"  localparam int unsigned DMA_IRQ_DEFAULT_COALESCE_COUNT = {irq['default_coalesce_count']};")
        lines.append(
            f"  localparam int unsigned DMA_IRQ_DEFAULT_COALESCE_TIMEOUT_CYCLES = {irq['default_coalesce_timeout_cycles']};"
        )
        lines.append("")
        _emit_string_metadata(lines, "DMA_IRQ_COMPLETION_EVENT_REQUIREMENT", irq["completion_event_requires"], c_mode=False)
    lines.append("endpackage")
    lines.append("")
    return "\n".join(lines)


def write_artifacts(manifest: dict) -> None:
    C_HEADER_PATH.write_text(render_c_header(manifest), encoding="utf-8", newline="\n")
    SV_PKG_PATH.write_text(render_sv_package(manifest), encoding="utf-8", newline="\n")


def main() -> None:
    manifest = load_manifest()
    write_artifacts(manifest)


if __name__ == "__main__":
    main()
