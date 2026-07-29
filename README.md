# GriefGuard
Minecraft向けのサーバー管理用プラグインです。

## 最初に開くファイル

ZIPで受け取った場合は、必ず「すべて展開」してから次のファイルを開いてください。Minecraftサーバーが起動中なら、先にPaperコンソールで `stop` を実行します。

- まず読む: `README_FIRST.txt`
- Windows: `Installers/Windows/Start-GriefGuard-Setup.bat`
- macOS: `Installers/macOS/GriefGuard-Installer.pkg`
- 詳細手順: `GriefGuard_Manual_JA.pdf`

## インストーラー

- macOS: `Installers/macOS/GriefGuard-Installer.pkg` を実行後、
  `Installers/macOS/GriefGuard-Setup.command` を開きます。
  このPKGはテスト用の未署名版です。
- Windows: `Installers/Windows/Start-GriefGuard-Setup.bat` をダブルクリックします。
  右クリックのPowerShell項目は不要です。互換Node.jsが無い場合だけインストーラーが公式配布元から取得します。
- 詳細: `Installers/README.md`
- 既存Paperを選ぶ時: PDF第3・4章を開き、ファイル選択画面で`paper.jar`、`server.properties`、`plugins`、`world`が直接入る最上位フォルダーを選びます。`cd`やパスの手入力は不要です。

## 配布前チェック

次のものをこのフォルダへ追加しないでください。

- `world`、`world_nether`、`world_the_end`
- `Backups`
- `AgentData`
- `agent-config.json`
- `.agent-sessions.json`
- `.password-reset.json`
- Discord Botトークン、Tailscaleの認証情報、実在する管理パスワード

設定完了後は、インストーラーが作る`GriefGuard-HomeServer/Agent-Manual-Controls.txt`を開きます。通常はAgentは自動起動しますが、保守時には`Start-GriefGuard-Agent`、`Stop-GriefGuard-Agent`、`Restart-GriefGuard-Agent`を使えます。Paperはサーバーフォルダ内の`start.bat`または`start.command`で別に起動します。

BlueMapは標準で自動導入され、通常のPaper初回起動後に実スポーン周辺から描画を始めます。初回描画の状態はアプリのマップ左下で確認します。診断後も古い地形や誤ったテクスチャが続く場合だけ、Paper停止後に`Repair-BlueMap`を使用してください。
