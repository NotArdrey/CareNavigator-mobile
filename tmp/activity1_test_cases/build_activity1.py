from __future__ import annotations

import copy
import os
import shutil
import tempfile
import zipfile
from pathlib import Path

from lxml import etree


REFERENCE = Path(r"C:\Users\Neila\Downloads\Activity1_Test_Scenarios_and_Test_Cases.docx")
OUTPUT = Path(r"E:\Codes\CareNavigatorPh\output\Activity1_CareNavigator_PH_Expanded_Test_Scenarios_and_Test_Cases.docx")

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
XML_NS = "http://www.w3.org/XML/1998/namespace"
NS = {"w": W_NS}


def qn(local: str) -> str:
    return f"{{{W_NS}}}{local}"


def paragraph_text(paragraph: etree._Element) -> str:
    return "".join(paragraph.xpath(".//w:t/text()", namespaces=NS))


def set_paragraph_text(paragraph: etree._Element, value: str) -> None:
    first_run = paragraph.find(qn("r"))
    preserved_rpr = None
    if first_run is not None:
        run_properties = first_run.find(qn("rPr"))
        if run_properties is not None:
            preserved_rpr = copy.deepcopy(run_properties)

    for child in list(paragraph):
        if child.tag != qn("pPr"):
            paragraph.remove(child)

    run = etree.SubElement(paragraph, qn("r"))
    if preserved_rpr is not None:
        run.append(preserved_rpr)

    lines = value.split("\n")
    for index, line in enumerate(lines):
        if index:
            etree.SubElement(run, qn("br"))
        text = etree.SubElement(run, qn("t"))
        if line.startswith(" ") or line.endswith(" "):
            text.set(f"{{{XML_NS}}}space", "preserve")
        text.text = line


def set_cell_text(cell: etree._Element, value: str) -> None:
    paragraphs = cell.xpath("./w:p", namespaces=NS)
    if not paragraphs:
        paragraphs = [etree.SubElement(cell, qn("p"))]
    set_paragraph_text(paragraphs[0], value)
    for extra in paragraphs[1:]:
        cell.remove(extra)


def replace_body_paragraphs(
    root: etree._Element, old: str, new: str, expected_count: int = 1
) -> None:
    matches = [
        paragraph
        for paragraph in root.xpath("//w:body/w:p", namespaces=NS)
        if paragraph_text(paragraph) == old
    ]
    if len(matches) != expected_count:
        raise RuntimeError(
            f"Expected {expected_count} paragraph(s) matching {old!r}; found {len(matches)}"
        )
    for match in matches:
        set_paragraph_text(match, new)


def set_page_break_before(root: etree._Element, text: str) -> None:
    matches = [
        paragraph
        for paragraph in root.xpath("//w:body/w:p", namespaces=NS)
        if paragraph_text(paragraph) == text
    ]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one paragraph matching {text!r}; found {len(matches)}")
    paragraph = matches[0]
    properties = paragraph.find(qn("pPr"))
    if properties is None:
        properties = etree.Element(qn("pPr"))
        paragraph.insert(0, properties)
    if properties.find(qn("pageBreakBefore")) is None:
        properties.append(etree.Element(qn("pageBreakBefore")))


def set_heading2_with_question_appearance(root: etree._Element, text: str) -> None:
    matches = [
        paragraph
        for paragraph in root.xpath("//w:body/w:p", namespaces=NS)
        if paragraph_text(paragraph) == text
    ]
    if len(matches) != 1:
        raise RuntimeError(f"Expected one paragraph matching {text!r}; found {len(matches)}")
    paragraph = matches[0]
    properties = paragraph.find(qn("pPr"))
    if properties is None:
        properties = etree.Element(qn("pPr"))
        paragraph.insert(0, properties)
    style = properties.find(qn("pStyle"))
    if style is None:
        style = etree.Element(qn("pStyle"))
        properties.insert(0, style)
    style.set(qn("val"), "Heading2")
    spacing = properties.find(qn("spacing"))
    if spacing is None:
        spacing = etree.SubElement(properties, qn("spacing"))
    spacing.set(qn("before"), "180")
    spacing.set(qn("after"), "100")

    for run in paragraph.xpath("./w:r", namespaces=NS):
        run_properties = run.find(qn("rPr"))
        if run_properties is None:
            run_properties = etree.Element(qn("rPr"))
            run.insert(0, run_properties)
        for child_name in ("b", "bCs"):
            if run_properties.find(qn(child_name)) is None:
                run_properties.append(etree.Element(qn(child_name)))
        for child_name, value in (("color", "404040"), ("sz", "24"), ("szCs", "24")):
            child = run_properties.find(qn(child_name))
            if child is None:
                child = etree.SubElement(run_properties, qn(child_name))
            child.set(qn("val"), value)


