from pathlib import Path

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import landscape
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase.pdfmetrics import stringWidth
from PIL import Image


ROOT = Path(r"C:\Users\Neila\AdvanceMobile\CareNavigatorPH")
OUT = ROOT / "output" / "pdf" / "CareNavigator_PH_System_Defense.pdf"
W, H = 960, 540

NAVY = HexColor("#102B3A")
TEAL = HexColor("#0B8F8C")
TEAL_DARK = HexColor("#00636B")
CYAN = HexColor("#DDF4F5")
INK = HexColor("#162F3D")
MUTED = HexColor("#536B78")
PALE = HexColor("#F2F6F8")
LINE = HexColor("#D5E0E5")
GREEN = HexColor("#218B64")
AMBER = HexColor("#D48C12")
RED = HexColor("#C72C3B")


def wrap(text, font, size, max_width):
    words = text.split()
    lines, current = [], ""
    for word in words:
        trial = word if not current else current + " " + word
        if stringWidth(trial, font, size) <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_wrapped(c, text, x, y, width, font="Helvetica", size=16, color=INK,
                 leading=None, max_lines=None):
    leading = leading or size * 1.28
    lines = wrap(text, font, size, width)
    if max_lines:
        lines = lines[:max_lines]
    c.setFont(font, size)
    c.setFillColor(color)
    for line in lines:
        c.drawString(x, y, line)
        y -= leading
    return y


def title(c, text, kicker=None):
    if kicker:
        c.setFont("Helvetica-Bold", 10)
        c.setFillColor(TEAL_DARK)
        c.drawString(42, H - 36, kicker.upper())
    c.setFont("Helvetica-Bold", 28)
    c.setFillColor(INK)
    c.drawString(42, H - 72, text)
    c.setStrokeColor(LINE)
    c.setLineWidth(1)
    c.line(42, H - 88, W - 42, H - 88)


def footer(c, page, source, light=False):
    c.setFont("Helvetica", 7.5)
    c.setFillColor(HexColor("#8AA1AC") if light else MUTED)
    c.drawString(42, 18, "Source: " + source)
    c.drawRightString(W - 42, 18, f"CareNavigator PH  |  {page:02d}")


def bullet_list(c, items, x, y, width, size=15, leading=24, color=INK, bullet_color=TEAL):
    for item in items:
        c.setFillColor(bullet_color)
        c.circle(x + 4, y + 5, 3, stroke=0, fill=1)
        y = draw_wrapped(c, item, x + 18, y, width - 18, size=size, color=color,
                         leading=leading) - 8
    return y


def label(c, text, x, y, w, fill=CYAN, color=TEAL_DARK):
    c.setFillColor(fill)
    c.roundRect(x, y, w, 26, 7, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 10)
    c.setFillColor(color)
    c.drawCentredString(x + w / 2, y + 8, text.upper())


def panel(c, x, y, w, h, fill=PALE, stroke=LINE, radius=12):
    c.setFillColor(fill)
    c.setStrokeColor(stroke)
    c.setLineWidth(1)
    c.roundRect(x, y, w, h, radius, stroke=1, fill=1)


def fit_image(c, path, x, y, w, h, contain=True):
    im = Image.open(path)
    iw, ih = im.size
    scale = min(w / iw, h / ih) if contain else max(w / iw, h / ih)
    dw, dh = iw * scale, ih * scale
    dx, dy = x + (w - dw) / 2, y + (h - dh) / 2
    c.drawImage(ImageReader(im), dx, dy, dw, dh, mask="auto")
    return dx, dy, dw, dh


def phone(c, path, x, y, h, caption=None):
    ratio = 390 / 844
    screen_h = h - 18
    screen_w = screen_h * ratio
    frame_w = screen_w + 16
    c.setFillColor(NAVY)
    c.roundRect(x, y, frame_w, h, 18, stroke=0, fill=1)
    c.setFillColor(white)
    c.roundRect(x + 8, y + 9, screen_w, screen_h, 12, stroke=0, fill=1)
    fit_image(c, path, x + 8, y + 9, screen_w, screen_h)
    if caption:
        c.setFont("Helvetica-Bold", 8.5)
        c.setFillColor(MUTED)
        c.drawCentredString(x + frame_w / 2, y - 13, caption)
    return frame_w


