#!/bin/sh
# GriefGuard ProxyBridge one-line bootstrap.
# This file is intentionally self-contained so it can be downloaded directly
# from the repository root without first copying Mobile-Manager-Agent.
set -eu

REPOSITORY="Minato-256/GriefGuard"
RELEASE_BASE="https://github.com/${REPOSITORY}/releases/latest/download"
RAW_BASE="https://raw.githubusercontent.com/${REPOSITORY}/main"
JAR_NAME="GriefGuard-ProxyBridge.jar"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/griefguard-proxy.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

PLATFORM=""
TARGET=""
AGENT_HOST=""
AGENT_PORT="25502"
PROXY_ID=""
TOKEN=""
OFFLINE=0
BRIDGE_FILE=""

usage() {
  cat <<'EOF'
GriefGuard ProxyBridge セットアップ

Proxyのルートフォルダーで実行すると、種類とフォルダーを自動判定します。
引数を省略した場合は対話形式で入力します。

  --platform velocity|bungee|waterfall|geyser
  --target <ProxyまたはGeyserのルート>
  --agent-host <AgentのTailscale IPまたはDNS名>
  --agent-port <ポート (既定: 25502)>
  --proxy-id <アプリで発行したProxy ID>
  --token <アプリで発行したToken>
  --offline                 同じフォルダーのJARを使用
  --bridge-file <JAR>      使用するJARを指定
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM=${2-}; shift 2 ;;
    --target) TARGET=${2-}; shift 2 ;;
    --agent-host) AGENT_HOST=${2-}; shift 2 ;;
    --agent-port) AGENT_PORT=${2-}; shift 2 ;;
    --proxy-id) PROXY_ID=${2-}; shift 2 ;;
    --token) TOKEN=${2-}; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    --bridge-file) BRIDGE_FILE=${2-}; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "[ERROR] 不明な引数です: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "[ERROR] $*" >&2; exit 1; }
is_dir() { [ -d "$1" ]; }

detect_platform() {
  root=$1
  if [ -f "$root/velocity.toml" ]; then echo velocity; return; fi
  if [ -f "$root/bungee.yml" ] || { [ -f "$root/config.yml" ] && [ -d "$root/plugins" ]; }; then echo bungee; return; fi
  if [ -d "$root/extensions" ]; then echo geyser; return; fi
  echo ""
}

if [ -z "$TARGET" ]; then
  detected=$(detect_platform "$PWD")
  if [ -n "$detected" ]; then TARGET=$PWD; PLATFORM=${PLATFORM:-$detected}; fi
fi

if [ -z "$TARGET" ]; then
  printf 'ProxyまたはGeyserのルートフォルダー: '
  IFS= read -r TARGET
fi
TARGET=${TARGET%/}
is_dir "$TARGET" || die "対象フォルダーが見つかりません: $TARGET"

if [ -z "$PLATFORM" ]; then
  PLATFORM=$(detect_platform "$TARGET")
fi
if [ "$PLATFORM" = waterfall ]; then PLATFORM=bungee; fi
if [ "$PLATFORM" != velocity ] && [ "$PLATFORM" != bungee ] && [ "$PLATFORM" != geyser ]; then
  echo "Proxy種類を選択してください。"
  echo "  1. Velocity"
  echo "  2. BungeeCord / Waterfall"
  echo "  3. Geyser Extension"
  printf '番号 [1]: '
  IFS= read -r answer
  case "${answer:-1}" in
    1) PLATFORM=velocity ;;
    2) PLATFORM=bungee ;;
    3) PLATFORM=geyser ;;
    *) die "Proxy種類の番号が不正です。" ;;
  esac
fi

if [ -z "$AGENT_HOST" ]; then printf 'Agentの待受アドレス（Agent PCのTailscale IP） [127.0.0.1]: '; IFS= read -r AGENT_HOST; AGENT_HOST=${AGENT_HOST:-127.0.0.1}; fi
case "$AGENT_HOST" in *[\"\'\ \	\r\n\;\&\|]*) die "Agentアドレスに使用できない文字があります。" ;; esac

if [ -z "$AGENT_PORT" ]; then AGENT_PORT=25502; fi
case "$AGENT_PORT" in *[!0-9]*|'') die "Agentポートが不正です。" ;; esac
[ "$AGENT_PORT" -ge 1 ] 2>/dev/null && [ "$AGENT_PORT" -le 65535 ] 2>/dev/null || die "Agentポートは1〜65535で指定してください。"

