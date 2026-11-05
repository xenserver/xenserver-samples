#!/usr/bin/env python3
"""Generate docs/workflows/: the workflow index, the Connecting page, and a page per workflow.

Each page shows the workflow's description from workflows.json, its code in every language, cut from
the sources so it cannot drift from what the samples do, and the example output recorded in
sample-output.tsv (next to this script). Only docs/workflows/ is generated; the rest of docs/ is written
by hand.

    tools/docs/generate_docs.py                       regenerate the pages
    tools/docs/generate_docs.py --check               change nothing; exit 1 if the sources and
                                                      workflows.json disagree, or a page is out of date
    tools/docs/generate_docs.py --captured FILE       first record new example output: FILE has lines of
                                                      "<language>\\t<workflow>\\t<output>" (escaped as in
                                                      sample-output.tsv); add --refresh to take every one

A workflow's recorded output carries a hash of the code that produced it, and new output replaces it
only when that code has changed: output from a run is not exactly reproducible (object uuids, timings),
so taking every new capture would rewrite pages for nothing. Standard library only.
"""
import argparse
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "docs", "workflows")
SAMPLE_STORE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample-output.tsv")

BANNER = ("<!-- Generated from workflows.json, the example sources and a run of each example. "
          "Edit those, not this file. -->")

# (id, title, source directory, code-fence language)
LANGUAGES = [
    ("csharp", "C# (.NET)", "csharp", "csharp"),
    ("python", "Python", "python", "python"),
    ("java", "Java", "java", "java"),
    ("go", "Go", "go", "go"),
    ("powershell", "PowerShell", "powershell", "powershell"),
    ("cli", "xe CLI", "cli", "bash"),
]

SOURCE_EXTENSIONS = (".cs", ".java", ".go", ".py", ".ps1", ".sh")
BUILD_DIRS = {"bin", "obj", "build", "target", ".gradle"}

# Any section header comment, such as "// --- connect ---": headers only delimit blocks.
MARKER_RE = re.compile(r"^\s*(//|#)\s*-{3,}\s*\S")
# The "OK: <workflow>" line every example prints on success: it ties a file to its workflow.
OK_LINE_RE = re.compile(r"OK:\s*([a-z0-9][a-z0-9-]*)")
# The marker a file uses to say "the connect example starts here".
CONNECT_MARKER_RE = re.compile(r"^\s*(//|#)\s*-{3,}\s*connect\s*-*\s*$", re.IGNORECASE)


# ---- catalogue -----------------------------------------------------------------------------

def load_sections():
    """workflows.json's sections, in order: [(name, [workflow, ...])]."""
    with open(os.path.join(ROOT, "workflows.json"), encoding="utf-8") as f:
        data = json.load(f)
    return [(s["name"], s["workflows"]) for s in data["sections"]]


# ---- reading the sources -------------------------------------------------------------------

def read_lines(path):
    """The file's lines without their endings (any of CRLF, LF, CR), as .NET's ReadAllLines gives them."""
    with open(path, encoding="utf-8-sig", newline="") as f:
        text = f.read()
    lines = re.split(r"\r\n|\r|\n", text)
    if lines and lines[-1] == "":
        lines.pop()
    return lines


def source_files(directory):
    """The source files under a language's directory, skipping build output, in a stable order."""
    found = []
    for dirpath, dirnames, filenames in os.walk(directory):
        dirnames[:] = [d for d in dirnames if d not in BUILD_DIRS]
        for name in filenames:
            if name.lower().endswith(SOURCE_EXTENSIONS):
                found.append(os.path.relpath(os.path.join(dirpath, name), directory).replace(os.sep, "/"))
    return sorted(found)


def indent(line):
    return len(line) - len(line.lstrip(" \t"))


