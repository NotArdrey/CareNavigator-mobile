"""Small compatibility shim for the bundled DOCX renderer.

The workstation has LibreOffice but not Poppler.  The documents skill imports
``pdf2image`` for two functions, so this task-local module implements the same
surface with PyMuPDF and Pillow while leaving the managed skill package intact.
"""

from pathlib import Path

import fitz
from PIL import Image


def pdfinfo_from_path(pdf_path):
    document = fitz.open(pdf_path)
    try:
        page = document[0]
        rect = page.rect
        return {
            "Pages": len(document),
            "Page size": f"{rect.width:g} x {rect.height:g} pts",
        }
    finally:
        document.close()


def convert_from_path(
    pdf_path,
    dpi=200,
    fmt="png",
    thread_count=1,
    output_folder=None,
    paths_only=False,
    output_file="page",
    **_kwargs,
):
    if fmt.lower() != "png":
        raise ValueError("This compatibility shim supports PNG output only.")

    output_dir = Path(output_folder or Path(pdf_path).parent)
    output_dir.mkdir(parents=True, exist_ok=True)
    document = fitz.open(pdf_path)
    results = []
    try:
        scale = float(dpi) / 72.0
        matrix = fitz.Matrix(scale, scale)
        for page_number, page in enumerate(document, start=1):
            pixmap = page.get_pixmap(matrix=matrix, alpha=False)
            image_path = output_dir / f"{output_file}0000-{page_number:02d}.png"
            pixmap.save(str(image_path))
            results.append(str(image_path) if paths_only else Image.open(image_path))
    finally:
        document.close()
    return results
