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
CREATE_MODE="${GRIEFGUARD_PROXY_CREATE:-0}"
CREATE_PARENT="${GRIEFGUARD_PROXY_PARENT:-}"
CREATE_NAME="${GRIEFGUARD_PROXY_NAME:-}"
LISTEN_PORT="${GRIEFGUARD_PROXY_LISTEN_PORT:-25565}"
BACKEND_HOST="${GRIEFGUARD_PROXY_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${GRIEFGUARD_PROXY_BACKEND_PORT:-25566}"
PROXY_VERSION="${GRIEFGUARD_PROXY_VERSION:-}"
PROXY_BUILD="${GRIEFGUARD_PROXY_BUILD:-}"
PROXY_JAR_URL="${GRIEFGUARD_PROXY_JAR_URL:-}"
AGENT_URL="${GRIEFGUARD_AGENT_URL:-}"
SETUP_CODE="${GRIEFGUARD_PROXY_SETUP_CODE:-}"
AGENT_HOST="${GRIEFGUARD_AGENT_HOST:-}"
AGENT_PORT="${GRIEFGUARD_AGENT_PORT:-25502}"
PROXY_ID="${GRIEFGUARD_PROXY_ID:-}"
TOKEN="${GRIEFGUARD_PROXY_TOKEN:-}"
OFFLINE=0
NO_VERIFY=0
CONNECTION_TIMEOUT="${GRIEFGUARD_PROXY_CONNECTION_TIMEOUT:-60}"

usage() {
  cat <<'EOF'
GriefGuard ProxyBridge GitHub セットアップ

GitHubから最新のProxyBridgeを取得し、現在のProxyへ自動配置します。

Proxyルートは、Proxy本体のJAR・設定ファイル・plugins/またはextensions/が
同じ階層にあるフォルダーです。/root、/home、/optなどの親フォルダーは指定しません。
新規作成で親フォルダーを空欄にすると、Linuxでは /home/minecraft（権限不足時は ~/minecraft）を自動作成します。

引数（省略すると画面で質問します）:
  --platform velocity|bungee|geyser
  --target <Proxyルート>
  --create                         新しいProxyフォルダーを作成（Velocity/Waterfall）
  --parent <親フォルダー>           新規Proxyの作成先
  --name <フォルダー名>             新規Proxyフォルダー名
  --listen-port <1-65535>          Proxy待受ポート（既定25565）
  --backend-host <ホスト>          接続先Paper（既定127.0.0.1）
  --backend-port <1-65535>         接続先Paperポート（既定25566）
  --proxy-version <バージョン>      公式安定版（省略時は最新安定版）
  --proxy-build <ビルド番号>       公式ビルド（省略時は最新ビルド）
  --proxy-jar-url <URL>             テスト・ミラー用Proxy JAR
  --agent-url <Agent HTTPS URL>
  --setup-code <アプリ発行の一時コード>
  --agent-host <AgentのTailscale IPまたはDNS>
  --agent-port <Agent待受ポート（既定25502）>
  --proxy-id <アプリ発行Proxy ID>
  --token <アプリ発行Token>
  --offline                          GitHubへ接続せず、スクリプトと同じフォルダーのJARを使用
  --no-verify                        Proxyを起動せずAgent接続確認を省略（オフライン検証用）
  --connection-timeout <秒>          Agent接続確認の待機時間（既定60秒）
  GRIEFGUARD_PROXY_NO_AUTOSTART=1    自動起動登録を省略（既定は有効）
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
    --create|--new) CREATE_MODE=1; shift ;;
    --parent|--create-parent) CREATE_PARENT="${2:-}"; shift 2 ;;
    --name) CREATE_NAME="${2:-}"; shift 2 ;;
    --listen-port) LISTEN_PORT="${2:-}"; shift 2 ;;
    --backend-host) BACKEND_HOST="${2:-}"; shift 2 ;;
    --backend-port) BACKEND_PORT="${2:-}"; shift 2 ;;
    --proxy-version) PROXY_VERSION="${2:-}"; shift 2 ;;
    --proxy-build) PROXY_BUILD="${2:-}"; shift 2 ;;
    --proxy-jar-url) PROXY_JAR_URL="${2:-}"; shift 2 ;;
    --agent-url) AGENT_URL="${2:-}"; shift 2 ;;
    --setup-code) SETUP_CODE="${2:-}"; shift 2 ;;
    --agent-host) AGENT_HOST="${2:-}"; shift 2 ;;
    --agent-port) AGENT_PORT="${2:-}"; shift 2 ;;
    --proxy-id) PROXY_ID="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    --no-verify) NO_VERIFY=1; shift ;;
    --connection-timeout) CONNECTION_TIMEOUT="${2:-60}"; shift 2 ;;
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

preferred_parent() {
  case "$(uname -s 2>/dev/null || true)" in
    Darwin) printf '%s' "$HOME/Documents/GriefGuardServers" ;;
    *) printf '%s' '/home/minecraft' ;;
  esac
}

ensure_parent() {
  requested="$1"
  if [ -z "$requested" ]; then requested=$(preferred_parent); fi
  if [ ! -d "$requested" ]; then
    mkdir -p "$requested" 2>/dev/null || {
      fallback="$HOME/minecraft"
      mkdir -p "$fallback" 2>/dev/null || { echo "[ERROR] 親フォルダーを作成できません: $requested" >&2; return 1; }
      echo "[WARN] $requestedを作成できないため、$fallbackを使用します。" >&2
      requested="$fallback"
    }
  fi
  valid_dir "$requested" || { echo "[ERROR] 親フォルダーを確認できません: $requested" >&2; return 1; }
  CDPATH= cd -- "$requested" && pwd
}

is_legacy_root_file() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    griefguard-proxy-setup.json|readme-griefguard-proxy.txt|griefguard-proxy-autostart.json|griefguard-proxy.service|griefguard-proxybridge.jar|start-proxy.sh|start-proxy.command|start-proxy.bat|start-proxy-supervisor.sh|start-proxy-supervisor.command|start-proxy-supervisor.bat|stop-proxy-supervisor.command|stop-proxy-supervisor.bat|griefguard-proxy-supervisor.ps1|.griefguard-proxy-supervisor.pid|.griefguard-proxy-stop) return 0 ;;
  esac
  return 1
}

