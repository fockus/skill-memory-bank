"""Review rubric × project quality settings (AGR-076).

The stock rubric bullets tagged `SOLID:`/`DRY:`/`KISS:`/`YAGNI:` and the
`(Testing Trophy)` one leave the review payload when the project switches that
principle / Trophy off (`mb-profile.sh quality --json`). Only bullets identical
to the bundled default are dropped: a bullet the project wrote itself is an
override and always stays.
"""

PRINCIPLES = ("SOLID", "DRY", "KISS", "YAGNI")


def _is_off(bullet, quality):
    text = bullet.split(": ", 1)[-1]
    for principle in PRINCIPLES:
        if text.startswith(principle + ":"):
            return (quality.get("principles") or {}).get(principle.lower()) == "off"
    return "(Testing Trophy)" in text and quality.get("testing_trophy") == "off"


def filter_rubric(bullets, stock, quality):
    """`bullets` minus the stock ones whose switch is off; `quality` = the resolved `quality` object."""
    return [b for b in bullets if not (b in stock and _is_off(b, quality))]


if __name__ == "__main__":
    quality = {"principles": {"kiss": "off"}, "testing_trophy": "off"}
    stock = {"code_rules: KISS: x", "tests: y (Testing Trophy)", "code_rules: DRY: z"}
    kept = filter_rubric(["code_rules: KISS: x", "code_rules: KISS: own", "tests: y (Testing Trophy)",
                          "code_rules: DRY: z"], stock, quality)
    assert kept == ["code_rules: KISS: own", "code_rules: DRY: z"], kept
