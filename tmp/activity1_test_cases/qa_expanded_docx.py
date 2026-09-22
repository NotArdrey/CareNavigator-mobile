from __future__ import annotations

import hashlib
import zipfile
from pathlib import Path

from lxml import etree


SOURCE = Path(r"C:\Users\Neila\Downloads\Activity1_Test_Scenarios_and_Test_Cases.docx")
FINAL = Path(r"E:\Codes\CareNavigatorPh\output\Activity1_CareNavigator_PH_Expanded_Test_Scenarios_and_Test_Cases.docx")
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


with zipfile.ZipFile(FINAL) as package:
    bad = package.testzip()
    if bad:
        raise RuntimeError(f"Corrupt package member: {bad}")
    document_xml = package.read("word/document.xml")
    root = etree.fromstring(document_xml)
    text = " ".join(root.xpath("//w:t/text()", namespaces=NS))
    scenario_ids = root.xpath(
        "//w:tbl[2]//w:tr[position() > 1]/w:tc[1]//w:t/text()",
        namespaces=NS,
    )
    header_rows = root.xpath("//w:tbl/w:tr[1]/w:trPr/w:tblHeader", namespaces=NS)
    table_count = len(root.xpath("//w:tbl", namespaces=NS))

assert scenario_ids == [f"TS-{n:02d}" for n in range(1, 16)], scenario_ids
assert "TS-15" in text
assert table_count == 6, table_count
assert len(header_rows) == table_count, (len(header_rows), table_count)
for forbidden in ("BookVerse", "book search", "shopping cart", "checkout"):
    assert forbidden.casefold() not in text.casefold(), forbidden

with zipfile.ZipFile(SOURCE) as source_package, zipfile.ZipFile(FINAL) as final_package:
    source_names = set(source_package.namelist())
    final_names = set(final_package.namelist())
    assert source_names == final_names
    changed = []
    for name in sorted(source_names - {"word/document.xml"}):
        if source_package.read(name) != final_package.read(name):
            changed.append(name)
    assert not changed, changed

print(f"ZIP integrity: PASS")
print(f"Scenario matrix: PASS ({len(scenario_ids)} scenarios, TS-01 through TS-15)")
print(f"Repeated table headers: PASS ({len(header_rows)}/{table_count})")
print("Template cleanup: PASS (no BookVerse/bookstore sample terms)")
print("Package preservation: PASS (only word/document.xml changed)")
print(f"Source SHA-256: {sha256(SOURCE)}")
print(f"Final SHA-256: {sha256(FINAL)}")
print(f"Final size: {FINAL.stat().st_size} bytes")
