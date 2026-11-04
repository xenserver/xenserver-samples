"""List templates.

Enumerate the pool's VM templates, both built-in and custom.

Run it::

    list_templates("https://xenserver", "root", password)
"""

from connection import connect


def list_templates(url, username, password):
    """List the pool's templates, flagging the built-in (default) ones."""
    session = connect(url, username, password)
    templates = sorted((v for v in session.xenapi.VM.get_all_records().values() if v["is_a_template"]),
                       key=lambda v: v["name_label"])
    print("Templates (%d):" % len(templates))
    for t in templates[:8]:
        is_default = "default_template" in t["other_config"]
        print("  - %s%s" % (t["name_label"], " [built-in]" if is_default else ""))
    print("OK: list-templates")
    session.xenapi.session.logout()