def slice_lines(lines, start, stop):
    """lines[start:stop] without leading/trailing blank lines, dedented by their common indentation."""
    chunk = lines[start:stop]
    while chunk and not chunk[-1].strip():
        chunk.pop()
    while chunk and not chunk[0].strip():
        chunk.pop(0)
    shared = min((indent(l) for l in chunk if l.strip()), default=0)
    return "\n".join(l[shared:] if len(l) >= shared else l.lstrip() for l in chunk)


def class_body(lines):
    """The lines inside a file's type declaration - between the first line that is just "{" and the
    last that is just "}" - or the whole file if it has none: what a reader would copy."""
    opens = [i for i, l in enumerate(lines) if l.rstrip() == "{"]
    closes = [i for i, l in enumerate(lines) if l.rstrip() == "}"]
    if opens and closes and closes[-1] > opens[0]:
        return lines[opens[0] + 1:closes[-1]]
    return lines


def marked_blocks(lines):
    """A file's blocks between section markers: (connect snippet, {workflow id: snippet})."""
    end_at = len(lines)
    markers = []
    for i, line in enumerate(lines):
        if "end of workflows" in line:
            end_at = i
            continue
        if MARKER_RE.match(line):
            markers.append(i)
    by_id, connect = {}, ""
    for k, start in enumerate(markers):
        stop = min(markers[k + 1], end_at) if k + 1 < len(markers) else end_at
        # A block also ends where its enclosing one does: a line indented less than the marker.
        for j in range(start + 1, stop):
            if lines[j].strip() and indent(lines[j]) < indent(lines[start]):
                stop = j
                break
        if stop <= start:
            continue
        code = slice_lines(lines, start + 1, stop)   # the marker itself is not shown
        if CONNECT_MARKER_RE.match(lines[start]):
            connect = code
            continue
        match = OK_LINE_RE.search(code)
        if match:
            by_id[match.group(1)] = code
    return connect, by_id


def extract_snippets(directory):
    """A language's code to show: (connect snippet, {workflow id: snippet}, {workflow id: file}).

    Each workflow has a file of its own, and its snippet is the file's type body (or the whole file),
    keyed by the id in its "OK: <id>" line - never by position. The connect snippet comes from the file
    with a "--- connect ---" marker."""
    by_id, files, connect = {}, {}, ""
    for rel in source_files(directory):
        lines = read_lines(os.path.join(directory, rel))
        body = class_body(lines)
        file_connect, file_by_id = marked_blocks(body)
        if file_connect:
            connect = file_connect
            continue
        if file_by_id:
            continue
        code = slice_lines(body, 0, len(body))
        match = OK_LINE_RE.search(code)
        if match:
            by_id[match.group(1)] = code
            files.setdefault(match.group(1), rel)
    return connect, by_id, files


def code_hash(code):
    """A short, stable fingerprint of a snippet."""
    return hashlib.sha256(code.replace("\r\n", "\n").encode("utf-8")).hexdigest()[:12]


# ---- recorded example output ---------------------------------------------------------------

def escape(s):
    return s.replace("\\", "\\\\").replace("\r", "").replace("\n", "\\n").replace("\t", "\\t")


def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != "\\" or i + 1 >= len(s):
            out.append(c)
        else:
            i += 1
            out.append({"n": "\n", "t": "\t", "\\": "\\"}.get(s[i], "\\" + s[i]))
        i += 1
    return "".join(out)


def read_tsv(path, columns):
    rows = []
    if os.path.exists(path):
        for line in read_lines(path):
            parts = line.split("\t")
            if len(parts) == columns:
                rows.append(parts)
    return rows


def recorded_output():
    """{(language, workflow): (code hash, output)} from sample-output.tsv."""
    return {(lang, wf): (h, unescape(out)) for lang, wf, h, out in read_tsv(SAMPLE_STORE, 4)}


def store_text(samples, languages, workflows):
    """sample-output.tsv's content: catalogue members only, sorted, one line per example."""
    lines = ["%s\t%s\t%s\t%s" % (lang, wf, h, escape(out))
             for (lang, wf), (h, out) in sorted(samples.items())
             if lang in languages and wf in workflows]
    return "\n".join(lines) + "\n"


