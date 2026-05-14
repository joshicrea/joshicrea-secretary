#!/usr/bin/env python3
# AI秘書プラグイン インストールスクリプト（Mac / Linux用）
# 使い方: Claude Code のチャットに以下をそのままコピペしてください
#
#   以下のURLからAI秘書プラグインのインストールスクリプトを取得して、
#   内容を確認してから実行してください:
#   https://raw.githubusercontent.com/joshicrea/joshicrea-secretary/master/install.py
#
import sys, os, json, urllib.request, zipfile, shutil, tempfile, pathlib, datetime

sys.stdout.reconfigure(encoding="utf-8")

print()
print("AI秘書プラグインをインストールしています...")
print()

# --- パス設定 ---
HOME_DIR   = pathlib.Path.home()
CLAUDE_DIR = HOME_DIR / ".claude"
PLUGINS_DIR = CLAUDE_DIR / "plugins"
CACHE_DIR   = PLUGINS_DIR / "cache" / "joshicrea" / "joshicrea-secretary"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# --- GitHubから最新コミット情報を取得 ---
API_URL = "https://api.github.com/repos/joshicrea/joshicrea-secretary/commits/master"
try:
    req = urllib.request.Request(API_URL, headers={"User-Agent": "joshicrea-install"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        commit_info = json.loads(resp.read().decode("utf-8"))
    full_sha  = commit_info["sha"]
    short_sha = full_sha[:12]
except Exception as e:
    print(f"GitHubへの接続に失敗しました: {e}")
    print("インターネット接続を確認してください。")
    sys.exit(1)

INSTALL_PATH = CACHE_DIR / short_sha

# すでにインストール済みの場合はスキップ
if INSTALL_PATH.exists():
    print(f"すでに最新版がインストールされています ({short_sha})")
else:
    ZIP_URL = "https://github.com/joshicrea/joshicrea-secretary/archive/refs/heads/master.zip"
    tmp_dir = pathlib.Path(tempfile.mkdtemp())
    zip_path = tmp_dir / "joshicrea-secretary.zip"

    try:
        print("ダウンロード中...")
        urllib.request.urlretrieve(ZIP_URL, zip_path)
    except Exception as e:
        print(f"ダウンロードに失敗しました: {e}")
        sys.exit(1)

    ext_dir = tmp_dir / "extract"
    ext_dir.mkdir()
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(ext_dir)

    # GitHubのZIPは "{repo}-master" フォルダに展開される
    extracted = next(ext_dir.iterdir())
    shutil.move(str(extracted), str(INSTALL_PATH))
    shutil.rmtree(tmp_dir, ignore_errors=True)

    print(f"ダウンロード完了 ({short_sha})")

# --- installed_plugins.json を更新 ---
INSTALLED_JSON = PLUGINS_DIR / "installed_plugins.json"
KEY = "joshicrea-secretary@joshicrea"
now_iso = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

PLUGINS_DIR.mkdir(parents=True, exist_ok=True)
if INSTALLED_JSON.exists():
    with open(INSTALLED_JSON, encoding="utf-8") as f:
        installed = json.load(f)
else:
    installed = {"version": 2, "plugins": {}}

installed.setdefault("plugins", {})[KEY] = [{
    "scope":        "user",
    "installPath":  str(INSTALL_PATH),
    "version":      short_sha,
    "installedAt":  now_iso,
    "lastUpdated":  now_iso,
    "gitCommitSha": full_sha,
}]

with open(INSTALLED_JSON, "w", encoding="utf-8") as f:
    json.dump(installed, f, ensure_ascii=False, indent=2)

# --- settings.json に enabledPlugins を追加 ---
SETTINGS_JSON = CLAUDE_DIR / "settings.json"
if SETTINGS_JSON.exists():
    with open(SETTINGS_JSON, encoding="utf-8") as f:
        settings = json.load(f)
else:
    settings = {}

settings.setdefault("enabledPlugins", {})[KEY] = True

with open(SETTINGS_JSON, "w", encoding="utf-8") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)

# --- rules/*.md をユーザーグローバルルールとして配置 ---
RULES_DIR      = CLAUDE_DIR / "rules"
SECRETARY_BASE = CLAUDE_DIR / "secretary"
RULES_DIR.mkdir(parents=True, exist_ok=True)

# --- 既存ユーザー向けマイグレーション（旧英語名 → 新日本語名）---
def _migrate(old_path: pathlib.Path, new_path: pathlib.Path):
    if old_path.exists() and not new_path.exists():
        old_path.rename(new_path)
    elif old_path.exists() and new_path.exists():
        # 両方ある場合は旧を削除（新が正）
        if old_path.is_file():
            old_path.unlink()
        else:
            shutil.rmtree(old_path, ignore_errors=True)

# rules ファイルの移行
_migrate(RULES_DIR / "secretary.md", RULES_DIR / "秘書.md")
_migrate(RULES_DIR / "work-tools.md", RULES_DIR / "使用ツール.md")
# secretary 配下のデータ移行
if SECRETARY_BASE.exists():
    _migrate(SECRETARY_BASE / "user-profile.md", SECRETARY_BASE / "ユーザープロフィール.md")
    _migrate(SECRETARY_BASE / "work-tools.md", SECRETARY_BASE / "使用ツール.md")
    _migrate(SECRETARY_BASE / "resources", SECRETARY_BASE / "素材")
# 旧英語名スキルの削除（新スキルはキャッシュから供給される）
USER_SKILLS_DIR = CLAUDE_DIR / "skills"
OLD_SKILL_NAMES = ["secretary","document","expense","goal","habit","memo","monthly-summary","payment","schedule","skill-creator","task"]
if USER_SKILLS_DIR.exists():
    for name in OLD_SKILL_NAMES:
        old_skill = USER_SKILLS_DIR / name
        if old_skill.exists():
            shutil.rmtree(old_skill, ignore_errors=True)

SOURCE_RULES_DIR = INSTALL_PATH / ".claude" / "rules"
for rules_file in SOURCE_RULES_DIR.glob("*.md"):
    content = rules_file.read_text(encoding="utf-8")
    content = content.replace("{{SECRETARY_BASE_DIR}}", str(SECRETARY_BASE))
    (RULES_DIR / rules_file.name).write_text(content, encoding="utf-8")

# --- SKILL.md の{{SECRETARY_BASE_DIR}}をプラグインキャッシュ内で置換 ---
SOURCE_SKILLS_DIR = INSTALL_PATH / ".claude" / "skills"
for skill_md in SOURCE_SKILLS_DIR.rglob("SKILL.md"):
    content = skill_md.read_text(encoding="utf-8")
    replaced = content.replace("{{SECRETARY_BASE_DIR}}", str(SECRETARY_BASE))
    if replaced != content:
        skill_md.write_text(replaced, encoding="utf-8")

print("ルールファイルとスキルを設定しました")

# --- データディレクトリを作成 ---
for sub in ["memory/学習ログ", "memory/タスク", "素材"]:
    (SECRETARY_BASE / sub).mkdir(parents=True, exist_ok=True)

# テンプレートをコピー（初回のみ・既存データを上書きしない）
# 旧パス（templates/）と新パス（テンプレート/）の両方を試行する
TEMPLATES_DIR = INSTALL_PATH / "テンプレート"
if not TEMPLATES_DIR.exists():
    TEMPLATES_DIR = INSTALL_PATH / "templates"

_TEMPLATE_NAME_MAP = {
    "user-profile.md": "ユーザープロフィール.md",
    "work-tools.md": "使用ツール.md",
}
if TEMPLATES_DIR.exists():
    for tmpl in TEMPLATES_DIR.iterdir():
        if tmpl.is_file():
            dest_name = _TEMPLATE_NAME_MAP.get(tmpl.name, tmpl.name)
            dest = SECRETARY_BASE / dest_name
            if not dest.exists():
                shutil.copy(str(tmpl), str(dest))

print("データフォルダを準備しました")

# --- インストール後の検証 ---
verify_ok   = True
sec_md_path = RULES_DIR / "秘書.md"
profile_path = SECRETARY_BASE / "ユーザープロフィール.md"

for f in [sec_md_path, profile_path]:
    if not f.exists():
        print(f"エラー: {f} が作成されませんでした")
        verify_ok = False

if sec_md_path.exists():
    if "{{SECRETARY_BASE_DIR}}" in sec_md_path.read_text(encoding="utf-8"):
        print("エラー: 秘書.mdのパス置換が不完全です")
        verify_ok = False

if not verify_ok:
    print()
    print("インストールに問題が発生しました。もう一度試してください。")
    sys.exit(1)

# --- 完了 ---
print()
print("インストール完了！")
print()
print("次の手順:")
print("  1. Claude Code を完全に閉じる")
print("  2. Claude Code を再度開く")
print("  3. チャットに「はじめまして」と送るとセットアップが始まります")
print()
