#!/usr/bin/env python3
"""Data guard: stops a build that would lose or hide the owner's data.

Run before every TestFlight archive (testflight.yml) and every CI build (build.yml):

    python3 .github/scripts/data_guard.py            # check (exit 1 on any problem)
    python3 .github/scripts/data_guard.py --update   # remember NEW model fields / keys (never forgets old ones)
    python3 .github/scripts/data_guard.py --accept-entitlements   # after an intended entitlement change ONLY

What it checks (snapshots live in .github/data-guard/):
  1. SwiftData store location. Rootbound and Roamr open their store with `url: LocalStore.url` (the app's own
     Application Support folder). Pulse Lab keeps SwiftData's default location, which is its first App Group
     (group.com.troydunn.pulselab) - it must NOT be switched to LocalStore.url, that would hide the Stack.
     The only other on-disk configuration allowed is the rescue's private copy (GroupStoreRescue.openCopy).
  2. Entitlements (App Groups and their order, iCloud containers, HealthKit ...) in project.yml match
     entitlements.json exactly.
  3. @Model stored properties: none renamed, removed or retyped; new ones need a default or must be optional.
  4. UserDefaults / @AppStorage keys: every key ever recorded still exists in its app.
  5. Files and folders that hold user data keep their names (pins.json).
  6. Every InfoPlist.xcstrings key has a real English value (ITMS-90738).
  7. Deep-link schemes and LSApplicationQueriesSchemes match links.json.
"""
import json
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GUARD = os.path.join(ROOT, ".github", "data-guard")

# Apps and the folders whose code runs inside them (keys are remembered per app).
APPS = {
    "Rootbound": ["TreeHub", "Shared", "RootboundWidgets", "RootboundWatch", "RootboundWatchWidgets"],
    "Roamr": ["TrackApp", "Shared", "RoamrWidgets", "RoamrWatch"],
    "PulseLab": ["PulseLab", "Shared/Store", "Shared/Wellness", "PulseLabWidgets", "PulseLabWatch", "PulseLabWatchWidgets"],
    "StillPoint": ["StillPoint", "Shared/Store", "Shared/Wellness", "StillPointWidgets", "StillPointWatch"],
    "Clicker": ["TVRemote", "Shared/Store", "ClankerrWatch", "ClankerrWidgets"],
    "WebShell": ["WebApps/Shell", "WebApps/NatalOrbit/Native", "WebApps/NatalOrbit/Widgets",
                 "WebApps/QuestApp/Native", "WebApps/QuestApp/Widgets"],
}

# Where each SwiftData app keeps its store. Anything not listed here may not create an on-disk store.
STORE_RULES = {
    # file -> rule for every ModelConfiguration( ... ) in it
    "TreeHub/App/TreeHubApp.swift": "local",
    "TrackApp/App/TrackHubApp.swift": "local",
    # Pulse Lab had its App Group before it had SwiftData: its store has always been in the group container.
    "PulseLab/Data/CloudSync.swift": "default",
    # The Nov 15 rescue reads a private temporary COPY of the stray shared store.
    "Shared/Models/StoreRescue.swift": "rescue-copy",
}
PULSELAB_GROUP = "group.com.troydunn.pulselab"

errors = []
notes = []


def err(msg):
    errors.append(msg)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def load_json(name, default=None):
    p = os.path.join(GUARD, name)
    if not os.path.exists(p):
        return default
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def save_json(name, value):
    os.makedirs(GUARD, exist_ok=True)
    with open(os.path.join(GUARD, name), "w", encoding="utf-8") as f:
        json.dump(value, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")


def load_project():
    path = os.path.join(ROOT, "project.yml")
    try:
        import yaml  # type: ignore
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f)
    except ImportError:
        out = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.load_file(ARGV[0]))", path],
            check=True, capture_output=True, text=True).stdout
        return json.loads(out)


def swift_files(dirs):
    seen = []
    for d in dirs:
        base = os.path.join(ROOT, d)
        if os.path.isfile(base):
            if base.endswith(".swift"):
                seen.append(os.path.relpath(base, ROOT))
            continue
        for dp, _, files in os.walk(base):
            for fn in files:
                if fn.endswith(".swift"):
                    seen.append(os.path.relpath(os.path.join(dp, fn), ROOT))
    return sorted(set(seen))