def merge_captured(samples, captured_path, hashes, refresh):
    """Take each newly captured output whose code differs from the code its recorded output came from."""
    for lang, wf, out in read_tsv(captured_path, 3):
        out = unescape(out)
        if not out.strip():
            continue
        h = hashes.get((lang, wf), "")
        if refresh or samples.get((lang, wf), ("", ""))[0] != h:
            samples[(lang, wf)] = (h, out)


# ---- pages ---------------------------------------------------------------------------------

def fenced(language, code):
    """A fenced code block whose fence is longer than any backtick run inside it."""
    longest = max((len(m) for m in re.findall(r"`+", code)), default=0)
    fence = "`" * max(3, longest + 1)
    return "%s%s\n%s\n%s" % (fence, language, code.rstrip(), fence)


def cell(s):
    return s.replace("|", "\\|").replace("\n", " ")


def first_sentence(s):
    if not s or not s.strip():
        return ""
    i = s.find(". ")
    return s[:i + 1] if i > 0 else s


def index_page(sections):
    titles = [title for _, title, _, _ in LANGUAGES]
    md = [BANNER, "",
          "# Workflow examples", "",
          "Real-world pool-management tasks, each implemented in " + ", ".join(titles[:-1]) +
          " and the %s. Each page shows the code in every language and example output from running it "
          "against a test pool: on yours, the names, addresses and UUIDs will differ. Every program "
          "first opens a session: see [Connecting](connecting.md)." % titles[-1], "",
          "Run any of them with `<program> <workflow> <url> <user> <password> [key=value ...]`; see the "
          "[repository README](../../README.md) for how to build and run each language.", ""]
    for name, workflows in sections:
        md += ["## " + name, "", "| Workflow | What it does |", "|---|---|"]
        md += ["| [%s](%s.md) | %s |" % (cell(w["title"]), w["id"], cell(first_sentence(w["description"])))
               for w in workflows]
        md.append("")
    md += ["## Source files", "", "Where every workflow above lives, per language:", ""]
    md += ["- %s: [`%s/`](../../%s) (one file per workflow)" % (title, src, src)
           for _, title, src, _ in LANGUAGES]
    return "\n".join(md)


def connecting_page(snippets):
    md = [BANNER, "", "# Connecting", "",
          "Every workflow starts the same way: open a session to the pool's coordinator, accepting its "
          "certificate (hosts ship with a self-signed one) and logging in. If you connect to a pool member "
          "instead, login fails with `HOST_IS_SLAVE` naming the coordinator, and these helpers reconnect "
          "there.", "",
          "[All workflows](README.md)", ""]
    for lang, title, _, highlight in LANGUAGES:
        md += ["## " + title, "", fenced(highlight, snippets[lang][0]), ""]
    return "\n".join(md)


def workflow_page(wf, snippets, samples):
    md = [BANNER, "", "# " + wf["title"], "", wf["description"], ""]
    if wf.get("requires"):
        md += ["**Requires:** %s." % wf["requires"], ""]
    if wf.get("caution"):
        md += ["**Caution:** %s." % wf["caution"], ""]
    md += ["Workflow `%s`. [All workflows](README.md) · [Connecting](connecting.md)" % wf["id"], ""]
    for lang, title, src, highlight in LANGUAGES:
        _, by_id, files = snippets[lang]
        md += ["## " + title, ""]
        if wf["id"] in files:
            md += ["Source: [`%s/%s`](../../%s/%s)" % (src, files[wf["id"]], src, files[wf["id"]]), ""]
        why = (wf.get("unsupported") or {}).get(lang)
        if why:
            md += ["*Not available in %s: %s*" % (title, why), ""]
        elif wf["id"] in by_id:
            md += [fenced(highlight, by_id[wf["id"]]), ""]
        else:
            md += ["*Not found in `%s`.*" % src, ""]
        output = samples.get((lang, wf["id"]), ("", ""))[1]
        if output.strip():
            md += ["<details><summary>Example output</summary>", "", fenced("text", output), "",
                   "</details>", ""]
    return "\n".join(md)


