"""
Docx Skill - Microsoft Word Document Operations
"""

import os
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH

class DocxSkill:
    name = "docx"
    description = "Create and edit Microsoft Word documents"
    
    def create_docx(self, filename, content="", title=""):
        """Create a new Word document"""
        doc = Document()
        
        if title:
            heading = doc.add_heading(title, 0)
            heading.alignment = WD_ALIGN_PARAGRAPH.CENTER
        
        if content:
            doc.add_paragraph(content)
        
        doc.save(filename)
        return {"result": "created", "file": filename}
    
    def add_heading(self, filename, text, level=1):
        """Add heading to document"""
        doc = Document(filename)
        doc.add_heading(text, level)
        doc.save(filename)
        return {"result": "added", "text": text}
    
    def add_paragraph(self, filename, text, bold=False):
        """Add paragraph to document"""
        doc = Document(filename)
        p = doc.add_paragraph(text)
        if bold:
            p.runs[0].bold = True
        doc.save(filename)
        return {"result": "added", "text": text}
    
    def add_image(self, filename, image_path, width=4):
        """Add image to document"""
        doc = Document(filename)
        doc.add_picture(image_path, width=Inches(width))
        doc.save(filename)
        return {"result": "added", "image": image_path}
    
    def add_table(self, filename, data):
        """Add table to document"""
        doc = Document(filename)
        rows = len(data)
        cols = len(data[0]) if rows > 0 else 0
        
        table = doc.add_table(rows=rows, cols=cols)
        table.style = 'Light Grid Accent 1'
        
        for i, row_data in enumerate(data):
            for j, cell_data in enumerate(row_data):
                table.rows[i].cells[j].text = str(cell_data)
        
        doc.save(filename)
        return {"result": "added", "rows": rows}

skill = DocxSkill()
