from pypdf import PdfReader
pdf = PdfReader(r'D:\FPGAhanjia\Hetero_SoC_2026_3\ALINX黑金AX7020开发板用户手册V2.2.pdf')
keys = ['RTL8211', 'RGMII', '千兆', '以太网', 'MDIO', 'MDC']
printed = 0
for i, p in enumerate(pdf.pages):
    text = p.extract_text() or ''
    if any(k.lower() in text.lower() for k in keys):
        print(f'=== PAGE {i+1} ===')
        lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
        for idx, line in enumerate(lines):
            if any(k.lower() in line.lower() for k in keys):
                for j in range(max(0, idx-2), min(len(lines), idx+4)):
                    print(lines[j])
                print('---')
                printed += 1
                if printed >= 30:
                    raise SystemExit
