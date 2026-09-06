# Godot をダウンロードして `godot` コマンドとして使えるようにするスクリプト（Windows 用）。
# tools/setup_godot.sh の Windows 版。バージョンは .godot-version で固定している。
#
# 使い方:
#   powershell -ExecutionPolicy Bypass -File tools\setup_godot.ps1
#
# 配置先（Linux 版と同じレイアウト）:
#   %USERPROFILE%\.local\godot\<version>\Godot_v<version>_win64.exe (+ _console.exe)
#   %USERPROFILE%\.local\bin\godot.cmd   PowerShell / cmd 用
#   %USERPROFILE%\.local\bin\godot       Git Bash 用
#
# 何度実行しても安全（インストール済みならダウンロードしない）。
$ErrorActionPreference = 'Stop'

$RepoRoot   = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Version    = (Get-Content (Join-Path $RepoRoot '.godot-version') -Raw).Trim()   # 例: 4.7.2-stable
$InstallDir = if ($env:GODOT_INSTALL_DIR) { $env:GODOT_INSTALL_DIR } else { Join-Path $env:USERPROFILE '.local\godot' }
$BinDir     = if ($env:GODOT_BIN_DIR)     { $env:GODOT_BIN_DIR }     else { Join-Path $env:USERPROFILE '.local\bin' }

$Archive = "Godot_v${Version}_win64.exe.zip"
$Binary  = "Godot_v${Version}_win64.exe"
$Console = "Godot_v${Version}_win64_console.exe"
$BaseUrl = "https://github.com/godotengine/godot/releases/download/${Version}"

$VersionDir = Join-Path $InstallDir $Version
$Target     = Join-Path $VersionDir $Binary
$TargetCon  = Join-Path $VersionDir $Console

if ((Test-Path $Target) -and (Test-Path $TargetCon)) {
    Write-Host "Godot ${Version} はインストール済みです: $Target"
} else {
    Write-Host "Godot ${Version} をダウンロードします..."
    $Work = Join-Path ([IO.Path]::GetTempPath()) ("godot-setup-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Work | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$Archive"          -OutFile (Join-Path $Work $Archive)
        Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/SHA512-SUMS.txt"   -OutFile (Join-Path $Work 'SHA512-SUMS.txt')

        Write-Host "チェックサムを検証します..."
        $line = Get-Content (Join-Path $Work 'SHA512-SUMS.txt') | Where-Object { $_ -match "\s$([regex]::Escape($Archive))$" }
        if (-not $line) { throw "SHA512-SUMS.txt に $Archive が見つかりません" }
        $expected = ($line -split '\s+')[0].ToLower()
        $actual   = (Get-FileHash -Algorithm SHA512 (Join-Path $Work $Archive)).Hash.ToLower()
        if ($expected -ne $actual) { throw "チェックサムが一致しません`n  期待: $expected`n  実際: $actual" }
        Write-Host "  ok   $Archive"

        Expand-Archive -Path (Join-Path $Work $Archive) -DestinationPath $Work -Force
        New-Item -ItemType Directory -Force -Path $VersionDir | Out-Null
        Move-Item -Force (Join-Path $Work $Binary)  $Target
        Move-Item -Force (Join-Path $Work $Console) $TargetCon
        Write-Host "インストールしました: $Target"
    } finally {
        Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
    }
}

# コマンドを作成する。ターミナルへ標準出力を流すため、コンソール版 exe を呼び出す。
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$cmdShim = Join-Path $BinDir 'godot.cmd'
[IO.File]::WriteAllText($cmdShim, "@echo off`r`n`"$TargetCon`" %*`r`n", [Text.Encoding]::ASCII)

$shShim = Join-Path $BinDir 'godot'
$shTarget = $TargetCon.Replace([char]92, [char]47)
[IO.File]::WriteAllText($shShim, "#!/bin/sh`nexec `"$shTarget`" `"`$@`"`n", (New-Object Text.UTF8Encoding($false)))

Write-Host "コマンドを作成しました: $cmdShim -> $TargetCon"
Write-Host "コマンドを作成しました: $shShim -> $TargetCon"

$onPath = ($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $BinDir.TrimEnd('\') }
if (-not $onPath) {
    Write-Host "PATH に $BinDir を追加してください（ユーザー環境変数 Path）。"
}

& $cmdShim --version