is_bridge_artifact() {
  printf '%s' "$1" | grep -qiE '^(GriefGuard-ProxyBridge(\.jar)?|griefguard[-_]?proxybridge|proxy-config\.json)(\..*)?$'
}

prepare_new_proxy_root() {
  root="$1"
  mkdir -p "$root" 2>/dev/null || { echo "[ERROR] 新規Proxy作成先を作成できません: $root" >&2; return 1; }
  unknown=''
  for entry in "$root"/* "$root"/.[!.]*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    if is_legacy_root_file "$name"; then rm -rf "$entry"; continue; fi
    case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
      plugins|extensions)
        for child in "$entry"/* "$entry"/.[!.]*; do
          [ -e "$child" ] || continue
          child_name=$(basename "$child")
          if [ -f "$child" ] && printf '%s' "$child_name" | grep -qiE '^GriefGuard-ProxyBridge(\.jar)?(\..*)?$'; then rm -f "$child"; else unknown="$unknown $name/$child_name"; fi
        done
        find "$entry" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q . || rmdir "$entry" 2>/dev/null || true
        ;;
      logs)
        log_unknown=0
        for log_entry in "$entry"/* "$entry"/.[!.]*; do
          [ -e "$log_entry" ] || continue
          [ "$(basename "$log_entry" | tr '[:upper:]' '[:lower:]')" = proxy-supervisor.log ] || log_unknown=1
        done
        if [ "$log_unknown" -eq 0 ]; then rm -rf "$entry"; else unknown="$unknown $name"; fi
        ;;
      *) unknown="$unknown $name" ;;
    esac
  done
  if [ -n "$unknown" ]; then
    echo "[ERROR] 新規Proxy作成先に未知のファイルが残っています。削除せず中止しました:$unknown" >&2
    return 1
  fi
  return 0
}

detect_platform() {
  root="$1"
  if [ -f "$root/velocity.toml" ]; then printf '%s' velocity; return; fi
  if [ -f "$root/bungee.yml" ]; then printf '%s' bungee; return; fi
  # A generic system directory often contains an "extensions" folder (for
  # example /opt/homebrew/include/X11).  It is not a Geyser root unless the
  # folder itself is named Geyser or it contains a Geyser artifact.
  if [ -d "$root/extensions" ] && [ ! -f "$root/bungee.yml" ]; then
    case "$(basename "$root")" in
      [Gg]eyser|[Gg]eyser-*) printf '%s' geyser; return ;;
    esac
    for jar in "$root"/*.jar "$root/extensions"/*.jar; do
      [ -f "$jar" ] || continue
      case "$(basename "$jar")" in
        geyser*.jar|Geyser*.jar) printf '%s' geyser; return ;;
      esac
    done
  fi
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
  3. /root、/home、/opt、/srvなどの親フォルダーは選びません。新規作成で親を空欄にすると /home/minecraft を作成します。

種類と必要な目印:
  1: Velocity（Java版プロキシ）      velocity.toml または Velocity*.jar / plugins/
  2: BungeeCord・Waterfall（Java版） config.yml・bungee.yml または BungeeCord/Waterfall*.jar / plugins/
  3: Geyser（統合版接続用）           extensions/ または Geyser*.jar / extensions/

例: /home/minecraft/velocity、/home/minecraft/waterfall、/home/minecraft/geyser
EOF
}

print_discovery_header() {
  echo '[RUN] Proxyルートフォルダーを自動検索しています…' >&2
  echo '      Proxy本体の設定ファイル・JAR・plugins/またはextensions/が同じ階層にある場所だけを調べます。' >&2
  echo '      /root、/home、/opt、/srvなどの親フォルダーは候補にしません。' >&2
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

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

proxy_service_label() {
  root="$1"
  digest=''
  if command -v sha1sum >/dev/null 2>&1; then
    digest=$(printf '%s' "$root" | sha1sum | cut -c1-12)
  elif command -v shasum >/dev/null 2>&1; then
    digest=$(printf '%s' "$root" | shasum -a 1 | cut -c1-12)
  fi
  [ -n "$digest" ] || digest=proxy
  printf 'griefguard-proxy-%s' "$digest"
}

download() {
  url="$1"; output="$2"
  if command -v curl >/dev/null 2>&1; then curl -fL --retry 2 --connect-timeout 15 "$url" -o "$output"; else wget -q --tries=2 -O "$output" "$url"; fi
}

proxy_required_java() {
  if [ "$1" = velocity ] && printf '%s' "$2" | grep -qE '^4(\.|$)'; then printf '25'; else printf '17'; fi
}

install_autostart() {
  root="$1"
  kind="$2"
  [ "$kind" = velocity ] || [ "$kind" = bungee ] || { echo '[INFO] Geyser構成はGeyser本体のサービスを使用するため、自動起動登録を省略します。' >&2; return 0; }
  # Running the installer is an explicit re-enable action. Do not inherit a
  # stale manual-stop marker from a previous installation.
  rm -f "$root/.griefguard-proxy-stop"
      label=$(proxy_service_label "$root")
  case "$(uname -s 2>/dev/null || true)" in
    Linux)
      if [ "$(id -u)" -eq 0 ] && [ -d /etc/systemd/system ]; then unit_dir=/etc/systemd/system; mode='systemd-system'; else unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; mode='systemd-user'; fi
      unit="$unit_dir/$label.service"
      mkdir -p "$unit_dir" 2>/dev/null || unit="$root/$label.service"
      cat > "$unit" <<EOF
[Unit]
Description=GriefGuard Proxy
After=network-online.target
[Service]
Type=simple
WorkingDirectory="$root"
ExecStart="$root/start-proxy-supervisor.sh"
Restart=on-failure
RestartSec=5
[Install]
WantedBy=default.target
EOF
      enabled=0
      [ -n "${mode:-}" ] || mode='file-only'
      if command -v systemctl >/dev/null 2>&1; then
        systemctl_args='--user'; [ "$mode" = systemd-system ] && systemctl_args=''
        systemctl $systemctl_args daemon-reload >/dev/null 2>&1 || true
        if systemctl $systemctl_args enable --now "$label.service" >/dev/null 2>&1; then enabled=1; fi
        if [ "$enabled" -eq 1 ] && [ "$mode" = systemd-user ] && command -v loginctl >/dev/null 2>&1; then loginctl enable-linger "${USER:-$(id -un)}" >/dev/null 2>&1 || true; fi
      fi
      if [ "$enabled" -eq 0 ] && command -v crontab >/dev/null 2>&1; then
        marker="# GriefGuard Proxy $label"
        (crontab -l 2>/dev/null | grep -vF "$marker" || true; printf '%s\n' "$marker"; printf '@reboot nohup "%s/start-proxy-supervisor.sh" >/dev/null 2>&1 &\n' "$root") | crontab - >/dev/null 2>&1 || true
        if crontab -l 2>/dev/null | grep -Fq "$marker"; then enabled=1; mode='cron-reboot'; fi
      fi
      nohup "$root/start-proxy-supervisor.sh" >/dev/null 2>&1 &
      printf '{"enabled":%s,"service":"%s","mode":"%s"}\n' "$enabled" "$label.service" "$mode" > "$root/griefguard-proxy-autostart.json"
      ;;
    Darwin)
      plist="$HOME/Library/LaunchAgents/$label.plist"
      mkdir -p "$(dirname "$plist")"
      cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>$label</string><key>ProgramArguments</key><array><string>$root/start-proxy-supervisor.sh</string></array><key>WorkingDirectory</key><string>$root</string><key>RunAtLoad</key><true/><key>KeepAlive</key><true/></dict></plist>
EOF
      uid=$(id -u)
      launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
      enabled=0
      if launchctl bootstrap "gui/$uid" "$plist" >/dev/null 2>&1; then
        enabled=1
        launchctl kickstart "gui/$uid/$label" >/dev/null 2>&1 || true
      fi
      printf '{"enabled":%s,"plist":"%s"}\n' "$enabled" "$(json_escape "$plist")" > "$root/griefguard-proxy-autostart.json"
      ;;
  esac
}

stop_known_autostart() {
  root="$1"
  label=$(proxy_service_label "$root")
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now "$label.service" >/dev/null 2>&1 || true
    systemctl disable --now "$label.service" >/dev/null 2>&1 || true
  fi
  rm -f "$root/$label.service" "$HOME/.config/systemd/user/$label.service" "/etc/systemd/system/$label.service" 2>/dev/null || true
  if command -v crontab >/dev/null 2>&1; then
    cron_tmp=$(mktemp 2>/dev/null || mktemp -t griefguard-cron)
    cron_current=$(crontab -l 2>/dev/null || true)
    if printf '%s\n' "$cron_current" | grep -Fq "# GriefGuard Proxy $label"; then
      printf '%s\n' "$cron_current" | awk -v marker="# GriefGuard Proxy $label" 'skip>0 {skip--; next} $0 == marker {skip=1; next} {print}' > "$cron_tmp"
      crontab "$cron_tmp" >/dev/null 2>&1 || true
    fi
    rm -f "$cron_tmp"
  fi
  pid_file="$root/.griefguard-proxy-supervisor.pid"
  if [ -f "$pid_file" ]; then
    pid=$(cat "$pid_file" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) ;; *) [ "$pid" -gt 1 ] && kill "$pid" 2>/dev/null || true ;; esac
  fi
}

read_managed_proxy_id() {
  root="$1"
  for config in "$root/plugins/griefguard-proxybridge/proxy-config.json" "$root/plugins/GriefGuard-ProxyBridge/proxy-config.json" "$root/extensions/griefguardproxybridge/proxy-config.json" "$root/proxy-config.json"; do
    [ -f "$config" ] || continue
    id=$(sed -n 's/.*"proxyId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)
    token=$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$config" | head -1)
    case "$id:$token" in proxy-[A-Za-z0-9_-]*:????????????????????????*) printf '%s' "$id"; return 0 ;; esac
  done
  return 1
}

is_managed_proxy_root() {
  root="$1"
  if read_managed_proxy_id "$root" >/dev/null 2>&1; then return 0; fi
  for marker in .griefguard-proxy-supervisor.pid .griefguard-proxy-stop start-proxy-supervisor.sh Start-Proxy-Supervisor.command Start-Proxy-Supervisor.bat GriefGuard-Proxy-Supervisor.ps1 griefguard-proxy-autostart.json griefguard-proxy-setup.json; do
    [ -e "$root/$marker" ] && return 0
  done
  for artifact in "$root/plugins/GriefGuard-ProxyBridge.jar" "$root/extensions/GriefGuard-ProxyBridge.jar"; do
    [ -f "$artifact" ] && return 0
  done
  return 1
}

stop_managed_processes() {
  root="$1"
  case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v powershell.exe >/dev/null 2>&1; then
        escaped=$(printf '%s' "$root" | sed "s/'/''/g")
        powershell.exe -NoLogo -NoProfile -Command "\$root='$escaped'; Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -and \$_.CommandLine.Contains(\$root) -and (\$_.CommandLine -match 'ProxySupervisorMain|start-proxy-supervisor|GriefGuard-Proxy-Supervisor|-jar.*(velocity|waterfall|bungeecord|bungee).*\\.jar') } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1 || true
      fi
      ;;
    *)
      if command -v ps >/dev/null 2>&1; then
        ps -axo pid=,command= 2>/dev/null | while IFS= read -r row; do
          pid=$(printf '%s' "$row" | awk '{print $1}')
          command=$(printf '%s' "$row" | sed 's/^[[:space:]]*[0-9][0-9]*[[:space:]]*//')
          case "$pid" in ''|*[!0-9]*) continue ;; esac
          [ "$pid" -gt 1 ] 2>/dev/null || continue
          case "$command" in *"$root"*) ;; *) continue ;; esac
          printf '%s' "$command" | grep -Eiq 'ProxySupervisorMain|start-proxy-supervisor|GriefGuard-Proxy-Supervisor|-jar.*(velocity|waterfall|bungeecord|bungee).*\.jar' || continue
          kill "$pid" 2>/dev/null || true
        done
      fi
      ;;
  esac
}