def normalise(text):
    return text.replace("\r\n", "\n").rstrip() + "\n"


# ---- checks --------------------------------------------------------------------------------

def catalogue_problems(sections, snippets):
    """Disagreements between workflows.json and the sources: each would leave a page showing nothing,
    or a workflow documented nowhere."""
    problems = []
    workflows = [w for _, ws in sections for w in ws]
    listed = {w["id"] for w in workflows}
    for lang, _, _, _ in LANGUAGES:
        connect, by_id, _ = snippets[lang]
        if not connect.strip():
            problems.append("%s: no '--- connect ---' marker" % lang)
        for w in workflows:
            unsupported = lang in (w.get("unsupported") or {})
            if not unsupported and w["id"] not in by_id:
                problems.append("%s: %s is missing (no file prints 'OK: %s')" % (lang, w["id"], w["id"]))
            if unsupported and w["id"] in by_id:
                problems.append("%s: %s is implemented, but workflows.json says it is unsupported"
                                % (lang, w["id"]))
        problems += ["%s: %s is not in workflows.json" % (lang, i) for i in sorted(set(by_id) - listed)]
    return problems


# ---- main ----------------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true",
                        help="change nothing; fail if a page is out of date or the catalogue disagrees")
    parser.add_argument("--captured", metavar="FILE", help="newly captured example output to record first")
    parser.add_argument("--refresh", action="store_true",
                        help="with --captured: take every capture, even for unchanged code")
    args = parser.parse_args()

    sections = load_sections()
    workflows = [w for _, ws in sections for w in ws]
    snippets = {lang: extract_snippets(os.path.join(ROOT, src)) for lang, _, src, _ in LANGUAGES}
    hashes = {(lang, i): code_hash(code) for lang, (_, by_id, _) in snippets.items()
              for i, code in by_id.items()}

    samples = recorded_output()
    # Output recorded without a hash is taken to match the current code.
    samples = {k: (h or hashes.get(k, ""), out) for k, (h, out) in samples.items()}
    if args.captured:
        merge_captured(samples, args.captured, hashes, args.refresh)

    pages = {"README.md": index_page(sections), "connecting.md": connecting_page(snippets)}
    pages.update({w["id"] + ".md": workflow_page(w, snippets, samples) for w in workflows})
    pages = {name: normalise(text) for name, text in pages.items()}
    store = store_text(samples, {l[0] for l in LANGUAGES}, {w["id"] for w in workflows})

    existing = sorted(n for n in os.listdir(OUT_DIR) if n.endswith(".md")) if os.path.isdir(OUT_DIR) else []
    if args.check:
        problems = catalogue_problems(sections, snippets)
        for name, text in sorted(pages.items()):
            path = os.path.join(OUT_DIR, name)
            if not os.path.exists(path) or normalise(open(path, encoding="utf-8").read()) != text:
                problems.append("docs/workflows/%s is out of date" % name)
        problems += ["docs/workflows/%s describes no workflow" % n for n in existing if n not in pages]
        for p in problems:
            print(p, file=sys.stderr)
        if problems:
            print("Run tools/docs/generate_docs.py to regenerate the pages.", file=sys.stderr)
        return 1 if problems else 0

    os.makedirs(OUT_DIR, exist_ok=True)
    # A page for a workflow that no longer exists would stay, linked from nowhere.
    for name in existing:
        if name not in pages:
            os.remove(os.path.join(OUT_DIR, name))
    for name, text in pages.items():
        with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    with open(SAMPLE_STORE, "w", encoding="utf-8", newline="\n") as f:
        f.write(store)
    return 0


if __name__ == "__main__":
    sys.exit(main())