def strip_comments(src):
    """Blank out // and /* */ comments, keeping string literals and line numbers."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"' and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def call_args(src, start):
    """Text between the parenthesis at src[start] and its match."""
    depth, i = 0, start
    while i < len(src):
        if src[i] == "(":
            depth += 1
        elif src[i] == ")":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
        i += 1
    return src[start + 1:]


# ---------------------------------------------------------------- 1. store location

def check_store(project):
    all_dirs = sorted({d for dirs in APPS.values() for d in dirs})
    for path in swift_files(all_dirs):
        src = strip_comments(read(path))
        rule = STORE_RULES.get(path)
        for m in re.finditer(r"\bModelConfiguration\s*\(", src):
            args = " ".join(call_args(src, m.end() - 1).split())
            line = src.count("\n", 0, m.start()) + 1
            where = f"{path}:{line}: ModelConfiguration({args})"
            if re.search(r"isStoredInMemoryOnly:\s*true", args):
                continue
            if "groupContainer:" in args or "containerURL" in args or "strayStoreURL" in args:
                err(f"{where}\n    opens a store inside an App Group. That is what hid the hugs and trips on Nov 15.")
            elif rule == "local":
                if not re.search(r"\burl:\s*LocalStore\.url\b", args):
                    err(f"{where}\n    must pass `url: LocalStore.url` (or be in-memory).")
            elif rule == "default":
                if "url:" in args:
                    err(f"{where}\n    Pulse Lab's store lives in its App Group ({PULSELAB_GROUP}), where SwiftData put it "
                        "from the first build. Do NOT give it a url (LocalStore.url would open a new, empty Stack).")
            elif rule == "rescue-copy":
                if not re.search(r"\burl:\s*copy\b", args) or not re.search(r"cloudKitDatabase:\s*\.none", args):
                    err(f"{where}\n    the rescue may only open its private temporary copy (`url: copy`, `cloudKitDatabase: .none`).")
            else:
                err(f"{where}\n    new on-disk SwiftData store. Use `url: LocalStore.url` and add the file to STORE_RULES "
                    "in .github/scripts/data_guard.py.")
        # Containers made without a configuration use SwiftData's default location (an App Group when the app has one).
        for m in re.finditer(r"\bModelContainer\s*\(", src):
            args = call_args(src, m.end() - 1)
            if "configurations:" not in args:
                line = src.count("\n", 0, m.start()) + 1
                err(f"{path}:{line}: ModelContainer(...) without `configurations:` uses the default location. "
                    "Pass a ModelConfiguration with `url: LocalStore.url`.")
        for m in re.finditer(r"\.modelContainer\s*\(\s*for:", src):
            line = src.count("\n", 0, m.start()) + 1
            err(f"{path}:{line}: .modelContainer(for:) uses the default location. Build the container with "
                "`url: LocalStore.url` and pass it instead.")
    # The rescue must never touch the stray shared file itself.
    rescue = "Shared/Models/StoreRescue.swift"
    if os.path.exists(os.path.join(ROOT, rescue)):
        for path in swift_files(["Shared", "TreeHub", "TrackApp"]):
            src = strip_comments(read(path))
            if "strayStoreURL" not in src:
                continue
            for bad in (r"removeItem\s*\(\s*at:\s*stray", r"moveItem\s*\(\s*at:\s*stray", r"openCopy\s*\(\s*stray",
                        r"\.write\s*\(\s*to:\s*stray"):
                if re.search(bad, src):
                    err(f"{path}: the rescue must leave the stray shared store untouched (found `{bad}`).")
    # LocalStore itself.
    ls = strip_comments(read("Shared/Store/LocalStore.swift"))
    if "URL.applicationSupportDirectory" not in ls or '"default.store"' not in ls or "containerURL" in ls:
        err("Shared/Store/LocalStore.swift: LocalStore.url must stay "
            "`URL.applicationSupportDirectory` + \"default.store\" (the app's own sandbox).")
    # Pulse Lab's default location is its FIRST App Group.
    groups = ((project["targets"].get("PulseLab", {}).get("entitlements", {}) or {}).get("properties", {}) or {}) \
        .get("com.apple.security.application-groups", [])
    if not groups or groups[0] != PULSELAB_GROUP:
        err(f"project.yml: PulseLab's first App Group must stay {PULSELAB_GROUP} (its SwiftData store is in that "
            f"group's container). Found {groups}.")


# ---------------------------------------------------------------- 2. entitlements

def entitlements(project):
    out = {}
    for name, t in project["targets"].items():
        e = t.get("entitlements")
        if e:
            out[name] = {"path": e.get("path"), "properties": e.get("properties") or {}}
    return out


def check_entitlements(project, accept, generated):
    now = entitlements(project)
    if accept:
        save_json("entitlements.json", now)
        notes.append("entitlements.json rewritten from project.yml")
        return
    want = load_json("entitlements.json")
    if want is None:
        err("Missing .github/data-guard/entitlements.json")
        return
    for name in sorted(set(now) | set(want)):
        a, b = want.get(name), now.get(name)
        if a == b:
            continue
        if b is None:
            err(f"project.yml: target {name} lost its entitlements.")
            continue
        if a is None:
            err(f"project.yml: target {name} has entitlements that are not in entitlements.json: {json.dumps(b['properties'])}")
            continue
        ap, bp = a["properties"], b["properties"]
        for k in sorted(set(ap) | set(bp)):
            if ap.get(k) != bp.get(k):
                err(f"project.yml: {name} entitlement {k} changed: allowed {json.dumps(ap.get(k))}, "
                    f"found {json.dumps(bp.get(k))}")
        if a.get("path") != b.get("path"):
            err(f"project.yml: {name} entitlements path changed: {a.get('path')} -> {b.get('path')}")
    if any("entitlement" in e for e in errors):
        err("Entitlements decide where data is stored and shared (App Groups, iCloud). If this change is really "
            "intended and no stored data moves, run `python3 .github/scripts/data_guard.py --accept-entitlements` "
            "and commit .github/data-guard/entitlements.json with it.")
    if generated:
        # After `xcodegen generate`: the files Xcode will actually sign with.
        for name, e in want.items():
            p = os.path.join(ROOT, e["path"] or "")
            if not os.path.exists(p):
                err(f"{e['path']}: generated entitlements file is missing.")
                continue
            with open(p, "rb") as f:
                got = plistlib.load(f)
            if got != e["properties"]:
                err(f"{e['path']}: generated entitlements differ from entitlements.json: {json.dumps(got, sort_keys=True)}")


# ---------------------------------------------------------------- 3. @Model properties

def model_properties():
    """{Model: {property: {"type": str, "safe": bool}}} for every @Model class in the shipped apps."""
    out = {}
    all_dirs = sorted({d for dirs in APPS.values() for d in dirs})
    for path in swift_files(all_dirs):
        src = strip_comments(read(path))
        for m in re.finditer(r"@Model\s+(?:final\s+)?class\s+(\w+)[^{]*\{", src):
            name, i, depth = m.group(1), m.end(), 1
            body_start = i
            while i < len(src) and depth:
                depth += {"{": 1, "}": -1}.get(src[i], 0)
                i += 1
            props, depth = {}, 0
            for line in src[body_start:i - 1].split("\n"):
                at_top = depth == 0
                depth += line.count("{") - line.count("}")
                if not at_top:
                    continue
                pm = re.match(r"\s*((?:@\w+(?:\([^)]*\))?\s+)*)(?:(?:private|public|internal|fileprivate)(?:\(set\))?\s+)*var\s+(\w+)\s*(?::\s*([^={]+?))?\s*(=\s*(.+?))?\s*(\{.*)?$", line)
                if not pm:
                    continue
                attrs, prop, typ, has_default, default, brace = pm.groups()
                if "@Transient" in attrs:
                    continue
                if brace and not has_default:
                    continue  # computed property
                typ = (typ or "").strip()
                if not typ:
                    typ = "= " + (default or "").strip()
                optional = typ.endswith("?")
                props[prop] = {"type": typ, "safe": bool(has_default) or optional}
            out[name] = props
    return out


def check_models(update):
    now = model_properties()
    snap = load_json("models.json", {})
    for model, props in sorted(now.items()):
        for p, info in sorted(props.items()):
            if not info["safe"]:
                err(f"@Model {model}.{p}: stored properties need a default value or must be optional "
                    "(otherwise the existing store cannot be opened and the app starts empty).")
    for model, props in sorted(snap.items()):
        if model not in now:
            err(f"@Model {model} is gone (renamed or removed). Its records would disappear.")
            continue
        for p, typ in sorted(props.items()):
            if p not in now[model]:
                err(f"@Model {model}.{p} is gone (renamed or removed). Every saved value of it would be lost.")
            elif now[model][p]["type"] != typ:
                err(f"@Model {model}.{p} changed type: {typ} -> {now[model][p]['type']}.")
    added = {m: {p: i["type"] for p, i in props.items() if p not in snap.get(m, {})} for m, props in now.items()}
    added = {m: v for m, v in added.items() if v}
    if added:
        notes.append("new @Model fields (fine; not yet in models.json): " + json.dumps(added, sort_keys=True))
        if update:
            for m, v in added.items():
                snap.setdefault(m, {}).update(v)
            save_json("models.json", snap)


# ---------------------------------------------------------------- 4. UserDefaults keys

KEY_USE = re.compile(r"(?:forKey:\s*|@AppStorage\(\s*|NSUbiquitousKeyValueStore\.default\.\w+\(forKey:\s*)(\"(?:[^\"\\\n]|\\.)*\"|[A-Za-z_][\w.]*)")
LET_STR = re.compile(r"\blet\s+(\w+)\s*(?::\s*String)?\s*=\s*\"((?:[^\"\\\n]|\\.)*)\"")
CODING_KEY = re.compile(r"forKey:\s*\.\w+")


def app_keys(dirs):
    files = {p: strip_comments(read(p)) for p in swift_files(dirs)}
    consts = {}
    for p, src in files.items():
        for m in LET_STR.finditer(src):
            consts.setdefault(m.group(1), set()).add(m.group(2))
    keys = set()
    for p, src in files.items():
        for m in KEY_USE.finditer(src):
            tok = m.group(1)
            if tok.startswith('"'):
                # "tv.name.\(host)" -> "tv.name.\(…)"; keys that are all interpolation are not names.
                k = re.sub(r"\\\([^)]*\)", "\\(…)", tok[1:-1])
                if not tok.startswith('"\\('):
                    keys.add(k)
            else:
                ident = tok.split(".")[-1]
                if ident in ("self", "Self"):
                    continue
                keys.update(v for v in consts.get(ident, ()) if not v.startswith('\\('))
    return keys


def check_keys(update):
    snap = load_json("keys.json", {})
    changed = False
    for app, dirs in APPS.items():
        now = app_keys(dirs)
        old = set(snap.get(app, []))
        for k in sorted(old - now):
            err(f"{app}: UserDefaults / AppStorage key \"{k}\" is no longer used (renamed or removed). "
                "Whatever was saved under it would be invisible after the update. Keep reading the old key.")
        new = now - old
        if new:
            notes.append(f"{app}: {len(new)} new key(s) not yet in keys.json: {', '.join(sorted(new))}")
            if update:
                snap[app] = sorted(old | now)
                changed = True
    if changed:
        save_json("keys.json", snap)


# ---------------------------------------------------------------- 5. file names

def check_pins():
    for pin in load_json("pins.json", []):
        path = pin["file"]
        if not os.path.exists(os.path.join(ROOT, path)):
            err(f"{path} is gone; it held {pin['why']}. If it moved, update .github/data-guard/pins.json "
                "and make sure the data is still read from the same place.")
            continue
        src = strip_comments(read(path))
        for s in pin["contains"]:
            if s not in src:
                err(f"{path}: `{s}` is gone ({pin['why']}). Changing it hides existing data.")


# ---------------------------------------------------------------- 6. InfoPlist.xcstrings

def check_xcstrings():
    for dp, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", "build", "node_modules")]
        for fn in files:
            if fn != "InfoPlist.xcstrings":
                continue
            rel = os.path.relpath(os.path.join(dp, fn), ROOT)
            with open(os.path.join(dp, fn), encoding="utf-8") as f:
                cat = json.load(f)
            for key, entry in cat.get("strings", {}).items():
                value = (((entry.get("localizations") or {}).get("en") or {}).get("stringUnit") or {}).get("value", "")
                if not value.strip() or value.strip() == key:
                    err(f"{rel}: \"{key}\" has no English value (Apple shows the raw key in permission prompts, ITMS-90738).")


# ---------------------------------------------------------------- 7. deep links

def links(project):
    out = {}
    for name, t in project["targets"].items():
        props = ((t.get("info") or {}).get("properties") or {})
        schemes = sorted(s for u in props.get("CFBundleURLTypes", []) for s in u.get("CFBundleURLSchemes", []))
        queries = sorted(props.get("LSApplicationQueriesSchemes", []))
        if schemes or queries:
            out[name] = {"schemes": schemes, "queries": queries}
    return out


def check_links(project, accept):
    now = links(project)
    if accept:
        save_json("links.json", now)
        return
    want = load_json("links.json", {})
    for name, w in sorted(want.items()):
        n = now.get(name, {"schemes": [], "queries": []})
        for s in w["schemes"]:
            if s not in n["schemes"]:
                err(f"project.yml: {name} no longer answers {s}:// links (the other apps open it with them).")
        for s in w["queries"]:
            if s not in n["queries"]:
                err(f"project.yml: {name} lost LSApplicationQueriesSchemes `{s}` (canOpenURL would say the other app "
                    "isn't installed).")


def main():
    args = set(sys.argv[1:])
    update = "--update" in args
    project = load_project()
    check_store(project)
    check_entitlements(project, "--accept-entitlements" in args, "--generated" in args)
    check_models(update)
    check_keys(update)
    check_pins()
    check_xcstrings()
    check_links(project, "--accept-links" in args)
    for n in notes:
        print("note: " + n)
    if errors:
        print(f"\nDATA GUARD FAILED ({len(errors)} problem(s)). This build could lose or hide saved data:\n")
        for e in errors:
            print(" - " + e)
            if os.environ.get("GITHUB_ACTIONS"):
                print("::error::" + e.split("\n")[0])
        sys.exit(1)
    print("Data guard passed: store locations, entitlements, model fields, saved keys, file names, "
          "permission texts and deep links are unchanged.")


if __name__ == "__main__":
    main()