# Stop only GriefGuard's generated Supervisor/runtime registration. Proxy
# jars/configs, plugin data, reports and login information are preserved.
stop_managed_root_runtime() {
  root="$1"
  is_managed_proxy_root "$root" || return 0
  stop_known_autostart "$root"
  stop_managed_processes "$root"
  for file in start-proxy-supervisor.sh Start-Proxy-Supervisor.command Start-Proxy-Supervisor.bat Stop-Proxy-Supervisor.command Stop-Proxy-Supervisor.bat GriefGuard-Proxy-Supervisor.ps1 .griefguard-proxy-supervisor.pid .griefguard-proxy-stop griefguard-proxy-autostart.json; do
    rm -f "$root/$file" 2>/dev/null || true
  done
  echo "[OK] GriefGuardの旧Supervisorを停止しました（設定・ログイン情報・データは保持）: $root" >&2
}

# Duplicate roots additionally lose only the generated connector JAR. This
# prevents the old installation from reconnecting while preserving its
# credential/config/data files for audit or recovery.
deactivate_managed_root() {
  root="$1"
  stop_managed_root_runtime "$root" || return 0
  # The duplicate root is inactive now. Remove only files generated by this
  # installer; retain Proxy jars/configuration and proxy-config.json so login
  # and pairing data can be recovered later.
  for file in start-proxy.sh Start-Proxy.command Start-Proxy.bat griefguard-proxy-setup.json README-GriefGuard-Proxy.txt griefguard-proxy-install-result.json; do
    rm -f "$root/$file" 2>/dev/null || true
  done
  if [ -d "$root/logs" ]; then
    for log in "$root/logs"/proxy-supervisor.log "$root/logs"/proxy-supervisor.log.*; do
      [ -f "$log" ] || continue
      rm -f "$log" 2>/dev/null || true
    done
    find "$root/logs" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q . || rmdir "$root/logs" 2>/dev/null || true
  fi
  rm -f "$root/plugins/GriefGuard-ProxyBridge.jar" "$root/extensions/GriefGuard-ProxyBridge.jar" 2>/dev/null || true
  echo "[OK] 旧Proxyの重複Connectorを整理しました（設定・ログイン情報・データは保持）: $root" >&2
}

