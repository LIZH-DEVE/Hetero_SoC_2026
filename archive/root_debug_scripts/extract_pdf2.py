import pdfplumber
import re

pdf_path = r'd:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\ALINX黑金AX7020开发板用户手册V2.2.pdf'

with pdfplumber.open(pdf_path) as pdf:
    print(f'Total pages: {len(pdf.pages)}')
    
    patterns = ['RESET', 'reset', 'PHY', 'phy', '以太网', 'Ethernet', 'ENET', 'RGMII', 'GMII', 'MIO']
    
    for i, page in enumerate(pdf.pages):
        text = page.extract_text()
        if text:
            for pattern in patterns:
                if pattern in text:
                    matches = re.findall(rf'.{{0,100}}{pattern}.{{0,100}}', text)
                    if matches:
                        print(f'\n=== Page {i+1}: {pattern} ===')
                        for m in matches[:3]:
                            print(m)