def remove_empty_body_headings(root: etree._Element) -> None:
    for paragraph in list(root.xpath("//w:body/w:p", namespaces=NS)):
        if paragraph_text(paragraph):
            continue
        style_values = paragraph.xpath("./w:pPr/w:pStyle/@w:val", namespaces=NS)
        if style_values == ["Heading1"]:
            paragraph.getparent().remove(paragraph)


def table_cells(table: etree._Element) -> list[list[etree._Element]]:
    return [row.xpath("./w:tc", namespaces=NS) for row in table.xpath("./w:tr", namespaces=NS)]


def mark_first_row_as_header(table: etree._Element) -> None:
    rows = table.xpath("./w:tr", namespaces=NS)
    if not rows:
        return
    row = rows[0]
    properties = row.find(qn("trPr"))
    if properties is None:
        properties = etree.Element(qn("trPr"))
        row.insert(0, properties)
    if properties.find(qn("tblHeader")) is None:
        marker = etree.SubElement(properties, qn("tblHeader"))
        marker.set(qn("val"), "true")


def build() -> None:
    if not REFERENCE.exists():
        raise FileNotFoundError(REFERENCE)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(REFERENCE, "r") as source:
        document_xml = source.read("word/document.xml")
        root = etree.fromstring(document_xml)

        replace_body_paragraphs(
            root,
            "At least six (6) Test Scenarios for the BookVerse application:",
            "Fifteen (15) Test Scenarios for the CareNavigator PH application:",
        )
        replace_body_paragraphs(
            root,
            "Related Scenario: TS-02 – Verify that a user can successfully log in using valid credentials.",
            "Related Scenario: TS-02 - Verify that an active user can sign in with valid credentials.",
            expected_count=2,
        )
        replace_body_paragraphs(
            root,
            "Related Scenario: TS-03 – Verify that the book search functionality returns accurate and relevant results.",
            "Related Scenario: TS-03 - Verify that a patient can reserve an available consultation slot.",
            expected_count=2,
        )
        replace_body_paragraphs(
            root,
            "A Test Scenario is a high-level description of what needs to be tested. It focuses on a particular feature or user action in a broad way (e.g., \"Verify that a user can successfully log in using valid credentials\"). It answers the question \"What should be tested?\" In contrast, a Test Case is a detailed, step-by-step set of instructions derived from a Test Scenario. It includes specific preconditions, test steps, test data, and expected results. It answers the questions \"How should it be tested?\" and \"What is the exact expected outcome?\" One Test Scenario can generate multiple Test Cases (both positive and negative).",
            "A Test Scenario is a high-level statement of what must be verified, such as whether a CareNavigator PH patient can reserve a consultation. A Test Case explains exactly how to verify that scenario through defined preconditions, test data, numbered actions, and observable expected results. One scenario may therefore produce several positive, negative, boundary, security, and role-based test cases.",
        )
        replace_body_paragraphs(
            root,
            "Creating Test Cases before execution ensures that testing is systematic, repeatable, and objective. Well-written Test Cases provide clear guidance on what to test, how to test it, and what the expected results are, which reduces ambiguity and human error during testing. They also serve as documentation for future regression testing, help estimate testing effort, enable better coverage of both positive and negative paths, and allow different testers to execute the same tests consistently. Without predefined Test Cases, testing can become ad-hoc, incomplete, and difficult to track or reproduce.",
            "Creating Test Cases before execution makes the work consistent, repeatable, and measurable. For CareNavigator PH, predefined cases help testers cover clinical workflows, role restrictions, scheduling boundaries, and error handling without relying on memory. They also provide regression evidence after code or database changes, allow different testers to reproduce the same result, and make defects easier to trace to a specific requirement and data condition.",
        )
        replace_body_paragraphs(
            root,
            "The most challenging part was designing the Negative Test Cases. While positive (happy path) scenarios are relatively straightforward because they follow the expected successful flow, negative cases require careful consideration of invalid inputs, edge cases, boundary conditions, and potential error messages. It is important to anticipate how the system should respond gracefully to incorrect data without crashing, while still providing useful feedback to the user. Identifying realistic yet meaningful negative data and writing precise expected results for failure paths demanded deeper analysis of the application's validation and error-handling logic.",
            "The most challenging part was defining realistic negative cases for a role-aware healthcare application. A failure may be blocked in the Flutter form, rejected by a repository, denied by Row Level Security, or caused by a time-slot race. The expected result must distinguish these layers while still requiring safe feedback, no duplicate or unauthorized record, and no exposure of clinical data. The 24-hour reservation rule and the no-slot state required especially precise preconditions.",
        )
        remove_empty_body_headings(root)
        set_page_break_before(root, "Additional Negative Test Case (TS-03)")
        set_page_break_before(root, "Part 4: Reflection")
        for reflection_question in (
            "1. What is the difference between a Test Scenario and a Test Case?",
            "2. Why is it important to create Test Cases before performing software testing?",
            "3. Which part of the activity was the most challenging and why?",
        ):
            set_heading2_with_question_appearance(root, reflection_question)

        tables = root.xpath("//w:body/w:tbl", namespaces=NS)
        if len(tables) != 6:
            raise RuntimeError(f"Expected 6 tables; found {len(tables)}")
        for table in tables:
            mark_first_row_as_header(table)

        application = table_cells(tables[0])
        set_cell_text(application[1][1], "CareNavigator PH")
        set_cell_text(
            application[2][1],
            "Cross-platform Flutter healthcare navigation and care management application (Web and Mobile)",
        )
        set_cell_text(
            application[3][1],
            "1. Registration, authentication, and role-based workspaces\n"
            "2. Hospital and doctor discovery, maps, and emergency availability\n"
            "3. Consultation requests, reservations, appointments, and secure messaging\n"
            "4. Clinical records, prescriptions, diagnostic results, and hospital administration",
        )

        scenarios = table_cells(tables[1])
        scenario_texts = [
            "Verify that a patient can register with valid identity information and complete email verification.",
            "Verify that an active user can sign in with valid credentials.",
            "Verify that a patient can reserve an available consultation slot.",
            "Verify that a public user can search verified, operating hospitals and doctors and view accurate directory and map details.",
            "Verify that an authorized doctor can complete a consultation and save clinical checkup and prescription information for the correct patient.",
            "Verify that route guards and Row Level Security prevent a user from accessing another user's or hospital's protected clinical data.",
            "Verify that a guest can submit a consultation request, complete email OTP verification, and enter the authorized review workflow.",
            "Verify that the care assistant returns preliminary symptom guidance and escalates deterministic emergency warning signs safely.",
            "Verify that an authorized medical-result upload remains preliminary until a doctor confirms, modifies, or rejects the extracted findings.",
            "Verify that authorized patients and clinicians can exchange care messages and secure attachments within the correct consultation relationship.",
            "Verify that care events create in-app notifications and eligible reminders without sending duplicate messages.",
            "Verify that a patient can reschedule or cancel an appointment while preserving slot availability and appointment history correctly.",
            "Verify that a hospital administrator can manage staff, services, availability, and appointments only for the assigned hospital.",
            "Verify that a super administrator can review hospitals and govern accounts without receiving unrestricted clinical-record access.",
            "Verify that emergency-bed capacity displays live, delayed, or expired status according to the configured freshness thresholds.",
        ]
        scenario_table = tables[1]
        scenario_rows = scenario_table.xpath("./w:tr", namespaces=NS)
        while len(scenario_rows) < len(scenario_texts) + 1:
            new_row = copy.deepcopy(scenario_rows[-1])
            scenario_table.append(new_row)
            scenario_rows.append(new_row)
        scenarios = table_cells(scenario_table)
        for row_index, scenario in enumerate(scenario_texts, start=1):
            set_cell_text(scenarios[row_index][0], f"TS-{row_index:02d}")
            set_cell_text(scenarios[row_index][1], scenario)

        login_positive = table_cells(tables[2])
        login_positive_values = {
            1: "TC_AUTH_001",
            2: "Successful Sign-In and Role-Based Redirect",
            3: "TS-02",
            4: (
                "1. The test Supabase project is available.\n"
                "2. An active patient account exists.\n"
                "3. The tester is signed out."
            ),
            5: (
                "1. Open CareNavigator PH and select Sign in.\n"
                "2. Enter the active patient's email and correct password.\n"
                "3. Select Sign in.\n"
                "4. Verify the destination workspace."
            ),
            6: "Email: qa.patient@carenavigator.test\nPassword: PatientPass1",
            7: (
                "1. Authentication succeeds and a session is created.\n"
                "2. The user is redirected to the Patient workspace.\n"
                "3. Patient navigation and the user's scoped data appear.\n"
                "4. Doctor and administrator access is not granted."
            ),
        }
        for row_index, value in login_positive_values.items():
            set_cell_text(login_positive[row_index][1], value)

        login_negative = table_cells(tables[3])
        login_negative_values = {
            1: "TC_AUTH_002",
            2: "Sign-In Rejected for an Incorrect Password",
            3: "TS-02",
            4: (
                "1. The test Supabase project is available.\n"
                "2. The active patient email exists.\n"
                "3. The tester is signed out."
            ),
            5: (
                "1. Open CareNavigator PH and select Sign in.\n"
                "2. Enter the patient email and an incorrect password.\n"
                "3. Select Sign in.\n"
                "4. Attempt to open /patient/appointments."
            ),
            6: "Email: qa.patient@carenavigator.test\nPassword: WrongPassword999 (invalid data)",
            7: (
                "1. Authentication fails and a safe error message appears.\n"
                "2. The user remains on the sign-in screen.\n"
                "3. No authenticated session is created.\n"
                "4. The protected route returns to sign-in and exposes no patient data."
            ),
        }
        for row_index, value in login_negative_values.items():
            set_cell_text(login_negative[row_index][1], value)

        booking_positive = table_cells(tables[4])
        booking_positive_values = {
            1: "TC_BOOKING_001",
            2: "Reserve an In-Person Consultation from a Published Slot",
            3: "TS-03",
            4: (
                "1. An active patient is signed in with a complete profile.\n"
                "2. A verified, operating hospital has an eligible doctor.\n"
                "3. An unoccupied in-person slot is at least 24 hours away."
            ),
            5: (
                "1. Open Patient > Appointments.\n"
                "2. Select Reserve consultation.\n"
                "3. Choose the hospital, clinician, and In person care mode.\n"
                "4. Enter the primary care concern.\n"
                "5. Choose a published date and time, then select Reserve consultation."
            ),
            6: (
                "Hospital: verified/open fixture\n"
                "Clinician: eligible doctor\n"
                "Concern: Recurring headache for two days\n"
                "Slot: 48 hours ahead"
            ),
            7: (
                "1. One reservation is created for the signed-in patient.\n"
                "2. It appears with the selected hospital, doctor, mode, and time.\n"
                "3. Its status and time match the server record.\n"
                "4. The occupied slot is no longer offered."
            ),
        }
        for row_index, value in booking_positive_values.items():
            set_cell_text(booking_positive[row_index][1], value)

        booking_negative = table_cells(tables[5])
        booking_negative_values = {
            1: "TC_BOOKING_002",
            2: "Reservation Blocked When No Qualifying Slot Is Available",
            3: "TS-03",
            4: (
                "1. An active patient is signed in.\n"
                "2. The doctor has no qualifying unoccupied slot in the next 30 days.\n"
                "3. No reservation exists for this attempt."
            ),
            5: (
                "1. Open Patient > Appointments and select Reserve consultation.\n"
                "2. Select the clinician fixture with no qualifying slots.\n"
                "3. Select In person care mode.\n"
                "4. Review the availability area and the submission control."
            ),
            6: (
                "Clinician: no qualifying future slots\n"
                "Search window: next 30 days\n"
                "Minimum lead time: 24 hours (boundary/edge data)"
            ),
            7: (
                "1. No date or time can be selected.\n"
                "2. The no-slot message states the 24-hour notice rule.\n"
                "3. Reserve consultation is disabled.\n"
                "4. No consultation or duplicate record is created."
            ),
        }
        for row_index, value in booking_negative_values.items():
            set_cell_text(booking_negative[row_index][1], value)

        output_xml = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone="yes")
        temp_handle, temp_name = tempfile.mkstemp(suffix=".docx", dir=str(OUTPUT.parent))
        os.close(temp_handle)
        temp_path = Path(temp_name)
        try:
            with zipfile.ZipFile(temp_path, "w") as target:
                for item in source.infolist():
                    payload = output_xml if item.filename == "word/document.xml" else source.read(item.filename)
                    target.writestr(item, payload)
            shutil.move(str(temp_path), OUTPUT)
        finally:
            if temp_path.exists():
                temp_path.unlink()

    print(OUTPUT)


if __name__ == "__main__":
    build()