repair_duplicate_roots() {
  current_target="$1"
  proxy_id="$2"
  discovered=$(discover_roots | awk 'NF && !seen[$0]++' || true)
  tab=$(printf '\t')
  current_abs=$(CDPATH= cd -- "$current_target" 2>/dev/null && pwd || true)
  while IFS="$tab" read -r old_root old_platform; do
    [ -n "$old_root" ] || continue
    old_abs=$(CDPATH= cd -- "$old_root" 2>/dev/null && pwd || true)
    [ -n "$old_abs" ] && [ "$old_abs" != "$current_abs" ] || continue
    old_id=$(read_managed_proxy_id "$old_abs" 2>/dev/null || true)
    [ "$old_id" = "$proxy_id" ] || continue
    deactivate_managed_root "$old_abs"
  done <<EOF
$discovered
EOF
}

purge_known_proxy_roots() {
  current_target="$1"
  discovered=$(discover_roots | awk 'NF && !seen[$0]++' || true)
  tab=$(printf '\t')
  while IFS="$tab" read -r old_root old_platform; do
    [ -n "$old_root" ] || continue
    old_abs=$(CDPATH= cd -- "$old_root" 2>/dev/null && pwd || true)
    [ -n "$old_abs" ] || continue
    current_abs=$(CDPATH= cd -- "$current_target" 2>/dev/null && pwd || true)
    [ -n "$current_abs" ] && [ "$old_abs" = "$current_abs" ] && continue
    deactivate_managed_root "$old_abs"
  done <<EOF
$discovered
EOF
}

