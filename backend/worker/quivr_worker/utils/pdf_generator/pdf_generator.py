import os

from fpdf import FPDF, XPos, YPos
from pydantic import BaseModel


class PDFModel(BaseModel):
    title: str
    content: str


class PDFGenerator(FPDF):
    def __init__(self, pdf_model: PDFModel, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.pdf_model = pdf_model
        self.add_font(
            "DejaVu",
            "",
            os.path.join(os.path.dirname(__file__), "font/DejaVuSansCondensed.ttf"),
        )
        self.add_font(
            "DejaVu",
            "B",
            os.path.join(
                os.path.dirname(__file__), "font/DejaVuSansCondensed-Bold.ttf"
            ),
        )
        self.add_font(
            "DejaVu",
            "I",
            os.path.join(
                os.path.dirname(__file__), "font/DejaVuSansCondensed-Oblique.ttf"
            ),
        )

    def header(self):
        # Logo
        logo_path = os.path.join(os.path.dirname(__file__), "logo.png")
        self.image(logo_path, 10, 10, 20)  # Adjust size as needed

        # Move cursor to right of image
        self.set_xy(20, 15)

        # Title
        self.set_font("DejaVu", "B", 12)
        self.multi_cell(0, 10, self.pdf_model.title, align="C")
        self.ln(5)  # Padding after title

    def footer(self):
        self.set_y(-15)

        self.set_font("DejaVu", "I", 8)
        self.set_text_color(169, 169, 169)
        self.cell(80, 10, "Generated by Quivr", 0, 0, "C")
        self.set_font("DejaVu", "U", 8)
        self.set_text_color(0, 0, 255)
        self.cell(30, 10, "quivr.app", 0, 0, "C", link="https://quivr.app")
        self.cell(0, 10, "Github", 0, 1, "C", link="https://github.com/quivrhq/quivr")

    def chapter_body(self):
        self.set_font("DejaVu", "", 12)
        self.multi_cell(
            0,
            10,
            self.pdf_model.content,
            markdown=True,
            new_x=XPos.RIGHT,
            new_y=YPos.TOP,
        )
        self.ln()

    def print_pdf(self):
        self.add_page()
        self.chapter_body()


if __name__ == "__main__":
    pdf_model = PDFModel(
        title="Summary of Legal Services Rendered by Orrick",
        content="""
**Summary:** 
""",
    )
    pdf = PDFGenerator(pdf_model)
    pdf.print_pdf()
    pdf.output("simple.pdf")
