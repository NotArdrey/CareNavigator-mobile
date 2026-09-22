# Template execution contract

## Reference

- Retained source: `C:\Users\Neila\Downloads\Activity1_Test_Scenarios_and_Test_Cases.docx`
- SHA-256: `61C76B80185CF10F1D5C137311234F2FC8BA0B7A8916EE7C784253F92DA23864`
- Evidence: `template-reference-render/` (four rendered pages) and `template-style-evidence.json`
- One portrait section; no drawings, content controls, footnotes, or endnotes.
- Preserve-only package features: theme, styles, numbering, header, footer, relationships, and PAGE/NUMPAGES fields.

## Page system

- US Letter portrait, 8.5 x 11 in.
- Margins: 0.75 in on all sides; one section; normal first/odd/even-page behavior.
- Header: single-line course/activity label with dark blue rule.
- Footer: light gray rule and centered `Page {PAGE} of {NUMPAGES}` fields.

## Typography and color

- Retain the source theme font and existing Word styles.
- Title block: centered 18 pt bold dark blue title, 14 pt bold blue subtitle, and 10 pt gray italic course line.
- Heading 1: dark navy section heading; Heading 2: blue case heading; Heading 3: dark gray reflection question.
- Body and table copy: source Normal style, generally 10-10.5 pt.
- Positive table headers remain medium blue (`2E75B6` family); negative table headers remain red; application/scenario headers remain dark navy (`1F4E79` family).

## Lists and tables

- Preserve six existing two-column tables and their row/column counts.
- Application information: 2.0/5.0 in columns.
- Scenario matrix: 1.0/6.0 in columns.
- Test-case tables: 1.75/5.25 in columns.
- Preserve source borders, cell margins, row expansion, vertical alignment, and repeated visual header treatment.
- Mark each existing first row as a semantic/repeating header row without changing its visual treatment.
- Multi-step values use line breaks inside the existing detail cells, matching the source pattern.

## Content flow and slot map

1. Preserve title, course label, learning outcomes, and activity framing.
2. Replace only the sample BookVerse application-information values.
3. Replace the six sample scenarios and extend the same table pattern to fifteen project-specific scenarios.
4. Preserve TS-02 and TS-03 as the two selected scenarios; replace all four sample cases in place with CareNavigator PH login and consultation-reservation coverage.
5. Rewrite the three reflection answers for CareNavigator PH while preserving the questions and end marker.
6. Leave header/footer text and fields unchanged.

## Fidelity gates

- Reference file remains byte-for-byte unchanged.
- Final uses the same page geometry, recurring header/footer, heading styles, table structure, and color system.
- No BookVerse, bookstore, book-search, cart, order, or checkout sample text remains.
- All tables wrap without clipping; headings stay with their following content when practical.
- Final page count may increase to accommodate the expanded fifteen-scenario matrix; no unexplained blank pages or broken table rows.
- The reflection section may receive an explicit page break to prevent its heading/question from being orphaned at the bottom of the preceding test-case page.
- Remove the source's four empty Heading 1 spacer paragraphs once the expanded scenario table supplies natural pagination.
- Force the additional negative TS-03 block to start on a new page so its heading stays with its table.
- Use a semantically continuous Heading 2 level for reflection questions while preserving the template's question styling.