create_proxy_root() {
  kind="$1"
  [ "$kind" = velocity ] || [ "$kind" = bungee ] || { echo '[ERROR] 新規作成はVelocityまたはBungeeCord/Waterfallのみ対応しています。' >&2; return 1; }
  parent="${CREATE_PARENT:-}"
  [ -n "$parent" ] || parent=$(ask '新規Proxyの親フォルダー（Enterで自動作成）' "$(preferred_parent)")
  parent=$(ensure_parent "$parent") || return 1
  name="${CREATE_NAME:-GriefGuard-Proxy}"
  case "$name" in ''|.|..|*/*|*\\*) echo '[ERROR] 新規Proxyフォルダー名が不正です。' >&2; return 1 ;; esac
  if [ -n "$TARGET" ]; then root="$TARGET"; else root="$parent/$name"; fi
  prepare_new_proxy_root "$root" || return 1
  root=$(CDPATH= cd -- "$root" && pwd)
  service_label=$(proxy_service_label "$root")
  LISTEN_PORT="${LISTEN_PORT:-25565}"; BACKEND_PORT="${BACKEND_PORT:-25566}"; BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
  case "$LISTEN_PORT:$BACKEND_PORT" in *[!0-9:]*|*:|:*) echo '[ERROR] Proxy/Paperポートは数字で指定してください。' >&2; return 1 ;; esac
  [ "$LISTEN_PORT" -ge 1 ] && [ "$LISTEN_PORT" -le 65535 ] && [ "$BACKEND_PORT" -ge 1 ] && [ "$BACKEND_PORT" -le 65535 ] || { echo '[ERROR] ポートは1〜65535で指定してください。' >&2; return 1; }
  case "$BACKEND_HOST" in *[!A-Za-z0-9.%:_-]*) echo '[ERROR] Paper接続先ホストが不正です。' >&2; return 1 ;; esac
  command -v curl >/dev/null 2>&1 || { echo '[ERROR] 新規Proxy作成にはcurlが必要です。' >&2; return 1; }
  project="$kind"; [ "$project" = bungee ] && project=waterfall
  user_agent='GriefGuard-Installer/1.0 (https://github.com/Minato-256/GriefGuard)'
  if [ -n "$PROXY_JAR_URL" ]; then
    jar_url="$PROXY_JAR_URL"; version=custom; build=custom
    jar_name="$(basename "${PROXY_JAR_URL%%\?*}")"; [ "$jar_name" = . ] || [ "$jar_name" = / ] && jar_name="$kind.jar"
  else
    project_json=$(curl -fsSL -H "User-Agent: $user_agent" --connect-timeout 15 --max-time 30 "https://fill.papermc.io/v3/projects/$project") || { echo '[ERROR] 公式Proxyのバージョン一覧を取得できませんでした。' >&2; return 1; }
    version="${PROXY_VERSION:-$(printf '%s' "$project_json" | grep -oE '"[0-9]+(\.[0-9]+){1,3}"' | tr -d '"' | sort -V | tail -1)}"
    [ -n "$version" ] || { echo '[ERROR] 公式の安定版Proxyバージョンが見つかりません。' >&2; return 1; }
    case "$version" in *[!0-9.]*) echo '[ERROR] 安定版以外のProxyバージョンは指定できません。' >&2; return 1 ;; esac
    builds_json=$(curl -fsSL -H "User-Agent: $user_agent" --connect-timeout 15 --max-time 30 "https://fill.papermc.io/v3/projects/$project/versions/$version/builds") || { echo '[ERROR] Proxyビルド一覧を取得できませんでした。' >&2; return 1; }
    build="${PROXY_BUILD:-$(printf '%s' "$builds_json" | grep -oE '"id":[0-9]+[^}]*"channel":"(STABLE|RECOMMENDED)"' | grep -oE '"id":[0-9]+' | tail -1 | cut -d: -f2)}"
    server_default=$(printf '%s' "$builds_json" | grep -oE '"server:default":\{.*' | tail -1)
    jar_name=$(printf '%s' "$server_default" | grep -oE '"name":"[^"}]+\.jar"' | head -1 | sed 's/^"name":"//; s/"$//')
    [ -n "$build" ] && [ -n "$jar_name" ] || { echo '[ERROR] 公式Proxyビルド情報を解釈できませんでした。' >&2; return 1; }
    jar_url=$(printf '%s' "$server_default" | grep -oE '"url":"https://[^"]+\.jar"' | head -1 | sed 's/^"url":"//; s/"$//')
    [ -n "$jar_url" ] || { echo '[ERROR] 公式Proxyのserver:defaultダウンロードURLを取得できませんでした。' >&2; return 1; }
  fi
  required_java=$(proxy_required_java "$kind" "$version")
  echo "[RUN] 公式安定版Proxyを取得しています: $project $version build $build" >&2
  tmp_jar="$root/.$jar_name.$$.downloading"
  download "$jar_url" "$tmp_jar" || { rm -f "$tmp_jar"; echo '[ERROR] Proxy本体のダウンロードに失敗しました。' >&2; return 1; }
  mv -f "$tmp_jar" "$root/$jar_name"; chmod 600 "$root/$jar_name" 2>/dev/null || true
  mkdir -p "$root/plugins"
  if [ "$kind" = velocity ]; then
    cat > "$root/velocity.toml" <<EOF
config-version = "2.7"
bind = "0.0.0.0:$LISTEN_PORT"
motd = "GriefGuard Proxy"
show-max-players = 20
online-mode = true
force-key-authentication = true
player-info-forwarding-mode = "modern"
forwarding-secret-file = "forwarding.secret"

[servers]
try = ["backend"]
backend = "$BACKEND_HOST:$BACKEND_PORT"

[forced-hosts]

[advanced]
command-rate-limit = 40
tab-complete-rate-limit = 20

[query]
enabled = false
EOF
    if command -v od >/dev/null 2>&1; then od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$root/forwarding.secret"; else printf '%s\n' "$(date +%s)-$$-griefguard" > "$root/forwarding.secret"; fi
    chmod 600 "$root/forwarding.secret"
  else
    cat > "$root/config.yml" <<EOF
forge_support: false
enable_query: false
connection_throttle: 4000
connection_throttle_limit: 3
ip_forward: true
online_mode: true
log_commands: false
network_compression_threshold: 256
servers:
  backend:
    motd: '&aGriefGuard Backend'
    address: $BACKEND_HOST:$BACKEND_PORT
    restricted: false
listeners:
- query_port: $LISTEN_PORT
  motd: '&aGriefGuard Proxy'
  priorities:
  - backend
  host: 0.0.0.0:$LISTEN_PORT
  max_players: 20
EOF
  fi
  cat > "$root/start-proxy.sh" <<EOF
#!/bin/sh
set -eu
cd "\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
JAVA_BIN="\${GRIEFGUARD_JAVA_BIN:-java}"
command -v "\$JAVA_BIN" >/dev/null 2>&1 || { echo "[ERROR] Java ${required_java}以上が必要です。GRIEFGUARD_JAVA_BINまたはPATHを確認してください。" >&2; exit 11; }
exec "\$JAVA_BIN" -Xms512M -Xmx2G -jar "$jar_name"
EOF
  cat > "$root/Start-Proxy.command" <<EOF
#!/bin/sh
set -eu
cd "\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
JAVA_BIN="\${GRIEFGUARD_JAVA_BIN:-java}"
command -v "\$JAVA_BIN" >/dev/null 2>&1 || { echo "[ERROR] Java ${required_java}以上が必要です。GRIEFGUARD_JAVA_BINまたはPATHを確認してください。" >&2; exit 11; }
exec "\$JAVA_BIN" -Xms512M -Xmx2G -jar "$jar_name"
EOF
  cat > "$root/Start-Proxy.bat" <<EOF
@echo off
cd /d "%~dp0"
java -Xms512M -Xmx2G -jar "$jar_name"
if errorlevel 1 pause
EOF
cat > "$root/start-proxy-supervisor.sh" <<EOF
#!/bin/sh
set -u
ROOT="\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
PID_FILE="\$ROOT/.griefguard-proxy-supervisor.pid"
STOP_FILE="\$ROOT/.griefguard-proxy-stop"
mkdir -p "\$ROOT/logs"
if [ -f "\$PID_FILE" ]; then old_pid=\$(cat "\$PID_FILE" 2>/dev/null || true); case "\$old_pid" in *[!0-9]*|'') old_pid='' ;; esac; if [ -n "\$old_pid" ] && kill -0 "\$old_pid" 2>/dev/null; then exit 0; fi; fi
if [ -f "\$STOP_FILE" ] && [ "\${GRIEFGUARD_MANUAL_START:-0}" != "1" ]; then exit 0; fi
if [ "\${GRIEFGUARD_MANUAL_START:-0}" = "1" ]; then rm -f "\$STOP_FILE"; fi
printf '%s' "\$\$" > "\$PID_FILE"
trap 'rm -f "\$PID_FILE"' EXIT INT TERM
JAVA_BIN="\${GRIEFGUARD_JAVA_BIN:-java}"
if ! command -v "\$JAVA_BIN" >/dev/null 2>&1; then echo "\$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Java ${required_java}以上が見つかりません。" >> "\$ROOT/logs/proxy-supervisor.log"; exit 11; fi
while :; do
  [ -f "\$STOP_FILE" ] && exit 0
  echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] Proxyを起動します。" >> "\$ROOT/logs/proxy-supervisor.log"
  "\$JAVA_BIN" -cp "\$ROOT/plugins/GriefGuard-ProxyBridge.jar" com.example.griefguard.proxy.ProxySupervisorMain --config "\$ROOT/plugins/GriefGuard-ProxyBridge/proxy-config.json" --proxy-root "\$ROOT" --proxy-jar "\$ROOT/$jar_name" --java-bin "\$JAVA_BIN" --xms 512M --xmx 2G >> "\$ROOT/logs/proxy-supervisor.log" 2>&1
  status=\$?
  [ -f "\$STOP_FILE" ] && exit 0
  echo "\$(date '+%Y-%m-%d %H:%M:%S') [WARN] Proxy制御Agentが終了しました（終了コード: \$status）。5秒後に再起動します。" >> "\$ROOT/logs/proxy-supervisor.log"
  sleep 5
done
EOF
  cat > "$root/Start-Proxy-Supervisor.command" <<'EOF'
#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
rm -f .griefguard-proxy-stop
export GRIEFGUARD_MANUAL_START=1
exec ./start-proxy-supervisor.sh
EOF
  cat > "$root/Stop-Proxy-Supervisor.command" <<'EOF'
#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
touch "$ROOT/.griefguard-proxy-stop"
if command -v sha1sum >/dev/null 2>&1; then service_label="griefguard-proxy-$(printf '%s' "$ROOT" | sha1sum | cut -c1-12)"; elif command -v shasum >/dev/null 2>&1; then service_label="griefguard-proxy-$(printf '%s' "$ROOT" | shasum -a 1 | cut -c1-12)"; else service_label='griefguard-proxy-proxy'; fi
if command -v systemctl >/dev/null 2>&1; then systemctl --user stop "$service_label.service" 2>/dev/null || systemctl stop "$service_label.service" 2>/dev/null || true; fi
if command -v launchctl >/dev/null 2>&1; then launchctl bootout "gui/$(id -u)/$service_label" 2>/dev/null || true; fi
if [ -f "$ROOT/.griefguard-proxy-supervisor.pid" ]; then kill "$(cat "$ROOT/.griefguard-proxy-supervisor.pid")" 2>/dev/null || true; fi
EOF
  chmod 700 "$root/start-proxy.sh" "$root/Start-Proxy.command" "$root/start-proxy-supervisor.sh" "$root/Start-Proxy-Supervisor.command" "$root/Stop-Proxy-Supervisor.command"; chmod 600 "$root/Start-Proxy.bat"
  cat > "$root/griefguard-proxy-setup.json" <<EOF
{"platform":"$kind","version":"$version","build":"$build","jar":"$jar_name","listenPort":$LISTEN_PORT,"backendHost":"$(json_escape "$BACKEND_HOST")","backendPort":$BACKEND_PORT,"requiresJava":$required_java}
EOF
  TARGET="$root"
  echo "[OK] 新規Proxyを作成しました: $TARGET" >&2
  echo "[OK] Proxy本体: $jar_name ($version build $build)" >&2
  echo "[OK] Paper接続先: $BACKEND_HOST:$BACKEND_PORT / 待受: $LISTEN_PORT" >&2
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

# discover_root compatibility name is kept in this section for older checks.
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

# Older launchers used /root as a placeholder. Treat that value as "not set"
# so an upgrade automatically falls back to the real search instead of
# installing into an unrelated parent folder.
if [ -n "$TARGET" ] && is_broad_root "$TARGET"; then
  echo "[WARN] Proxyルートの初期値 '$TARGET' は親フォルダーのため使用しません。自動検索へ切り替えます。" >&2
  TARGET=""
fi

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo '[ERROR] curlまたはwgetが必要です。Ubuntuなら sudo apt-get install curl を実行してください。' >&2
  exit 11
fi

if [ "$CREATE_MODE" -ne 1 ] && [ -z "$TARGET" ]; then
  print_discovery_header
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
    tab=$(printf '\t')
    printf '%s\n' "$discovered" | while IFS="$tab" read -r candidate candidate_platform; do
      [ -n "$candidate" ] || continue
      echo "  $index. $(platform_label "$candidate_platform"): $candidate" >&2
      index=$((index + 1))
    done
    choice=$(ask '使用する番号' '')
    case "$choice" in
      ''|*[!0-9]*) echo '[ERROR] 候補番号は表示された数字で指定してください。' >&2; exit 12 ;;
    esac
    if [ "$choice" -lt 1 ] || [ "$choice" -gt "$candidate_count" ]; then
      echo "[ERROR] 候補番号が不正です。1〜$candidate_count の番号を指定してください。" >&2
      exit 12
    fi
    selected=$(printf '%s\n' "$discovered" | sed -n "${choice}p")
    TARGET=$(printf '%s' "$selected" | awk -F '\t' '{print $1}')
    PLATFORM=$(printf '%s' "$selected" | awk -F '\t' '{print $2}')
    [ -n "$TARGET" ] || { echo '[ERROR] 候補番号が不正です。' >&2; exit 12; }
  else
    echo '[INFO] 自動検索で利用可能なProxyルートは見つかりませんでした。' >&2
    mode=$(ask '1: 既存Proxyを選択 / 2: 新規Proxyを作成' '2')
    if [ "$mode" = 2 ]; then
      CREATE_MODE=1
      if [ -z "$PLATFORM" ]; then
        platform_guide
        number=$(ask '種類の番号 (1: Velocity / 2: BungeeCord・Waterfall)' '1')
        case "$number" in 1) PLATFORM=velocity ;; 2) PLATFORM=bungee ;; *) echo '[ERROR] 新規Proxyの種類は1または2です。' >&2; exit 13 ;; esac
      fi
    else
      platform_guide
      TARGET=$(ask '既存Proxyルート（例: /home/minecraft/velocity）' '')
    fi
  fi
fi
if [ "$CREATE_MODE" -eq 1 ]; then
  [ "$PLATFORM" = waterfall ] && PLATFORM=bungee
  [ -n "$PLATFORM" ] || { platform_guide; number=$(ask '種類の番号 (1: Velocity / 2: BungeeCord・Waterfall)' '1'); case "$number" in 1) PLATFORM=velocity ;; 2) PLATFORM=bungee ;; *) echo '[ERROR] 新規Proxyの種類は1または2です。' >&2; exit 13 ;; esac; }
  purge_known_proxy_roots "$TARGET"
  create_proxy_root "$PLATFORM" || exit 12
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

json_field() {
  value=$(printf '%s' "$2" | sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" | head -1)
  if [ -z "$value" ]; then value=$(printf '%s' "$2" | sed -n "s/.*\"$1\":\([0-9][0-9]*\).*/\1/p" | head -1); fi
  printf '%s' "$value"
}

