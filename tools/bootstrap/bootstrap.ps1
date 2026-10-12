<#
.SYNOPSIS
  Pinned bootstrap for Windows: builds Lua with MSVC and installs LuaRocks, with
  SHA-256 verification. Windows counterpart of bootstrap.sh.
.PARAMETER Prefix
  Install location (default: .hecate\toolchain under the repository root).
.PARAMETER Arch
  Target architecture: x64 or arm64 (default: the host's). The MSVC environment must
  target the same architecture. LuaRocks ships no arm64 build, so its x64 executables
  run under Windows' emulation on arm64; Lua itself is built natively.
.NOTES
  Requires a Visual Studio C++ toolchain and CMake in PATH, in a developer shell
  (or after ilammy/msvc-dev-cmd in GitHub Actions).
#>
param(
  [ValidateSet('x64', 'arm64')]
  [string]$Arch = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }),
  [string]$Prefix = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.hecate\toolchain')
)
$ErrorActionPreference = 'Stop'

$LuaVersion = '5.5.1'
$LuaSha256 = '1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce'
$LuaRocksVersion = '3.13.0'
$LuaRocksSha256 = '0897ade5d459d55cd1962a948153745a6749feb345403c68aaa9207388557ab9'
$LuaAbi = '55'

$work = Join-Path ([IO.Path]::GetTempPath()) ("hecate-bootstrap-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
  function Get-Verified($Url, $Sha256, $File) {
    $path = Join-Path $work $File
    Invoke-WebRequest -Uri $Url -OutFile $path -UseBasicParsing
    $actual = (Get-FileHash -Algorithm SHA256 $path).Hash.ToLowerInvariant()
    if ($actual -ne $Sha256) { throw "checksum mismatch for $File (got $actual)" }
    return $path
  }

  $luaTgz = Get-Verified "https://www.lua.org/ftp/lua-$LuaVersion.tar.gz" $LuaSha256 'lua.tar.gz'
  $rocksZip = Get-Verified "https://luarocks.org/releases/luarocks-$LuaRocksVersion-windows-64.zip" $LuaRocksSha256 'luarocks.zip'

  tar -xzf $luaTgz -C $work
  if ($LASTEXITCODE -ne 0) { throw 'tar failed' }

  New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
  $Prefix = (Resolve-Path $Prefix).Path
  $cmakeDir = Join-Path $PSScriptRoot 'lua-cmake'
  $build = Join-Path $work 'build'

  $cmakeArch = if ($Arch -eq 'arm64') { 'ARM64' } else { 'x64' }
  cmake -S $cmakeDir -B $build -A $cmakeArch "-DLUA_SRC=$work\lua-$LuaVersion\src" "-DLUA_ABI=$LuaAbi"
  if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
  cmake --build $build --config Release
  if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }
  cmake --install $build --config Release --prefix $Prefix
  if ($LASTEXITCODE -ne 0) { throw 'cmake install failed' }

  Expand-Archive -Path $rocksZip -DestinationPath $work -Force
  Copy-Item "$work\luarocks-$LuaRocksVersion-windows-64\*.exe" (Join-Path $Prefix 'bin')

  # LuaRocks must know where the import library is to build C rocks (spike OQ-2).
  $p = $Prefix -replace '\\', '/'
  $config = @"
rocks_trees = { "$p/rocks" }
lua_interpreter = "lua.exe"
lua_version = "5.5"
variables = {
  LUA_DIR = "$p",
  LUA_INCDIR = "$p/include",
  LUA_LIBDIR = "$p/lib",
  LUA_BINDIR = "$p/bin",
  LUALIB = "lua$LuaAbi.lib",
}
"@
  Set-Content -Path (Join-Path $Prefix 'luarocks-config.lua') -Value $config -Encoding ASCII

  $env:LUAROCKS_CONFIG = Join-Path $Prefix 'luarocks-config.lua'
  & (Join-Path $Prefix 'bin\lua.exe') -v
  & (Join-Path $Prefix 'bin\luarocks.exe') --version | Select-Object -First 1
  Write-Host "Add $Prefix\bin to PATH and set LUAROCKS_CONFIG=$Prefix\luarocks-config.lua"
}
finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