if [ -z "$PROXY_ID" ]; then printf 'Proxy ID: '; IFS= read -r PROXY_ID; fi
case "$PROXY_ID" in [A-Za-z0-9_-][A-Za-z0-9_-][A-Za-z0-9_-]*) ;; *) die "Proxy IDが不正です。" ;; esac
[ "${#PROXY_ID}" -le 80 ] || die "Proxy IDは80文字以内で指定してください。"

if [ -z "$TOKEN" ]; then printf 'ペアリングToken（入力は表示されません）: '; stty -echo 2>/dev/null || true; IFS= read -r TOKEN; stty echo 2>/dev/null || true; printf '\n'; fi
[ "${#TOKEN}" -ge 24 ] || die "Tokenは24文字以上で指定してください。"
case "$TOKEN" in *[\"\'\ \	\r\n\;\&\|]*) die "Tokenに使用できない文字があります。" ;; esac

if [ -n "$BRIDGE_FILE" ]; then
  BRIDGE="$BRIDGE_FILE"
elif [ "$OFFLINE" -eq 1 ] && [ -f "$SCRIPT_DIR/$JAR_NAME" ]; then
  BRIDGE="$SCRIPT_DIR/$JAR_NAME"
else
  command -v curl >/dev/null 2>&1 || die "curlが必要です。"
  echo "[INFO] GitHub ReleasesからProxyBridgeを取得しています…"
  BRIDGE="$TEMP_DIR/$JAR_NAME"
  if ! curl -fsSL --retry 2 "$RELEASE_BASE/$JAR_NAME" -o "$BRIDGE"; then
    echo "[INFO] Releaseアセットが見つからないため、リポジトリ直下から取得します。"
    curl -fsSL --retry 2 "$RAW_BASE/$JAR_NAME" -o "$BRIDGE" || die "ProxyBridgeの取得に失敗しました。"
  fi
  if ! curl -fsSL --retry 2 "$RELEASE_BASE/SHA256SUMS" -o "$TEMP_DIR/SHA256SUMS"; then
    curl -fsSL --retry 2 "$RAW_BASE/SHA256SUMS" -o "$TEMP_DIR/SHA256SUMS" || die "SHA256SUMSの取得に失敗しました。"
  fi
  expected=$(awk '$2 == "GriefGuard-ProxyBridge.jar" { print $1; exit }' "$TEMP_DIR/SHA256SUMS")
  [ "${#expected}" -eq 64 ] || die "JARのSHA-256が見つかりません。"
  if command -v sha256sum >/dev/null 2>&1; then actual=$(sha256sum "$BRIDGE" | awk '{print $1}'); else actual=$(shasum -a 256 "$BRIDGE" | awk '{print $1}'); fi
  [ "$actual" = "$expected" ] || die "ProxyBridgeのSHA-256検証に失敗しました。"
fi
[ -f "$BRIDGE" ] || die "ProxyBridge JARが見つかりません: $BRIDGE"

if [ "$PLATFORM" = geyser ]; then install_dir="$TARGET/extensions"; data_dir="$install_dir/griefguardproxybridge";
else install_dir="$TARGET/plugins"; if [ "$PLATFORM" = velocity ]; then data_dir="$install_dir/griefguard-proxybridge"; else data_dir="$install_dir/GriefGuard-ProxyBridge"; fi; fi
mkdir -p "$install_dir" "$data_dir"
destination="$install_dir/$JAR_NAME"
if [ -f "$destination" ]; then cp -p "$destination" "$destination.backup-$(date +%Y%m%d-%H%M%S)"; fi
cp "$BRIDGE" "$destination"
chmod 600 "$destination" 2>/dev/null || true

config="$data_dir/proxy-config.json"
temporary="$config.$$"
umask 077
cat > "$temporary" <<EOF
{
  "agentHost": "$AGENT_HOST",
  "agentPort": $AGENT_PORT,
  "proxyId": "$PROXY_ID",
  "token": "$TOKEN",
  "platform": "$PLATFORM",
  "enabled": true,
  "failClosed": false,
  "cacheMaxAgeSeconds": 86400
}
EOF
mv "$temporary" "$config"
chmod 600 "$config"
echo "[OK] ProxyBridgeを配置しました: $destination"
echo "[OK] 接続設定を保存しました: $config"
echo "[NEXT] Proxyを再起動し、アプリの「Proxy接続管理」でオンライン状態を確認してください。"
