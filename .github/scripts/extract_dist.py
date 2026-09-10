#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""dist.tar を EXTRACT_DEST 環境変数の指すディレクトリへ展開する（CI用）。

なぜ環境変数経由か（2026-09-10 実測）:
  展開先パスを python -c "...extractall('$DEST')" のように
  シェル文字列へ直接埋め込むと、Windows のバックスラッシュパス（RUNNER_TEMP 由来）に
  含まれる \a が Python の文字列リテラル内でエスケープシーケンスとして解釈され、
  BEL(0x07)混入でパスが壊れる（同日に別の3箇所で踏んだのと同型のバグ）。
  argv・環境変数はエスケープ処理を受けないため、これを避けられる。

使い方: EXTRACT_DEST=<展開先> python extract_dist.py [<tarファイル。既定 dist.tar>]
"""
import os
import sys
import tarfile


def main() -> int:
    dest = os.environ.get("EXTRACT_DEST")
    if not dest:
        print("EXTRACT_DEST が設定されていません")
        return 1
    src = sys.argv[1] if len(sys.argv) > 1 else "dist.tar"
    os.makedirs(dest, exist_ok=True)
    with tarfile.open(src) as tf:
        tf.extractall(dest, filter="data")
    print("展開完了: {} -> {}".format(src, dest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
