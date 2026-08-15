# 開発者向けドキュメント

開発者向けの情報（ビルド・配布）をまとめる。ディレクトリ構成・コーディングルールは
[CLAUDE.md](CLAUDE.md) を参照。開発者向けツール一式（ビルドスクリプト等）は
[dev-tools/](dev-tools/) 配下にアプリ本体と分離して置いている
（設計: [dev-tools/docs/spec/distribution.md](dev-tools/docs/spec/distribution.md)）。

## exeのビルド

前提: 開発者PCに AutoHotkey v2（Ahk2Exeを含む）がインストール済みであること。

```
powershell -File dev-tools\src\build.ps1
```

`build\nagame-ahk-vX.Y.Z.exe`（`.gitignore` 対象・コミット不要）が生成される。バージョンは
`src\main.ahk` 先頭の `;@Ahk2Exe-SetVersion` ディレクティブから取得する。

Ahk2Exe.exe が標準の場所（`%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe`）に無い場合は、
環境変数 `AHK2EXE_PATH` で実際のパスを指定する。同様にAutoHotkey v2本体
（既定 `%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe`）が標準の場所に無い場合は
`AHK_V2_EXE_PATH` で指定する（v1/v2が共存する環境ではAhk2Exeの既定baseがv1になっていることがあり、
`build.ps1` は `/base` でv2本体を明示指定してビルドする。経緯は
[docs/adr/0001-ahk2exeビルドの環境依存対応.md](docs/adr/0001-ahk2exeビルドの環境依存対応.md)参照）。

## リリース時の手順

1. `src\config\Settings.ahk` の `Version` を更新する。
2. `src\main.ahk` 先頭の `;@Ahk2Exe-SetVersion` を同じ値に手動で更新する（自動同期はしていない）。
3. 上記コマンドでビルドし、`build\nagame-ahk-vX.Y.Z.exe` を生成する。
4. 生成したexeを社内ファイルサーバーの配布先フォルダに手動でコピーし、配置場所を案内する
   （GitHub Releasesは使わない）。

## 未整備・今後整理する点

- ファイルサーバー上の配置パス・命名規則、旧バージョンの扱いは未確定。
- 詳細な設計・未決定事項は [dev-tools/docs/spec/distribution.md](dev-tools/docs/spec/distribution.md) を参照。