verify_agent_proxy() {
  verify_url="$AGENT_URL"
  [ -n "$verify_url" ] || verify_url="http://$AGENT_HOST:3000"
  case "$verify_url" in http://*|https://*) ;; *) echo '[ERROR] Agent接続確認URLが不正です。' >&2; return 2 ;; esac
  payload=$(printf '{"proxyId":"%s","token":"%s"}' "$(json_escape "$PROXY_ID")" "$(json_escape "$TOKEN")")
  response_file="$tmp/verify-response.json"
  elapsed=0
  last=''
  timeout_seconds="$CONNECTION_TIMEOUT"
  case "$timeout_seconds" in ''|*[!0-9]*) timeout_seconds=60 ;; esac
  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    http_code=$(curl -sS --connect-timeout 5 --max-time 10 -H 'Content-Type: application/json' -d "$payload" -o "$response_file" -w '%{http_code}' "$verify_url/api/proxy/setup/verify" 2>/dev/null || printf '000')
    body=$(cat "$response_file" 2>/dev/null || true)
    case "$http_code" in
      2[0-9][0-9])
        if printf '%s' "$body" | grep -Eq '"ready"[[:space:]]*:[[:space:]]*true'; then return 0; fi
        last=$(printf '%s' "$body" | sed -n 's/.*"online"[[:space:]]*:[[:space:]]*\([^,}]*\).*"controlOnline"[[:space:]]*:[[:space:]]*\([^,}]*\).*/plugin=\1 control=\2/p' | head -1)
        ;;
      401) echo '[ERROR] Proxy IDまたはTokenが一致しません。アプリでProxy登録情報を再発行してください。' >&2; return 3 ;;
      404) echo '[ERROR] Agentが接続確認APIに対応していません。Agentを最新版へ更新して再実行してください。' >&2; return 2 ;;
      *) last="HTTP $http_code" ;;
    esac
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "[ERROR] Agent接続確認が${timeout_seconds}秒で完了しませんでした。${last:+ 最後の状態: $last}" >&2
  return 1
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

