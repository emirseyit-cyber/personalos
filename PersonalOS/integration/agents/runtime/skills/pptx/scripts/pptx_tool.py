"""
Pptx Skill - Microsoft PowerPoint Operations
"""

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

class PptxSkill:
    name = "pptx"
    description = "Create and edit PowerPoint presentations"
    
    def create_pptx(self, filename):
        """Create a new presentation"""
        prs = Presentation()
        prs.save(filename)
        return {"result": "created", "file": filename}
    
    def add_slide(self, filename, layout=1, title=""):
        """Add a slide"""
        prs = Presentation(filename)
        slide = prs.slides.add_slide(prs.slide_layouts[layout])
        
        if title:
            title_shape = slide.shapes.title
            title_shape.text = title
        
        prs.save(filename)
        return {"result": "added", "title": title}
    
    def add_content(self, filename, text, level=0):
        """Add content to slide"""
        prs = Presentation(filename)
        slide = prs.slides[-1]
        
        body = slide.placeholders[1]
        tf = body.text_frame
        p = tf.add_paragraph()
        p.text = text
        p.level = level
        
        prs.save(filename)
        return {"result": "added", "text": text}
    
    def add_image(self, filename, image_path, left=2, top=2, width=4):
        """Add image to slide"""
        prs = Presentation(filename)
        slide = prs.slides[-1]
        slide.shapes.add_picture(image_path, Inches(left), Inches(top), width=Inches(width))
        prs.save(filename)
        return {"result": "added", "image": image_path}

skill = PptxSkill()
