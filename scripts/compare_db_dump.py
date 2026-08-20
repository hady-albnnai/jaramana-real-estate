#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
compare_db_dump.py — فحص علامات الانحراف المعروفة داخل dump سيرفر حي.

الاستخدام:
    python3 scripts/compare_db_dump.py db_dump.sql [--detailed]

يطبع لكل علامة: ✅ موجودة / ❌ غائبة / ⚠️ غامضة، مع مقتطف دالّ من الملف.
المرجع: docs/DRIFT_CLOSURE_PLAYBOOK.md
"""
import re
import sys

MARKERS = {
    "get_lawyer_appointments (توقيع sts/cnl_rsn)": {
        "pattern": r"get_lawyer_appointments",
        "hint": r"cnl_rsn",
    },
    "rebook_legal_appointment_v2": {
        "pattern": r"rebook_legal_appointment_v2",
        "hint": r"APPOINTMENT_NOT_REBOOKABLE",
    },
    "v3: LAWYER_INACTIVE_FOR_RENEWAL (ثغرة 2)": {
        "pattern": r"approve_payment_final_v3",
        "hint": r"LAWYER_INACTIVE_FOR_RENEWAL",
    },
    "prepare: OPEN_CONSULTATION_EXISTS (ثغرة 3)": {
        "pattern": r"prepare_consultation_intent_v2",
        "hint": r"OPEN_CONSULTATION_EXISTS",
    },
    "v3: CHAT_EXPIRED_7DAYS recheck (ثغرة 4)": {
        "pattern": r"approve_payment_final_v3",
        "hint": r"CHAT_EXPIRED_7DAYS",
    },
    "عمود waveform على consultation_chats": {
        "pattern": r"consultation_chats",
        "hint": r"waveform",
    },
    "عمود doc_img_admin على offers": {
        "pattern": r"CREATE TABLE.*offers|doc_img_admin",
        "hint": r"doc_img_admin",
    },
    "جدول offer_documents (سند الملكية الحي)": {
        "pattern": r"offer_documents",
        "hint": r"offer_documents",
    },
    "بوالصي INSERT على payment_proofs = مقفولة": {
        "pattern": r"payment_proofs_user_insert|Users can upload their own payment proofs",
        "hint": None,
    },
    "enqueue يصرّف الطابور فوراً (push فوري)": {
        "pattern": r"enqueue_consultation_notification_push",
        "hint": r"process_consultation_outbox_v2",
    },
    "trg_consultation_payment_v2 نص غني (اتصال المكتب)": {
        "pattern": r"trg_consultation_payment_v2",
        "hint": r"الاتصال بالمكتب",
    },
}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    detailed = "--detailed" in sys.argv
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(f"❌ تعذّرت قراءة الملف: {e}")
        return 1

    print(f"فحص: {path} ({len(src)} محرف)\n")
    missing = []
    for label, spec in MARKERS.items():
        base = bool(re.search(spec["pattern"], src))
        hint_ok = spec["hint"] is None or bool(re.search(spec["hint"], src))
        if spec["hint"] is None:
            # نتحقق من الغياب (بوالصي مقفولة = لا يجب أن تظهر)
            status = "✅ مقفول (غائب — كما ينبغي)" if not base else "⚠️ لسا موجود — الباب لم يُقفل"
            if base:
                missing.append(label)
        elif base and hint_ok:
            status = "✅ موجود"
        elif base and not hint_ok:
            status = "⚠️ موجود لكن نسخة قديمة (بلا التوقيع الجديد)"
            missing.append(label)
        else:
            status = "❌ غائب كلياً"
            missing.append(label)
        print(f"  {status:55s} | {label}")
        if detailed and base:
            m = re.search(spec["pattern"], src)
            s = max(0, (m.start() if m else 0) - 60)
            snippet = src[s:s + 180].replace("\n", " ")
            print(f"       مقتطف: …{snippet}…")

    print()
    if missing:
        print(f"⚠️ فروقات للإقفال: {len(missing)}")
        for m in missing:
            print(f"   - {m}")
    else:
        print("✅ لا فروقات معروفة — السيرفر مطابق للريبو على العلامات المفحوصة.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