# Stop the old Supervisor for the selected root before replacing its JAR. The
# old connector itself is kept until the backup below is made. Other roots are
# deactivated only when they carry the same Proxy ID.
stop_managed_root_runtime "$TARGET"
repair_duplicate_roots "$TARGET" "$PROXY_ID"

tmp=$(mktemp -d 2>/dev/null || mktemp -d -t griefguard-proxy)
trap 'rm -rf "$tmp"' EXIT INT TERM
jar="$tmp/GriefGuard-ProxyBridge.jar"
sums="$tmp/SHA256SUMS"
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
if [ "${GRIEFGUARD_PROXY_NO_AUTOSTART:-0}" != 1 ]; then
  if [ "$PLATFORM" = velocity ]; then jar_name=$(find "$TARGET" -maxdepth 1 -type f -iname 'velocity*.jar' -print -quit 2>/dev/null | sed 's#^.*/##'); else jar_name=$(find "$TARGET" -maxdepth 1 -type f \( -iname 'waterfall*.jar' -o -iname 'bungeecord*.jar' -o -iname 'bungee*.jar' \) -print -quit 2>/dev/null | sed 's#^.*/##'); fi
  if [ -n "$jar_name" ]; then
    if [ "$PLATFORM" = velocity ]; then bridge_config_rel='plugins/griefguard-proxybridge/proxy-config.json'; else bridge_config_rel='plugins/GriefGuard-ProxyBridge/proxy-config.json'; fi
    mkdir -p "$TARGET/logs"
    cat > "$TARGET/start-proxy-supervisor.sh" <<EOF
