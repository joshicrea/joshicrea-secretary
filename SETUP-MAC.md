# AI秘書 Macセットアップ手順書

この手順書はClaude Codeが読んで実行するための設定ガイドです。
実行内容：GitHubからMarkdownファイルを取得して `~/.claude/` に配置し、設定JSONを更新します。
外部プログラムの実行は不要です。

---

## Step 1: ホームディレクトリを確認する

以下のコマンドでホームディレクトリを確認し、以降の `{HOME}` に使用する。

```bash
echo $HOME
```

---

## Step 2: 必要なディレクトリを作成する

```bash
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/plugins/cache/joshicrea/joshicrea-secretary"
mkdir -p "$HOME/.claude/plugins"
mkdir -p "$HOME/.claude/secretary/memory/学習ログ"
mkdir -p "$HOME/.claude/secretary/memory/タスク"
mkdir -p "$HOME/.claude/secretary/resources"
```

---

## Step 3: 最新バージョンのSHAを取得する

```bash
curl -s "https://api.github.com/repos/joshicrea/joshicrea-secretary/commits/master" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['sha'][:12])"
```

出力された12文字（例: `a1b2c3d4e5f6`）を `{SHA}` として記録する。

---

## Step 4: プラグインファイルをダウンロードして展開する

```bash
curl -L "https://github.com/joshicrea/joshicrea-secretary/archive/refs/heads/master.zip" -o /tmp/joshi-secretary.zip
unzip -q /tmp/joshi-secretary.zip -d /tmp/joshi-extract
mv /tmp/joshi-extract/joshicrea-secretary-master "$HOME/.claude/plugins/cache/joshicrea/joshicrea-secretary/{SHA}"
rm -rf /tmp/joshi-extract /tmp/joshi-secretary.zip
```

`{SHA}` は Step 3 で取得した値に置き換える。

---

## Step 5: ルールファイルを配置する

`{{SECRETARY_BASE_DIR}}` を `{HOME}/.claude/secretary` に置換しながらコピーする。

```bash
python3 << 'EOF'
import pathlib
home = pathlib.Path.home()
install = home / ".claude/plugins/cache/joshicrea/joshicrea-secretary"
# 最新のSHAディレクトリを自動検出
sha_dir = sorted(install.iterdir())[-1]
rules_src = sha_dir / ".claude/rules"
rules_dst = home / ".claude/rules"
secretary_base = str(home / ".claude/secretary")
for f in rules_src.glob("*.md"):
    content = f.read_text(encoding="utf-8")
    content = content.replace("{{SECRETARY_BASE_DIR}}", secretary_base)
    (rules_dst / f.name).write_text(content, encoding="utf-8")
    print(f"配置: {f.name}")
print("ルールファイルの配置が完了しました")
EOF
```

---

## Step 6: スキルファイルのパスを置換する

```bash
python3 << 'EOF'
import pathlib
home = pathlib.Path.home()
install = home / ".claude/plugins/cache/joshicrea/joshicrea-secretary"
sha_dir = sorted(install.iterdir())[-1]
skills_dir = sha_dir / ".claude/skills"
secretary_base = str(home / ".claude/secretary")
count = 0
for skill_md in skills_dir.rglob("SKILL.md"):
    content = skill_md.read_text(encoding="utf-8")
    replaced = content.replace("{{SECRETARY_BASE_DIR}}", secretary_base)
    if replaced != content:
        skill_md.write_text(replaced, encoding="utf-8")
        count += 1
print(f"スキルファイルを {count} 件更新しました")
EOF
```

---

## Step 7: テンプレートファイルをコピーする

```bash
python3 << 'EOF'
import pathlib, shutil
home = pathlib.Path.home()
install = home / ".claude/plugins/cache/joshicrea/joshicrea-secretary"
sha_dir = sorted(install.iterdir())[-1]
templates_dir = sha_dir / "templates"
secretary_base = home / ".claude/secretary"
if templates_dir.exists():
    for tmpl in templates_dir.iterdir():
        if tmpl.is_file():
            dest = secretary_base / tmpl.name
            if not dest.exists():
                shutil.copy(str(tmpl), str(dest))
                print(f"コピー: {tmpl.name}")
print("テンプレートのコピーが完了しました")
EOF
```

---

## Step 8: installed_plugins.json を作成・更新する

```bash
python3 << 'EOF'
import pathlib, json, datetime
home = pathlib.Path.home()
install_base = home / ".claude/plugins/cache/joshicrea/joshicrea-secretary"
sha_dir = sorted(install_base.iterdir())[-1]
sha = sha_dir.name
plugins_dir = home / ".claude/plugins"
installed_path = plugins_dir / "installed_plugins.json"
key = "joshicrea-secretary@joshicrea"
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
entry = {
    "scope": "user",
    "installPath": str(sha_dir),
    "version": sha,
    "installedAt": now,
    "lastUpdated": now,
    "gitCommitSha": sha,
}
if installed_path.exists():
    data = json.loads(installed_path.read_text(encoding="utf-8"))
else:
    data = {"version": 2, "plugins": {}}
data.setdefault("plugins", {})[key] = [entry]
installed_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"installed_plugins.json を更新しました (version: {sha})")
EOF
```

---

## Step 9: settings.json に enabledPlugins を追加する

```bash
python3 << 'EOF'
import pathlib, json
home = pathlib.Path.home()
settings_path = home / ".claude/settings.json"
key = "joshicrea-secretary@joshicrea"
if settings_path.exists():
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
else:
    settings = {}
settings.setdefault("enabledPlugins", {})[key] = True
settings_path.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
print("settings.json を更新しました")
EOF
```

---

## Step 10: インストールを確認する

```bash
python3 << 'EOF'
import pathlib
home = pathlib.Path.home()
ok = True
checks = [
    home / ".claude/rules/secretary.md",
    home / ".claude/secretary/user-profile.md",
]
for f in checks:
    if f.exists():
        print(f"OK: {f.name}")
    else:
        print(f"NG: {f} が見つかりません")
        ok = False
if ok:
    sec = (home / ".claude/rules/secretary.md").read_text(encoding="utf-8")
    if "{{SECRETARY_BASE_DIR}}" in sec:
        print("NG: secretary.md のパス置換が不完全です")
    else:
        print("\nインストール完了！Claude Code を再起動してから「はじめまして」と送ってください。")
EOF
```
