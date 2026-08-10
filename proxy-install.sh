#!/bin/sh
# GriefGuard ProxyBridge one-line bootstrap.
#
# This file is intentionally dependency-light so a rental VPS can install the
# connector without first copying Mobile-Manager-Agent or installing Node.js.
# Upload this file to the GitHub repository root as proxy-install.sh, then run:
#   tmp=$(mktemp "${TMPDIR:-/tmp}/griefguard-proxy.XXXXXX") && trap 'rm -f "$tmp"' EXIT && curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Minato-256/GriefGuard/main/proxy-install.sh -o "$tmp" && sh "$tmp"
set -eu

REPOSITORY="${GRIEFGUARD_GITHUB_REPO:-Minato-256/GriefGuard}"
RELEASE_BASE="https://github.com/${REPOSITORY}/releases/latest/download"
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/main"
PLATFORM=""
TARGET="${GRIEFGUARD_PROXY_ROOT:-}"
AGENT_URL="${GRIEFGUARD_AGENT_URL:-}"
SETUP_CODE="${GRIEFGUARD_PROXY_SETUP_CODE:-}"
AGENT_HOST="${GRIEFGUARD_AGENT_HOST:-}"
AGENT_PORT="${GRIEFGUARD_AGENT_PORT:-25502}"
PROXY_ID="${GRIEFGUARD_PROXY_ID:-}"
TOKEN="${GRIEFGUARD_PROXY_TOKEN:-}"
OFFLINE=0

usage() {
  cat <<'EOF'
GriefGuard ProxyBridge GitHub セットアップ

GitHubから最新のProxyBridgeを取得し、現在のProxyへ自動配置します。

Proxyルートは、Proxy本体のJAR・設定ファイル・plugins/またはextensions/が
同じ階層にあるフォルダーです。/root、/home、/optなどの親フォルダーは指定しません。

引数（省略すると画面で質問します）:
  --platform velocity|bungee|geyser
  --target <Proxyルート>
  --agent-url <Agent HTTPS URL>
  --setup-code <アプリ発行の一時コード>
  --agent-host <AgentのTailscale IPまたはDNS>
  --agent-port <Agent待受ポート（既定25502）>
  --proxy-id <アプリ発行Proxy ID>
  --token <アプリ発行Token>
  --offline                          GitHubへ接続せず、スクリプトと同じフォルダーのJARを使用
  --help

種類の目印:
  Velocity: velocity.toml または Velocity*.jar / plugins/
  BungeeCord・Waterfall: config.yml・bungee.yml または BungeeCord/Waterfall*.jar / plugins/
  Geyser: extensions/ または Geyser*.jar / extensions/

1行実行例:
  tmp=$(mktemp "${TMPDIR:-/tmp}/griefguard-proxy.XXXXXX") && trap 'rm -f "$tmp"' EXIT && curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Minato-256/GriefGuard/main/proxy-install.sh -o "$tmp" && sh "$tmp"
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --agent-url) AGENT_URL="${2:-}"; shift 2 ;;
    --setup-code) SETUP_CODE="${2:-}"; shift 2 ;;
    --agent-host) AGENT_HOST="${2:-}"; shift 2 ;;
    --agent-port) AGENT_PORT="${2:-}"; shift 2 ;;
    --proxy-id) PROXY_ID="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[ERROR] 不明な引数です: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ask() {
  prompt="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r answer || answer=""
  if [ -n "$answer" ]; then printf '%s' "$answer"; else printf '%s' "$default"; fi
}

valid_dir() { [ -n "$1" ] && [ -d "$1" ]; }