def new_page(c):
    c.setFillColor(white)
    c.rect(0, 0, W, H, stroke=0, fill=1)


def build():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUT), pagesize=(W, H))
    c.setTitle("CareNavigator PH System Demonstration and Defense")
    c.setAuthor("CareNavigator PH")

    # 1 - Cover
    new_page(c)
    c.setFillColor(NAVY)
    c.rect(0, 0, W, H, stroke=0, fill=1)
    c.setFillColor(TEAL)
    c.roundRect(56, H - 92, 56, 56, 14, stroke=0, fill=1)
    c.setFillColor(white)
    c.rect(79, H - 82, 10, 36, stroke=0, fill=1)
    c.rect(66, H - 69, 36, 10, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 12)
    c.drawString(128, H - 65, "CARENAVIGATOR PH")
    c.setFont("Helvetica-Bold", 38)
    c.drawString(56, H - 165, "System Demonstration")
    c.drawString(56, H - 207, "and Defense")
    draw_wrapped(c, "A role-aware platform for finding care, coordinating consultations, and managing clinical operations.",
                 56, H - 250, 480, size=17, color=HexColor("#D7E6EC"), leading=23)
    label(c, "Flutter + Supabase", 56, 82, 150, fill=HexColor("#164455"), color=HexColor("#8DE1DE"))
    label(c, "Mobile + Web", 218, 82, 132, fill=HexColor("#164455"), color=HexColor("#8DE1DE"))
    mobile = ROOT / "submission_assets" / "live_app_home_mobile.png"
    phone(c, mobile, 692, 54, 438, "390 x 844 mobile viewport")
    footer(c, 1, "README.md; submission_assets/live_app_home_mobile.png", light=True)
    c.showPage()

    # 2 - Problem / solution
    new_page(c)
    title(c, "One platform replaces a fragmented care journey", "Problem and response")
    c.setFont("Helvetica-Bold", 20)
    c.setFillColor(RED)
    c.drawString(56, 414, "Without coordination")
    bullet_list(c, [
        "Patients search across disconnected channels for facilities, clinicians, and availability.",
        "Consultation requests, medical files, messages, and follow-ups are handled in separate workflows.",
        "Hospitals and administrators need controlled, auditable access to operational and clinical data.",
    ], 56, 380, 390, size=15)
    c.setFillColor(TEAL)
    c.roundRect(476, 108, 428, 324, 16, stroke=0, fill=1)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 20)
    c.drawString(506, 394, "With CareNavigator PH")
    bullet_list(c, [
        "Verified hospital and clinician discovery",
        "Deterministic emergency screening",
        "Guest and registered-patient consultation flows",
        "Role-specific clinical and operational workspaces",
        "Realtime communication with protected records",
    ], 506, 354, 350, size=15, color=white, bullet_color=white)
    footer(c, 2, "README.md; SYSTEM_ARCHITECTURE.md sections 1 and 5")
    c.showPage()

    # 3 - Roles
    new_page(c)
    title(c, "Five roles share one governed care platform", "Users and scope")
    roles = [
        ("Guest", "Discover care, run preliminary screening, and submit a verified consultation request."),
        ("Patient", "Book, reschedule, consult, message, and access records, prescriptions, labs, and files."),
        ("Doctor", "Manage schedules, assigned patients, consultations, prescriptions, and clinical review."),
        ("Hospital admin", "Manage staff, services, departments, capacity, rooms, ER status, and reports."),
        ("Super admin", "Approve hospitals, govern accounts and permissions, review analytics, and audit activity."),
    ]
    y = 258
    for i, (name, desc) in enumerate(roles):
        x = 52 + (i % 3) * 300
        if i == 3:
            x = 202
            y = 90
        elif i == 4:
            x = 502
        panel(c, x, y, 256, 142, fill=white)
        c.setFillColor(TEAL if i < 3 else NAVY)
        c.rect(x, y + 132, 256, 10, stroke=0, fill=1)
        c.setFont("Helvetica-Bold", 17)
        c.setFillColor(INK)
        c.drawString(x + 18, y + 103, name)
        draw_wrapped(c, desc, x + 18, y + 78, 218, size=12.5, color=MUTED, leading=17)
    footer(c, 3, "PRE_BUILD_REPORT.md - Role coverage")
    c.showPage()

    # 4 - Journey timeline
    new_page(c)
    title(c, "The demonstration follows a complete patient journey", "End-to-end workflow")
    steps = [
        ("01", "Discover", "Search verified hospitals, clinicians, services, and current availability."),
        ("02", "Assess", "Apply emergency rules first, then generate preliminary guidance."),
        ("03", "Book", "Submit guest intake or reserve an available slot as a registered patient."),
        ("04", "Consult", "Use secure messaging and approved consultation channels for online care."),
        ("05", "Continue care", "Receive prescriptions, lab requests, results, notifications, and follow-ups."),
    ]
    c.setStrokeColor(LINE)
    c.setLineWidth(4)
    c.line(100, 288, 862, 288)
    xs = [104, 292, 480, 668, 856]
    for x, (num, head, desc) in zip(xs, steps):
        c.setFillColor(TEAL)
        c.circle(x, 288, 14, stroke=0, fill=1)
        c.setFillColor(white)
        c.setFont("Helvetica-Bold", 9)
        c.drawCentredString(x, 285, num)
        c.setFont("Helvetica-Bold", 16)
        c.setFillColor(INK)
        c.drawCentredString(x, 330, head)
        lines = wrap(desc, "Helvetica", 10.5, 134)
        c.setFont("Helvetica", 10.5)
        c.setFillColor(MUTED)
        yy = 250
        for line in lines:
            c.drawCentredString(x, yy, line)
            yy -= 14
    label(c, "Public", 66, 406, 108)
    label(c, "Clinical", 426, 406, 108, fill=HexColor("#E4F2EA"), color=GREEN)
    label(c, "Continuity", 786, 406, 108, fill=HexColor("#E9EEF8"), color=NAVY)
    footer(c, 4, "SYSTEM_ARCHITECTURE.md section 6; README.md")
    c.showPage()

    # 5 - Demonstration screens
    new_page(c)
    title(c, "The interface adapts from public discovery to role workspaces", "System demonstration")
    desktop = ROOT / "submission_assets" / "live_app_home.png"
    panel(c, 44, 102, 552, 334, fill=white)
    fit_image(c, desktop, 56, 116, 528, 306)
    c.setFont("Helvetica-Bold", 12)
    c.setFillColor(MUTED)
    c.drawString(56, 88, "Desktop public home - 1280 x 720")
    phone(c, mobile, 694, 80, 362, "Mobile public home - 390 x 844")
    footer(c, 5, "submission_assets/live_app_home.png; live_app_home_mobile.png")
    c.showPage()

    # 6 - Mobile CRUD screenshots
    new_page(c)
    title(c, "Mobile CRUD controls are visible at a real 390 x 844 viewport", "Responsive implementation")
    shots = [
        ("create_operation.png", "Create"),
        ("read_operation.png", "Read"),
        ("update_operation.png", "Update"),
        ("delete_operation.png", "Delete"),
    ]
    x = 95
    for filename, cap in shots:
        phone(c, ROOT / "submission_assets" / filename, x, 75, 344, cap)
        x += 202
    c.setFont("Helvetica", 12)
    c.setFillColor(MUTED)
    c.drawCentredString(W / 2, 44, "Schedule-slot workflow: publish, review, change visibility, and safely delete recurring availability.")
    footer(c, 6, "submission_assets/mobile CRUD screenshots - 390 x 844")
    c.showPage()

    # 7 - Architecture
    new_page(c)
    title(c, "Layered architecture separates client, data, and privileged work", "Technical design")
    layers = [
        ("Flutter client", "Adaptive mobile and web UI, GoRouter navigation, shared clinical design system", HexColor("#DDF4F5")),
        ("State and access", "Riverpod providers and typed Dart repositories as the only Supabase boundary", HexColor("#EAF3FA")),
        ("Supabase platform", "Auth, PostgreSQL, RLS, Realtime, private Storage, RPCs, triggers, Cron", HexColor("#E8F1EC")),
        ("Server integrations", "Edge Functions connect Groq, Gmail SMTP, OpenStreetMap, and OSRM", HexColor("#F6EFE3")),
    ]
    ys = [388, 286, 184, 82]
    for (head, body, fill), y in zip(layers, ys):
        panel(c, 138, y, 684, 76, fill=fill, radius=8)
        c.setFont("Helvetica-Bold", 17)
        c.setFillColor(INK)
        c.drawString(162, y + 43, head)
        c.setFont("Helvetica", 12.5)
        c.setFillColor(MUTED)
        c.drawString(332, y + 43, body)
    for y in [372, 270, 168]:
        c.setStrokeColor(TEAL)
        c.setLineWidth(2)
        c.line(480, y, 480, y - 18)
        c.line(474, y - 12, 480, y - 18)
        c.line(486, y - 12, 480, y - 18)
    footer(c, 7, "SYSTEM_ARCHITECTURE.md sections 2-5")
    c.showPage()

    # 8 - Security and clinical safety
    new_page(c)
    title(c, "Clinical safety and authorization are enforced before convenience", "Risk controls")
    panel(c, 52, 102, 408, 332, fill=HexColor("#FFF7F2"), stroke=HexColor("#F1D6C8"))
    panel(c, 500, 102, 408, 332, fill=HexColor("#F0F8F6"), stroke=HexColor("#C9E3DA"))
    c.setFont("Helvetica-Bold", 20)
    c.setFillColor(RED)
    c.drawString(80, 392, "Clinical safeguards")
    bullet_list(c, [
        "Emergency warning signs trigger deterministic escalation.",
        "AI output is preliminary and requires licensed-doctor review.",
        "Medical-result processing tracks review and decision states.",
        "No unavailable or invented records are substituted in the UI.",
    ], 80, 354, 340, size=14)
    c.setFont("Helvetica-Bold", 20)
    c.setFillColor(GREEN)
    c.drawString(528, 392, "Data safeguards")
    bullet_list(c, [
        "RLS prevents cross-patient, cross-doctor, and cross-hospital access.",
        "Private files use short-lived signed URLs after authorization.",
        "Privileged workflows validate roles before server-side credentials are used.",
        "Sensitive administrative and workflow actions are audited.",
    ], 528, 354, 340, size=14, bullet_color=GREEN)
    footer(c, 8, "SYSTEM_ARCHITECTURE.md sections 7-8; VERIFICATION_REPORT.md")
    c.showPage()

    # 9 - Backend metrics
    new_page(c)
    title(c, "The backend contract is broad, live, and access-controlled", "Implementation evidence")
    metrics = [
        ("49", "RLS-enabled public tables", TEAL),
        ("19", "Realtime-published tables", NAVY),
        ("5", "Active Edge Functions", GREEN),
    ]
    x = 52
    for num, desc, color in metrics:
        panel(c, x, 166, 260, 242, fill=PALE)
        c.setFont("Helvetica-Bold", 62)
        c.setFillColor(color)
        c.drawString(x + 24, 300, num)
        draw_wrapped(c, desc, x + 24, 260, 208, font="Helvetica-Bold", size=17, color=INK, leading=22)
        x += 298
    c.setFont("Helvetica", 13)
    c.setFillColor(MUTED)
    c.drawCentredString(W / 2, 120, "Private clinical Storage, audited RPCs, scheduled notification dispatch, and server-side secrets complete the platform boundary.")
    footer(c, 9, "README.md - Supabase; PRE_BUILD_REPORT.md - Live Supabase contract inventory")
    c.showPage()

    # 10 - Verification
    new_page(c)
    title(c, "Core quality gates passed for code, tests, and builds", "Verification results")
    rows = [
        ("Flutter static analysis", "PASSED", GREEN),
        ("Automated Flutter tests", "26 PASSED", GREEN),
        ("Flutter web release build", "PASSED", GREEN),
        ("Android debug build", "PASSED", GREEN),
        ("Live migration verification", "PASSED", GREEN),
        ("Ordinary live-contract test", "1 INTENTIONAL SKIP", AMBER),
    ]
    y = 374
    for name, result, color in rows:
        c.setStrokeColor(LINE)
        c.line(76, y - 10, 884, y - 10)
        c.setFont("Helvetica", 15)
        c.setFillColor(INK)
        c.drawString(82, y + 8, name)
        c.setFont("Helvetica-Bold", 13)
        c.setFillColor(color)
        c.drawRightString(876, y + 8, result)
        y -= 50
    c.setFont("Helvetica", 11.5)
    c.setFillColor(MUTED)
    c.drawString(82, 72, "Scope note: live seeded-account workflows require configured non-production accounts and relationship data.")
    footer(c, 10, "VERIFICATION_REPORT.md - Verification summary and runtime-tested behavior")
    c.showPage()

    # 11 - Limitations
    new_page(c)
    title(c, "Remaining work centers on production validation", "Limitations and next steps")
    items = [
        ("Connected user testing", "Exercise patient, doctor, hospital-admin, and super-admin sessions with dedicated test accounts."),
        ("External providers", "Validate SMTP delivery, Groq responses, online consultation channels, and scheduled dispatch."),
        ("Device coverage", "Complete physical Android testing and an iOS build and device pass on macOS."),
        ("Security hardening", "Enable leaked-password protection and complete an independent privacy and healthcare compliance review."),
        ("Operations", "Add centralized observability, backup and recovery procedures, key rotation, and load testing."),
    ]
    y = 414
    for i, (head, body) in enumerate(items, 1):
        c.setFillColor(TEAL if i < 4 else NAVY)
        c.circle(76, y + 4, 16, stroke=0, fill=1)
        c.setFont("Helvetica-Bold", 11)
        c.setFillColor(white)
        c.drawCentredString(76, y, str(i))
        c.setFont("Helvetica-Bold", 15)
        c.setFillColor(INK)
        c.drawString(110, y + 6, head)
        draw_wrapped(c, body, 110, y - 16, 740, size=12.5, color=MUTED, leading=17)
        y -= 75
    footer(c, 11, "VERIFICATION_REPORT.md - Remaining production verification; SYSTEM_ARCHITECTURE.md section 11")
    c.showPage()

    # 12 - Conclusion
    new_page(c)
    c.setFillColor(NAVY)
    c.rect(0, 0, W, H, stroke=0, fill=1)
    c.setFillColor(TEAL)
    c.rect(56, 436, 106, 8, stroke=0, fill=1)
    c.setFont("Helvetica-Bold", 34)
    c.setFillColor(white)
    c.drawString(56, 374, "Defense conclusion")
    draw_wrapped(c,
        "CareNavigator PH demonstrates that one responsive, role-aware system can connect care discovery, consultation workflows, protected clinical records, and hospital operations without weakening authorization boundaries.",
        56, 326, 700, size=18, color=HexColor("#D7E6EC"), leading=27)
    c.setFont("Helvetica-Bold", 17)
    c.setFillColor(HexColor("#8DE1DE"))
    c.drawString(56, 196, "What the defense establishes")
    bullet_list(c, [
        "The system solves a coherent care-navigation problem.",
        "Its architecture separates UI, state, data access, and privileged services.",
        "Its safety, security, and verification evidence are documented and testable.",
    ], 56, 160, 690, size=14, color=white, bullet_color=TEAL)
    c.setFont("Helvetica-Bold", 18)
    c.setFillColor(white)
    c.drawRightString(W - 56, 68, "Ready for demonstration and questions")
    footer(c, 12, "README.md; SYSTEM_ARCHITECTURE.md; VERIFICATION_REPORT.md", light=True)
    c.save()


if __name__ == "__main__":
    build()
