"""Focus Guard の静的チェック（Windows など Xcode が無い環境用）。

Swift のコンパイルの代わりにはならない（型の誤りは GitHub Actions の macOS ビルドで見つかる）。確認する内容:
  1. Swift ファイルの構文（tree-sitter-swift。pip install tree-sitter-language-pack）
  2. 括弧の対応
  3. project.yml のソースパス・拡張の種類・権限（Family Controls / App Group）
  4. 拡張の主クラス名がコード中に存在するか
  5. 本体と拡張が同じ保存処理（FocusStore）と制限処理（ShieldController）を使っているか
使い方: python scripts/static_check.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT_DIRS = ["FocusGuard", "FocusGuardMonitor", "FocusGuardShield", "FocusGuardShieldAction",
              "FocusGuardReport", "Shared", "Packages/FocusGuardKit"]

EXPECTED_EXTENSIONS = {
    "FocusGuardMonitor": "com.apple.deviceactivity.monitor-extension",
    "FocusGuardShield": "com.apple.ManagedSettingsUI.shield-configuration-service",
    "FocusGuardShieldAction": "com.apple.ManagedSettings.shield-action-service",
    "FocusGuardReport": "com.apple.deviceactivityui.report-extension",
}

errors: list[str] = []
warnings: list[str] = []


def swift_files() -> list[Path]:
    files: list[Path] = []
    for d in SWIFT_DIRS:
        files += sorted((ROOT / d).rglob("*.swift"))
    return [f for f in files if ".build" not in f.parts]


def strip_strings_and_comments(src: str) -> str:
    src = re.sub(r'"""[\s\S]*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*[\s\S]*?\*/", "", src)
    return src


def check_syntax(files: list[Path]) -> None:
    try:
        from tree_sitter_language_pack import get_parser  # type: ignore
    except ImportError:
        warnings.append("tree-sitter-language-pack が無いため構文チェックを省略（pip install tree-sitter-language-pack）")
        return
    parser = get_parser("swift")
    for f in files:
        source = f.read_bytes()
        tree = parser.parse(source)
        bad = []

        def walk(node):
            if node.type == "ERROR" or node.is_missing:
                bad.append(node)
                return
            for child in node.children:
                walk(child)

        walk(tree.root_node)
        lines = source.decode("utf-8").splitlines()
        for node in bad[:3]:
            line = node.start_point[0] + 1
            kind = "欠落" if node.is_missing else "解析不能"
            errors.append(f"構文({kind}) {f.relative_to(ROOT)}:{line}: {lines[line - 1].strip()[:90]}")


def check_balance(files: list[Path]) -> None:
    pairs = {"(": ")", "[": "]", "{": "}"}
    for f in files:
        src = strip_strings_and_comments(f.read_text(encoding="utf-8"))
        stack = []
        for ch in src:
            if ch in pairs:
                stack.append(ch)
            elif ch in pairs.values():
                if not stack or pairs[stack.pop()] != ch:
                    errors.append(f"括弧の対応が不正: {f.relative_to(ROOT)}")
                    break
        else:
            if stack:
                errors.append(f"閉じていない括弧: {f.relative_to(ROOT)}")


def check_project() -> None:
    try:
        import yaml  # type: ignore
    except ImportError:
        warnings.append("PyYAML が無いため project.yml の検査を省略")
        return
    spec = yaml.safe_load((ROOT / "project.yml").read_text(encoding="utf-8"))
    template = spec["targetTemplates"]["FGEntitled"]["entitlements"]["properties"]
    if template.get("com.apple.developer.family-controls") is not True:
        errors.append("Family Controls の権限がテンプレートに無い")
    if template.get("com.apple.security.application-groups") != ["$(APP_GROUP_ID)"]:
        errors.append("App Group が APP_GROUP_ID を参照していない")

    for name, target in spec["targets"].items():
        if "FGEntitled" not in target.get("templates", []):
            errors.append(f"{name}: 権限テンプレート FGEntitled を使っていない")
        for src in target["sources"]:
            if not (ROOT / src["path"]).exists():
                errors.append(f"{name}: ソースパスが存在しない {src['path']}")
        props = target["info"]["properties"]
        if name in EXPECTED_EXTENSIONS:
            ext = props.get("NSExtension", {})
            if ext.get("NSExtensionPointIdentifier") != EXPECTED_EXTENSIONS[name]:
                errors.append(f"{name}: NSExtensionPointIdentifier が違う")
            principal = ext.get("NSExtensionPrincipalClass")
            if principal:
                cls = principal.split(".")[-1]
                code = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / name).rglob("*.swift"))
                if not re.search(rf"class {cls}\b", code):
                    errors.append(f"{name}: 主クラス {cls} がコードに無い")
            if name != "FocusGuardReport" and props.get("FGAppGroupID") != "$(APP_GROUP_ID)":
                errors.append(f"{name}: Info.plist に FGAppGroupID が無い")
        if name == "FocusGuard":
            deps = {d.get("target") for d in target["dependencies"]}
            for ext_name in EXPECTED_EXTENSIONS:
                if ext_name not in deps:
                    errors.append(f"本体が {ext_name} を埋め込んでいない")

    pkg = ROOT / spec["packages"]["FocusGuardKit"]["path"] / "Package.swift"
    if not pkg.exists():
        errors.append("FocusGuardKit の Package.swift が無い")
    for js in (ROOT / "FocusGuard/Resources").rglob("*.json"):
        try:
            json.loads(js.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errors.append(f"JSON不正 {js.relative_to(ROOT)}: {e}")


def check_shared_usage() -> None:
    """本体と拡張が、同じ保存処理・同じ制限判定を通しているか"""
    must = {
        "FocusGuard/App/AppModel.swift": ["FocusStore", "ShieldController.reconcile", "ReviewEngine.review", "SessionMonitor.start"],
        "FocusGuardMonitor/FocusMonitor.swift": ["store.update", "ShieldController.reconcile"],
        "FocusGuardShieldAction/ShieldActionExtension.swift": ["store.update", "recordShieldEvent"],
    }
    for rel, needles in must.items():
        text = (ROOT / rel).read_text(encoding="utf-8")
        for n in needles:
            if n not in text:
                errors.append(f"{rel}: {n} を使っていない")
    # 緊急解除は AI・通信を通さない
    model = (ROOT / "FocusGuard/App/AppModel.swift").read_text(encoding="utf-8")
    body = re.search(r"func emergencyUnlock[\s\S]*?\n    }\n", model)
    if not body or "OnDeviceAIReviewer" in body.group(0) or "await" in body.group(0):
        errors.append("緊急解除が AI や非同期処理を経由している")
    # 外部AI APIを使っていない
    for f in swift_files():
        text = f.read_text(encoding="utf-8")
        if re.search(r"https?://|URLSession|api\.openai|api\.anthropic", text):
            errors.append(f"通信処理がある（外部API禁止）: {f.relative_to(ROOT)}")


def main() -> int:
    files = swift_files()
    check_syntax(files)
    check_balance(files)
    check_project()
    check_shared_usage()
    print(f"Swift ファイル: {len(files)} 件")
    for w in warnings:
        print("注意:", w)
    for e in errors:
        print("NG:", e)
    print("結果:", "問題なし" if not errors else f"{len(errors)} 件の問題")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