detect_platform() {
  root="$1"
  if [ -f "$root/velocity.toml" ]; then printf '%s' velocity; return; fi
  if [ -f "$root/bungee.yml" ]; then printf '%s' bungee; return; fi
  if [ -d "$root/extensions" ] && [ ! -f "$root/bungee.yml" ]; then printf '%s' geyser; return; fi
  if [ -d "$root/plugins" ]; then
    for jar in "$root"/*.jar; do
      name=$(basename "$jar" 2>/dev/null || true)
      case "$name" in
        velocity*.jar|Velocity*.jar) printf '%s' velocity; return ;;
        waterfall*.jar|Waterfall*.jar|bungeecord*.jar|BungeeCord*.jar|bungee*.jar|Bungee*.jar) printf '%s' bungee; return ;;
      esac
    done
  fi
  printf '%s' ""
}

platform_label() {
  case "$1" in
    velocity) printf '%s' 'Velocity（Java版プロキシ）' ;;
    bungee) printf '%s' 'BungeeCord / Waterfall（Java版プロキシ）' ;;
    geyser) printf '%s' 'Geyser（統合版接続用）' ;;
    *) printf '%s' '不明なプロキシ' ;;
  esac
}

platform_guide() {
  cat >&2 <<'EOF'

Proxyルートフォルダーの選び方:
  1. Proxy本体のJAR、設定ファイル、plugins/またはextensions/が同じ階層にある場所を選びます。
  2. plugins/やextensions/だけを選ばず、その一つ上のフォルダーを選びます。
  3. /root、/home、/opt、/srvなどの親フォルダーは選びません。

種類と必要な目印:
  1: Velocity（Java版プロキシ）      velocity.toml または Velocity*.jar / plugins/
  2: BungeeCord・Waterfall（Java版） config.yml・bungee.yml または BungeeCord/Waterfall*.jar / plugins/
  3: Geyser（統合版接続用）           extensions/ または Geyser*.jar / extensions/

例: /home/minecraft/velocity、/home/minecraft/waterfall、/home/minecraft/geyser
EOF
}

has_proxy_jar() {
  root="$1"
  kind="$2"
  for jar in "$root"/*.jar; do
    [ -f "$jar" ] || continue
    name=$(basename "$jar")
    case "$kind:$name" in
      velocity:velocity*.jar|velocity:Velocity*.jar) return 0 ;;
      bungee:waterfall*.jar|bungee:Waterfall*.jar|bungee:bungeecord*.jar|bungee:BungeeCord*.jar|bungee:bungee*.jar|bungee:Bungee*.jar) return 0 ;;
      geyser:geyser*.jar|geyser:Geyser*.jar) return 0 ;;
    esac
  done
  return 1
}

is_broad_root() {
  case "$1" in
    /|/root|/home|/opt|/srv|/usr|/var|/tmp) return 0 ;;
  esac
  return 1
}

validate_proxy_root() {
  root="$1"
  kind="$2"
  label=$(platform_label "$kind")
  case "$kind" in
    velocity) base_ok=0; [ -f "$root/velocity.toml" ] || has_proxy_jar "$root" velocity || base_ok=1; install_dir="$root/plugins" ;;
    bungee) base_ok=0; [ -f "$root/config.yml" ] || [ -f "$root/bungee.yml" ] || has_proxy_jar "$root" bungee || base_ok=1; install_dir="$root/plugins" ;;
    geyser) base_ok=0; [ -d "$root/extensions" ] || has_proxy_jar "$root" geyser || base_ok=1; install_dir="$root/extensions" ;;
    *) echo '[ERROR] プロキシ種類が不正です。' >&2; return 1 ;;
  esac
  echo >&2
  echo "[確認] 選択したProxyルート: $root" >&2
  echo "  種類: $label" >&2
  echo "  配置先: $install_dir" >&2
  if [ "$base_ok" -eq 0 ]; then echo '  ✓ Proxy本体・設定ファイル: 確認できました' >&2; else echo '  ✗ Proxy本体・設定ファイル: 見つかりません' >&2; fi
  if [ -d "$install_dir" ]; then echo "  ✓ $(basename "$install_dir")/: 確認できました" >&2; else echo "  △ $(basename "$install_dir")/: 無いためインストーラーが作成します" >&2; fi
  contents=''
  for entry in "$root"/*; do
    [ -e "$entry" ] || continue
    contents="$contents\n    $(basename "$entry")"
  done
  if [ -n "$contents" ]; then printf '  フォルダー内の主な項目:%b\n' "$contents" >&2; fi
  if [ "$base_ok" -ne 0 ]; then
    if is_broad_root "$root"; then
      echo "[ERROR] $root は親フォルダーです。${label}のファイルが直接入る一つ下のフォルダーを選択してください。" >&2
    else
      echo "[ERROR] $root は${label}のルートとして確認できません。必要なファイルを確認してください。" >&2
    fi
    return 1
  fi
  return 0
}

discover_roots() {
  for candidate in "$(pwd)" "${GRIEFGUARD_PROXY_ROOT:-}"; do
    [ -n "$candidate" ] || continue
    detected=$(detect_platform "$candidate")
    if [ -n "$detected" ] && ! is_broad_root "$candidate"; then printf '%s\t%s\n' "$candidate" "$detected"; fi
  done
  for base in "$HOME" /home /opt /srv; do
    [ -d "$base" ] || continue
    while IFS= read -r candidate; do
      detected=$(detect_platform "$candidate")
      if [ -n "$detected" ] && ! is_broad_root "$candidate"; then printf '%s\t%s\n' "$candidate" "$detected"; fi
    done <<EOF
$(find "$base" -maxdepth 4 \( -type f \( -name velocity.toml -o -name bungee.yml -iname 'velocity*.jar' -o -iname 'waterfall*.jar' -o -iname 'bungeecord*.jar' -o -iname 'Geyser*.jar' \) -o -type d -name extensions \) -print 2>/dev/null | sed 's#/[^/]*$##' | head -20)
EOF
  done
  return 0
}

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo '[ERROR] curlまたはwgetが必要です。Ubuntuなら sudo apt-get install curl を実行してください。' >&2
  exit 11
fi

if [ -z "$TARGET" ]; then
  discovered=$(discover_roots | awk 'NF && !seen[$0]++' || true)
  candidate_count=$(printf '%s\n' "$discovered" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
  if [ "$candidate_count" -eq 1 ]; then
    TARGET=$(printf '%s\n' "$discovered" | awk -F '\t' 'NR==1{print $1}')
    PLATFORM=$(printf '%s\n' "$discovered" | awk -F '\t' 'NR==1{print $2}')
    echo "[AUTO] Proxy種類を検出しました: $(platform_label "$PLATFORM")"
    echo "[AUTO] Proxyルートを検出しました: $TARGET"
  elif [ "$candidate_count" -gt 1 ]; then
    echo '[INFO] 複数のProxy候補を検出しました。使用する番号を選択してください。' >&2
    index=1
    printf '%s\n' "$discovered" | while IFS='\t' read -r candidate candidate_platform; do
      [ -n "$candidate" ] || continue
      echo "  $index. $(platform_label "$candidate_platform"): $candidate" >&2
      index=$((index + 1))
    done
    choice=$(ask '使用する番号' '')
    selected=$(printf '%s\n' "$discovered" | sed -n "${choice}p")
    TARGET=$(printf '%s' "$selected" | awk -F '\t' '{print $1}')
    PLATFORM=$(printf '%s' "$selected" | awk -F '\t' '{print $2}')
    [ -n "$TARGET" ] || { echo '[ERROR] 候補番号が不正です。' >&2; exit 12; }
  else
    platform_guide
    TARGET=$(ask 'Proxyルートフォルダー（例: /home/minecraft/velocity）' '')
  fi
fi
if ! valid_dir "$TARGET"; then
  echo "[ERROR] Proxyルートフォルダーが見つかりません: $TARGET" >&2
  exit 12
fi
TARGET=$(CDPATH= cd -- "$TARGET" && pwd)

if [ -z "$PLATFORM" ]; then PLATFORM=$(detect_platform "$TARGET"); fi
if [ "$PLATFORM" = waterfall ]; then PLATFORM=bungee; fi
case "$PLATFORM" in
  velocity|bungee|geyser) ;;
  *)
    platform_guide
    PLATFORM=$(ask '種類の番号 (1: Velocity / 2: BungeeCord・Waterfall / 3: Geyser)' '')
    case "$PLATFORM" in 1) PLATFORM=velocity ;; 2) PLATFORM=bungee ;; 3) PLATFORM=geyser ;; *) echo '[ERROR] 種類は1、2、3のいずれかです。' >&2; exit 13 ;; esac
    ;;
esac

validate_proxy_root "$TARGET" "$PLATFORM" || exit 12
echo "[OK] $(platform_label "$PLATFORM")として認識しました。" >&2

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
json_field() {
  value=$(printf '%s' "$2" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -1)
  if [ -z "$value" ]; then value=$(printf '%s' "$2" | sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p" | head -1); fi
  printf '%s' "$value"
}

if [ -n "$SETUP_CODE" ]; then
  [ -n "$AGENT_URL" ] || { echo '[ERROR] Agent HTTPS URLがありません。アプリで導入コマンドを再発行してください。' >&2; exit 14; }
  case "$AGENT_URL" in http://*|https://*) ;; *) echo '[ERROR] Agent HTTPS URLの形式が不正です。' >&2; exit 14 ;; esac
  display_name=$(basename "$TARGET")
  payload=$(printf '{"code":"%s","platform":"%s","displayName":"%s"}' "$(json_escape "$SETUP_CODE")" "$(json_escape "$PLATFORM")" "$(json_escape "$display_name")")
  exchange=$(curl -fsSL --connect-timeout 15 --max-time 30 -H 'Content-Type: application/json' -d "$payload" "${AGENT_URL%/}/api/proxy/setup/exchange" 2>/dev/null || true)
  PROXY_ID=$(json_field proxyId "$exchange")
  TOKEN=$(json_field token "$exchange")
  AGENT_HOST=$(json_field agentHost "$exchange")
  AGENT_PORT=$(json_field agentPort "$exchange")
  AGENT_PORT=${AGENT_PORT:-25502}
  if [ -z "$PROXY_ID" ] || [ -z "$TOKEN" ] || [ -z "$AGENT_HOST" ]; then
    error=$(json_field error "$exchange")
    echo "[ERROR] Agentへの自動登録に失敗しました: ${error:-接続できませんでした。Tailscale HTTPSとコードの期限を確認してください。}" >&2
    exit 16
  fi
  echo "[OK] AgentへのProxy登録を完了しました: $PROXY_ID"
else
  AGENT_HOST=${AGENT_HOST:-$(ask 'Agentの待受アドレス（Agent PCのTailscale IP）' 127.0.0.1)}
  AGENT_PORT=${AGENT_PORT:-$(ask 'Agent ProxyBridgeポート' 25502)}
  PROXY_ID=${PROXY_ID:-$(ask 'アプリで発行したProxy ID')}
  TOKEN=${TOKEN:-$(ask 'アプリで発行したToken')}
fi

case "$AGENT_HOST" in *[!A-Za-z0-9.:%_-]*|'') echo '[ERROR] Agentアドレスが不正です。' >&2; exit 14 ;; esac
case "$AGENT_PORT" in *[!0-9]*|'') echo '[ERROR] Agentポートが不正です。' >&2; exit 15 ;; esac
if [ "$AGENT_PORT" -lt 1 ] || [ "$AGENT_PORT" -gt 65535 ]; then echo '[ERROR] Agentポートは1〜65535です。' >&2; exit 15; fi
case "$PROXY_ID" in proxy-[A-Za-z0-9_-]*) ;; *) echo '[ERROR] Proxy IDが不正です。アプリで再発行してください。' >&2; exit 16 ;; esac
if [ "${#TOKEN}" -lt 24 ]; then echo '[ERROR] Tokenが短すぎます。アプリでProxy登録情報を再発行してください。' >&2; exit 17; fi

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t griefguard-proxy)
trap 'rm -rf "$tmp"' EXIT INT TERM
jar="$tmp/GriefGuard-ProxyBridge.jar"
sums="$tmp/SHA256SUMS"
download() {
  url="$1"; output="$2"
  if command -v curl >/dev/null 2>&1; then curl -fL --retry 2 --connect-timeout 15 "$url" -o "$output"; else wget -q --tries=2 -O "$output" "$url"; fi
}
if [ "$OFFLINE" -eq 1 ]; then
  echo '[RUN] 同梱ProxyBridgeを確認しています。'
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  if [ ! -f "$script_dir/GriefGuard-ProxyBridge.jar" ] || [ ! -f "$script_dir/SHA256SUMS" ]; then
    echo '[ERROR] --offlineにはproxy-install.sh、GriefGuard-ProxyBridge.jar、SHA256SUMSを同じフォルダーへ置いてください。' >&2
    exit 18
  fi
  cp "$script_dir/GriefGuard-ProxyBridge.jar" "$jar"
  cp "$script_dir/SHA256SUMS" "$sums"
  echo '[OK] 同じフォルダーのProxyBridgeを使用します（オフライン）。'
elif ! download "$RELEASE_BASE/GriefGuard-ProxyBridge.jar" "$jar" 2>/dev/null || ! download "$RELEASE_BASE/SHA256SUMS" "$sums" 2>/dev/null; then
  echo "[RUN] GitHubからProxyBridgeを取得しています: $REPOSITORY"
  echo '[INFO] Releasesに見つからないため、リポジトリ直下のファイルを使用します。'
  download "$RAW_BASE/GriefGuard-ProxyBridge.jar" "$jar"
  download "$RAW_BASE/SHA256SUMS" "$sums"
else
  echo "[RUN] GitHubからProxyBridgeを取得しています: $REPOSITORY"
fi
expected=$(awk '$NF == "GriefGuard-ProxyBridge.jar" || $NF == "*GriefGuard-ProxyBridge.jar" { print $1; exit }' "$sums")
case "$expected" in [A-Fa-f0-9][A-Fa-f0-9]*) ;; *) echo '[ERROR] SHA256SUMSにProxyBridgeのハッシュがありません。' >&2; exit 18 ;; esac
case "$(printf '%s' "$expected" | awk '{print length}')" in 64) ;; *) echo '[ERROR] SHA-256の形式が不正です。' >&2; exit 18 ;; esac
if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$jar" | awk '{print $1}'); elif command -v shasum >/dev/null 2>&1; then actual=$(shasum -a 256 "$jar" | awk '{print $1}'); else echo '[ERROR] sha256sumまたはshasumが必要です。' >&2; exit 19; fi
if [ "$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')" ]; then echo '[ERROR] ProxyBridgeのSHA-256検証に失敗しました。' >&2; exit 20; fi

if [ "$PLATFORM" = geyser ]; then install_dir="$TARGET/extensions"; data_dir="$install_dir/griefguardproxybridge"; else install_dir="$TARGET/plugins"; if [ "$PLATFORM" = velocity ]; then data_dir="$install_dir/griefguard-proxybridge"; else data_dir="$install_dir/GriefGuard-ProxyBridge"; fi; fi
mkdir -p "$install_dir" "$data_dir"
destination="$install_dir/GriefGuard-ProxyBridge.jar"
if [ -f "$destination" ]; then backup="$destination.backup-$(date -u +%Y%m%dT%H%M%SZ)"; cp "$destination" "$backup"; echo "[OK] 既存JARをバックアップしました: $backup"; fi
# Stage both artifacts and rename only after the complete copy. A cancelled
# SSH session must never leave a half-written JAR/config that prevents Proxy
# startup on the next restart.
staged_jar="$destination.$$.downloading"
cp "$jar" "$staged_jar"
chmod 600 "$staged_jar" 2>/dev/null || true
mv -f "$staged_jar" "$destination"
umask 077
config_file="$data_dir/proxy-config.json"
if [ -f "$config_file" ]; then config_backup="$config_file.backup-$(date -u +%Y%m%dT%H%M%SZ)"; cp "$config_file" "$config_backup"; echo "[OK] 既存設定をバックアップしました: $config_backup"; fi
staged_config="$config_file.$$.saving"
cat > "$staged_config" <<EOF
{
  "agentHost": "$(json_escape "$AGENT_HOST")",
  "agentPort": $AGENT_PORT,
  "proxyId": "$(json_escape "$PROXY_ID")",
  "token": "$(json_escape "$TOKEN")",
  "platform": "$PLATFORM",
  "edition": "standard",
  "enabled": true,
  "failClosed": false,
  "cacheMaxAgeSeconds": 86400,
  "autoUpdate": true,
  "autoApplyOnRestart": true
}
EOF
chmod 600 "$staged_config" 2>/dev/null || true
mv -f "$staged_config" "$config_file"
echo "[OK] ${PLATFORM}へProxyBridgeを配置しました: $destination"
echo "[OK] 設定を保存しました: $config_file"
echo '[NEXT] Proxyを再起動してください。アプリの「設定 → プロキシ接続管理」でオンラインを確認します。'