#!/bin/sh
set -u
ROOT="\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
PID_FILE="\$ROOT/.griefguard-proxy-supervisor.pid"
STOP_FILE="\$ROOT/.griefguard-proxy-stop"
mkdir -p "\$ROOT/logs"
if [ -f "\$PID_FILE" ]; then old_pid=\$(cat "\$PID_FILE" 2>/dev/null || true); case "\$old_pid" in *[!0-9]*|'') old_pid='' ;; esac; if [ -n "\$old_pid" ] && kill -0 "\$old_pid" 2>/dev/null; then exit 0; fi; fi
if [ -f "\$STOP_FILE" ] && [ "\${GRIEFGUARD_MANUAL_START:-0}" != "1" ]; then exit 0; fi
if [ "\${GRIEFGUARD_MANUAL_START:-0}" = "1" ]; then rm -f "\$STOP_FILE"; fi
printf '%s' "\$\$" > "\$PID_FILE"
trap 'rm -f "\$PID_FILE"' EXIT INT TERM
JAVA_BIN="\${GRIEFGUARD_JAVA_BIN:-java}"
command -v "\$JAVA_BIN" >/dev/null 2>&1 || { echo "\$(date '+%Y-%m-%d %H:%M:%S') [ERROR] Javaが見つかりません。" >> "\$ROOT/logs/proxy-supervisor.log"; exit 11; }
while :; do
  [ -f "\$STOP_FILE" ] && exit 0
  echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] Proxyを起動します。" >> "\$ROOT/logs/proxy-supervisor.log"
  "\$JAVA_BIN" -cp "\$ROOT/plugins/GriefGuard-ProxyBridge.jar" com.example.griefguard.proxy.ProxySupervisorMain --config "\$ROOT/$bridge_config_rel" --proxy-root "\$ROOT" --proxy-jar "\$ROOT/$jar_name" --java-bin "\$JAVA_BIN" --xms 512M --xmx 2G >> "\$ROOT/logs/proxy-supervisor.log" 2>&1
  status=\$?
  [ -f "\$STOP_FILE" ] && exit 0
  echo "\$(date '+%Y-%m-%d %H:%M:%S') [WARN] Proxy制御Agentが終了しました（終了コード: \$status）。5秒後に再起動します。" >> "\$ROOT/logs/proxy-supervisor.log"
  sleep 5
done
EOF
    cat > "$TARGET/Start-Proxy-Supervisor.command" <<'EOF'
#!/bin/sh
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
rm -f .griefguard-proxy-stop
export GRIEFGUARD_MANUAL_START=1
exec ./start-proxy-supervisor.sh
EOF
    cat > "$TARGET/Stop-Proxy-Supervisor.command" <<'EOF'
#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
touch "$ROOT/.griefguard-proxy-stop"
if command -v sha1sum >/dev/null 2>&1; then service_label="griefguard-proxy-$(printf '%s' "$ROOT" | sha1sum | cut -c1-12)"; elif command -v shasum >/dev/null 2>&1; then service_label="griefguard-proxy-$(printf '%s' "$ROOT" | shasum -a 1 | cut -c1-12)"; else service_label='griefguard-proxy-proxy'; fi
if command -v systemctl >/dev/null 2>&1; then systemctl --user stop "$service_label.service" 2>/dev/null || systemctl stop "$service_label.service" 2>/dev/null || true; fi
if command -v launchctl >/dev/null 2>&1; then launchctl bootout "gui/$(id -u)/$service_label" 2>/dev/null || true; fi
if [ -f "$ROOT/.griefguard-proxy-supervisor.pid" ]; then kill "$(cat "$ROOT/.griefguard-proxy-supervisor.pid")" 2>/dev/null || true; fi
EOF
    chmod 700 "$TARGET/start-proxy-supervisor.sh" "$TARGET/Start-Proxy-Supervisor.command" "$TARGET/Stop-Proxy-Supervisor.command"
    install_autostart "$TARGET" "$PLATFORM"
    echo '[OK] Proxy制御Agentの自動起動・終了時再起動を設定しました。'
  else
    echo '[WARN] Proxy本体JARを特定できないため、制御Agentの常駐登録を省略しました。'
  fi
else
  echo '[INFO] GRIEFGUARD_PROXY_NO_AUTOSTART=1のため常駐登録を省略しました。'
fi

result_file="$TARGET/griefguard-proxy-install-result.json"
if [ "${GRIEFGUARD_PROXY_NO_AUTOSTART:-0}" = 1 ]; then
  printf '{"success":false,"verified":false,"reason":"--no-auto-startが指定されたため未確認","proxyId":"%s","checkedAt":"%s"}\n' "$(json_escape "$PROXY_ID")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$result_file"
  echo '[WARN] --no-auto-startが指定されたためAgent接続確認を省略しました。Proxyを起動後、アプリでオンライン状態を確認してください。'
elif [ "$NO_VERIFY" -eq 1 ]; then
  printf '{"success":false,"verified":false,"reason":"--no-verifyが指定されたため未確認","proxyId":"%s","checkedAt":"%s"}\n' "$(json_escape "$PROXY_ID")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$result_file"
  echo '[WARN] --no-verifyが指定されたためAgent接続確認を省略しました。Proxy起動後、アプリでオンライン状態を確認してください。'
else
  echo '[RUN] AgentとProxyBridgeの接続を確認しています（最大待機時間あり）…'
  if verify_agent_proxy; then
    printf '{"success":true,"verified":true,"proxyId":"%s","checkedAt":"%s"}\n' "$(json_escape "$PROXY_ID")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$result_file"
    echo '[OK] AgentとProxyBridgeの接続を確認しました。インストール完了です。'
  else
    printf '{"success":false,"verified":false,"reason":"Agent接続確認に失敗しました","proxyId":"%s","checkedAt":"%s"}\n' "$(json_escape "$PROXY_ID")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$result_file"
    echo "[ERROR] Proxyは配置しましたが、Agent接続を確認できませんでした。ログ: $TARGET/logs/proxy-supervisor.log" >&2
    exit 21
  fi
fi
