# Verification of ADR 0029 on Windows (run in a shell with the MSVC environment): an executable that embeds the
# Lua 5.5 interpreter (here: linked to lua55.dll, which sits beside it) and the same four checks as
# verify_interpreter.sh.
# usage: verify_interpreter.ps1 -Toolchain <prefix> -LuaRocksLib <dir> -LuaRocksBin <script> -Work <dir>
param(
  [Parameter(Mandatory)][string]$Toolchain,
  [Parameter(Mandatory)][string]$LuaRocksLib,
  [Parameter(Mandatory)][string]$LuaRocksBin,
  [Parameter(Mandatory)][string]$Work,
  [string]$NativeRock = 'digest',
  [string]$PureRock = 'plc'
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Work = (Resolve-Path $Work).Path

function Step($text) { Write-Host "`n=== $text" }
function Run {
  & $args[0] $args[1..($args.Count - 1)]
  if ($LASTEXITCODE -ne 0) { throw "failed (exit $LASTEXITCODE): $($args -join ' ')" }
}

Step 'build the host (Lua 5.5 in lua55.dll beside it)'
$lib = Get-ChildItem -Path $Toolchain -Recurse -Filter lua55.lib | Select-Object -First 1
$dll = Get-ChildItem -Path $Toolchain -Recurse -Filter lua55.dll | Select-Object -First 1
if (-not $lib -or -not $dll) { throw 'lua55.lib or lua55.dll not found in the toolchain' }
Push-Location $Work
Run cl /nologo /MD /O2 "$here\lua_host.c" "/I$Toolchain\include" /Fe:host.exe /link $lib.FullName
Pop-Location
Copy-Item $dll.FullName $Work
Get-ChildItem $Work -Filter host.exe | Format-List Name, Length

$host_ = Join-Path $Work 'host.exe'

Step '1. the host loads a native rock built by the standard toolchain'
Run luarocks --tree "$Work\t1" install $NativeRock
$env:LUA_CPATH = "$Work\t1\lib\lua\5.5\?.dll;;"
Run $host_ "$here\check_native.lua" $NativeRock

# LUAROCKS_CONFIG is the toolchain's (compiler and library variables); only the tree changes, with --tree.
$env:LUA_PATH = "$LuaRocksLib\?.lua;;"

Step "2. LuaRocks runs inside the host and installs a pure-Lua rock ($PureRock)"
Run $host_ $LuaRocksBin --version
Run $host_ $LuaRocksBin --tree "$Work\t2" install $PureRock

Step "3. LuaRocks runs inside the host and builds a source rock ($NativeRock) from the Lua headers"
# Verbose output is kept and filtered: the lines about deployment, copies and failures are what matters here.
$verbose = & $host_ $LuaRocksBin --tree "$Work\t3" install --verbose $NativeRock 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Write-Host $verbose; throw "install of $NativeRock failed" }
Write-Host 'the last 90 verbose lines of the install, shortened:'
$lines = $verbose -split "`r?`n"
$lines | Select-Object -Last 90 | ForEach-Object { $t = $_.Trim(); if ($t.Length -gt 150) { $t = $t.Substring(0, 150) + '...' }; Write-Host "  $t" }
Write-Host 'files installed in t3:'
Get-ChildItem -Recurse -File "$Work\t3" | ForEach-Object { Write-Host "  $($_.FullName)" }
$env:LUA_PATH = "$LuaRocksLib\?.lua;;"
$env:LUA_CPATH = "$Work\t3\lib\lua\5.5\?.dll;;"
Run $host_ "$here\check_native.lua" $NativeRock

Step '4. the contract test of the sha256 seam runs in the host'
if ($NativeRock -eq 'digest') {
  $env:LUA_PATH = "$here\?.lua;$Work\t2\share\lua\5.5\?.lua;;"
  Run $host_ "$here\digest_test.lua" digest
  Run $host_ "$here\digest_test.lua" plc
}
Write-Host "`nall checks passed"
