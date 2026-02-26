"""
Pdf Skill - PDF Document Operations
"""

from PyPDF2 import PdfReader, PdfWriter
from pypdf import PdfReader as PyPdfReader, PdfWriter as PyPdfWriter
import io

class PdfSkill:
    name = "pdf"
    description = "Read and manipulate PDF documents"
    
    def read_pdf(self, filename):
        """Read PDF and extract text"""
        reader = PyPdfReader(filename)
        text = ""
        for page in reader.pages:
            text += page.extract_text() + "\n"
        return {"result": "read", "pages": len(reader.pages), "text": text[:1000]}
    
    def extract_text(self, filename, page_num=0):
        """Extract text from specific page"""
        reader = PyPdfReader(filename)
        if page_num < len(reader.pages):
            text = reader.pages[page_num].extract_text()
            return {"result": "extracted", "page": page_num, "text": text}
        return {"error": "Page not found"}
    
    def merge_pdfs(self, filenames, output):
        """Merge multiple PDFs"""
        writer = PyPdfWriter()
        for filename in filenames:
            reader = PyPdfReader(filename)
            for page in reader.pages:
                writer.add_page(page)
        
        with open(output, "wb") as f:
            writer.write(f)
        
        return {"result": "merged", "files": len(filenames), "output": output}
    
    def split_pdf(self, filename, page_start, page_end, output):
        """Split PDF into range"""
        reader = PyPdfReader(filename)
        writer = PyPdfWriter()
        
        for i in range(page_start, page_end + 1):
            if i < len(reader.pages):
                writer.add_page(reader.pages[i])
        
        with open(output, "wb") as f:
            writer.write(f)
        
        return {"result": "split", "pages": f"{page_start}-{page_end}", "output": output}

skill = PdfSkill()
