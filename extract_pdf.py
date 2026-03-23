import PyPDF2
import re

pdf_path = r'd:\FPGAhanjia\Hetero_SoC_2026_3\Hetero_SoC_2026\ALINX黑金AX7020开发板用户手册V2.2.pdf'

with open(pdf_path, 'rb') as f:
    reader = PyPDF2.PdfReader(f)
    print(f'Total pages: {len(reader.pages)}')
    
    text = ''
    for page in reader.pages:
        text += page.extract_text()
    
    patterns = ['以太网', 'Ethernet', 'GEM', 'ENET', 'PHY', 'RJ45', '网络']
    for pattern in patterns:
        matches = re.findall(rf'.{{0,100}}{pattern}.{{0,100}}', text, re.IGNORECASE)
        if matches:
            print(f'\n=== {pattern} ===')
            for i, m in enumerate(matches[:5]):
                print(f'{i}: {m}')
