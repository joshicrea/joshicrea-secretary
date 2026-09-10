#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""配布物（git archive の tar）の改行コードを検証する。

なぜ要るか（2026-09-10）:
  hooks/run-hook.cmd は cmd.exe と Unix の bash の両方が読む polyglot。
  .gitattributes の `*.cmd text eol=crlf` により配布ZIPでは CRLF になり、
  macOS の bash は行末の CR を取り除かないため Unix 側の分岐が壊れる。
  Windows 上の Git Bash（MSYS2）は CR を自動で除去するので、
  開発機で bash を叩いても正常に見える。機械でしか捕まえられない。

  あわせて run-hook.cmd が ASCII のみであることも見る。cmd.exe はファイルを
  OEM コードページ（日本語環境では CP932）で読むため、UTF-8 の日本語を
  REM コメントに書くと化けて命令として解釈され EXIT=255 で落ちる（実測）。

使い方: python verify_line_endings.py <dist.tar>
終了コード: 0=OK / 1=NGあり

この検査が見ていない層:
  - ファイルの中身が正しいか（改行コードと文字集合だけを見る）
  - .ps1 の BOM 有無（別途 install スクリプト側で扱う）
"""
import sys
import tarfile

CR = bytes([13])  # 復帰文字。ソースに直接書くと壊れるため数値で書く

# パス -> 期待する状態
MUST_BE_LF = ["hooks/run-hook.cmd", "hooks/session-start", "hooks/session-log", "install.py"]
MUST_BE_ASCII = ["hooks/run-hook.cmd"]


# Windows CI runner はデフォルトで stdout を cp1252 等のレガシーコードページで開き、
# 日本語の print が UnicodeEncodeError になる（2026-09-10 実測）。UTF-8に固定する。
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

def main() -> int:
    if len(sys.argv) < 2:
        print("使い方: verify_line_endings.py <dist.tar>")
        return 1
    ng = []
    with tarfile.open(sys.argv[1], "r:") as tf:
        names = set(tf.getnames())
        for path in MUST_BE_LF:
            if path not in names:
                ng.append("配布物に含まれていない: " + path)
                continue
            data = tf.extractfile(path).read()
            if CR in data:
                ng.append("CR が含まれている（LF であるべき）: " + path)
            else:
                print("OK  LF のみ: " + path)
        for path in MUST_BE_ASCII:
            if path not in names:
                continue
            data = tf.extractfile(path).read()
            non_ascii = [b for b in data if b > 127]
            if non_ascii:
                ng.append("ASCII 以外の文字が含まれている（cmd.exe が CP932 で読むため化ける）: " + path)
            else:
                print("OK  ASCII のみ: " + path)
    if ng:
        for x in ng:
            print("NG: " + x)
        return 1
    print("全項目 OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
