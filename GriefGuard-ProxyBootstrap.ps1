param(
  [ValidateSet('velocity','bungee','waterfall','geyser','')][string]$Platform = '',
  [string]$Target = '',
  [string]$AgentHost = '',
  [int]$AgentPort = 25502,
  [string]$ProxyId = '',
  [string]$Token = '',
  [switch]$Offline,
  [string]$BridgeFile = ''
)

$ErrorActionPreference = 'Stop'
$Repo = 'Minato-256/GriefGuard'
$ReleaseBase = "https://github.com/$Repo/releases/latest/download"
$RawBase = "https://raw.githubusercontent.com/$Repo/main"
$JarName = 'GriefGuard-ProxyBridge.jar'
$Temp = Join-Path ([IO.Path]::GetTempPath()) ("griefguard-proxy-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Temp | Out-Null

function Fail([string]$Message) { throw $Message }
function Detect-Platform([string]$Root) {
  if (Test-Path -LiteralPath (Join-Path $Root 'velocity.toml')) { return 'velocity' }
  if ((Test-Path -LiteralPath (Join-Path $Root 'bungee.yml')) -or ((Test-Path -LiteralPath (Join-Path $Root 'config.yml')) -and (Test-Path -LiteralPath (Join-Path $Root 'plugins')))) { return 'bungee' }
  if (Test-Path -LiteralPath (Join-Path $Root 'extensions')) { return 'geyser' }
  return ''
}
function Read-Default([string]$Prompt, [string]$Default) {
  $value = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value.Trim()
}

try {
  if ([string]::IsNullOrWhiteSpace($Target)) {
    $detected = Detect-Platform (Get-Location).Path
    if ($detected) { $Target = (Get-Location).Path; if (-not $Platform) { $Platform = $detected } }
  }
  if ([string]::IsNullOrWhiteSpace($Target)) { $Target = Read-Host 'ProxyまたはGeyserのルートフォルダー' }
  $Target = (Resolve-Path -LiteralPath $Target).Path
  if (-not $Platform) { $Platform = Detect-Platform $Target }
  if ($Platform -eq 'waterfall') { $Platform = 'bungee' }
  if ($Platform -notin @('velocity','bungee','geyser')) {
    Write-Host "Proxy種類を選択してください。`n  1. Velocity`n  2. BungeeCord / Waterfall`n  3. Geyser Extension"
    switch (Read-Default '番号' '1') { '1' { $Platform = 'velocity' } '2' { $Platform = 'bungee' } '3' { $Platform = 'geyser' } default { Fail 'Proxy種類の番号が不正です。' } }
  }
  if ([string]::IsNullOrWhiteSpace($AgentHost)) { $AgentHost = Read-Default 'Agentの待受アドレス（Agent PCのTailscale IP）' '127.0.0.1' }
  if ($AgentHost -match '[\"''\s;|&]') { Fail 'Agentアドレスに使用できない文字があります。' }
  if ($AgentPort -lt 1 -or $AgentPort -gt 65535) { Fail 'Agentポートは1〜65535で指定してください。' }
  if ([string]::IsNullOrWhiteSpace($ProxyId)) { $ProxyId = Read-Host 'Proxy ID' }
  if ($ProxyId -notmatch '^[A-Za-z0-9_-]{3,80}$') { Fail 'Proxy IDが不正です。' }
  if ([string]::IsNullOrWhiteSpace($Token)) { $secure = Read-Host 'ペアリングToken（入力は表示されません）' -AsSecureString; $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) } }
  if ($Token.Length -lt 24 -or $Token -match '[\"''\s;|&]') { Fail 'Tokenが不正です。24文字以上で指定してください。' }

  if ($BridgeFile) { $Bridge = (Resolve-Path -LiteralPath $BridgeFile).Path }
  elseif ($Offline) { $Bridge = Join-Path $PSScriptRoot $JarName }
  else {
    $Bridge = Join-Path $Temp $JarName
    Write-Host '[INFO] GitHub ReleasesからProxyBridgeを取得しています…'
    try { Invoke-WebRequest -UseBasicParsing "$ReleaseBase/$JarName" -OutFile $Bridge }
    catch {
      Write-Host '[INFO] Releaseアセットが見つからないため、リポジトリ直下から取得します。'
      Invoke-WebRequest -UseBasicParsing "$RawBase/$JarName" -OutFile $Bridge
    }
    $sums = Join-Path $Temp 'SHA256SUMS'
    try { Invoke-WebRequest -UseBasicParsing "$ReleaseBase/SHA256SUMS" -OutFile $sums }
    catch { Invoke-WebRequest -UseBasicParsing "$RawBase/SHA256SUMS" -OutFile $sums }
    $line = Get-Content -LiteralPath $sums | Where-Object { $_ -match '\sGriefGuard-ProxyBridge\.jar\s*$' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '^([a-fA-F0-9]{64})\s+') { Fail 'JARのSHA-256が見つかりません。' }
    $expected = $Matches[1].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Bridge).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { Fail 'ProxyBridgeのSHA-256検証に失敗しました。' }
  }
  if (-not (Test-Path -LiteralPath $Bridge)) { Fail "ProxyBridge JARが見つかりません: $Bridge" }

  if ($Platform -eq 'geyser') { $installDir = Join-Path $Target 'extensions'; $dataDir = Join-Path $installDir 'griefguardproxybridge' }
  else { $installDir = Join-Path $Target 'plugins'; $dataDir = if ($Platform -eq 'velocity') { Join-Path $installDir 'griefguard-proxybridge' } else { Join-Path $installDir 'GriefGuard-ProxyBridge' } }
  New-Item -ItemType Directory -Force -Path $installDir,$dataDir | Out-Null
  $destination = Join-Path $installDir $JarName
  if (Test-Path -LiteralPath $destination) { Copy-Item -LiteralPath $destination -Destination ($destination + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
  Copy-Item -LiteralPath $Bridge -Destination $destination -Force

  $config = [ordered]@{ agentHost=$AgentHost; agentPort=$AgentPort; proxyId=$ProxyId; token=$Token; platform=$Platform; enabled=$true; failClosed=$false; cacheMaxAgeSeconds=86400 } | ConvertTo-Json
  $configPath = Join-Path $dataDir 'proxy-config.json'
  [IO.File]::WriteAllText($configPath, $config + "`r`n", (New-Object Text.UTF8Encoding($false)))
  Write-Host "[OK] ProxyBridgeを配置しました: $destination"
  Write-Host "[OK] 接続設定を保存しました: $configPath"
  Write-Host '[NEXT] Proxyを再起動し、アプリの「Proxy接続管理」でオンライン状態を確認してください。'
}
finally {
  Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
