# Manual check of `hecate.test` on Windows

For a person on a fresh Windows machine (x64). The goal is to see the reporters on a real console, which no CI run
can show. Record what you see in `HANDOFF.md` (pull request of the `test` item), under "Next steps", item 3.

## 1. Install the tools (once)

Use PowerShell. Reboot or open a new shell after each installer that changes `PATH`.

1. **Git**: `winget install --id Git.Git -e`
2. **Visual Studio Build Tools** with the C++ workload (compiles Lua and `luv`):
   `winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`
3. **CMake**: `winget install --id Kitware.CMake -e`
4. **Windows Terminal** (already present on Windows 11): `winget install --id Microsoft.WindowsTerminal -e`
5. **Rust**, only for the `json` reporter (step 4, check D): `winget install --id Rustlang.Rustup -e`, then `rustup default stable`.

## 2. Get the code and build the toolchain

Open **"x64 Native Tools Command Prompt for VS 2022"** (Start menu), then start PowerShell in it with `pwsh` or
`powershell`. Every command below runs there.

```powershell
git clone https://github.com/hecate-framework/hecate.git
cd hecate
git checkout claude/relay-test
powershell -ExecutionPolicy Bypass -File tools\bootstrap\bootstrap.ps1
$env:PATH = "$PWD\.hecate\toolchain\bin;$env:PATH"
$env:LUAROCKS_CONFIG = "$PWD\.hecate\toolchain\luarocks-config.lua"
lua -v
luarocks --tree .hecate\rocks install luv 1.53.0-0
```

`lua -v` must print `Lua 5.5.1`. The bootstrap takes a few minutes. If a command fails, copy its output into the
report and stop.

For the `json` reporter only (check D):

```powershell
$tc = "$PWD\.hecate\toolchain" -replace '\\', '/'
$env:LUA_LIB_NAME = 'lua55'; $env:LUA_LIB = "$tc/lib"; $env:LUA_INC = "$tc/include"
lua tools\run.lua build-native json
```

## 3. Sanity check

```powershell
lua tools\run.lua test test
```

Expected: `test: ok`. This runs the unit tests of the package, including the golden files of the reporters.

## 4. The manual checks

The demo (`packages\test\manual\demo`) has 32 tests on purpose: passing ones, a failure with a structural diff, an
error, a message with non-ASCII characters, a suite of 2000 assertions and a long case name in a nested directory.
**The expected exit status is 1.** Show it with `echo $LASTEXITCODE`.

Run each check twice: in **Windows Terminal (PowerShell tab)** and in **`cmd.exe`**, and say which one you used.
The "x64 Native Tools Command Prompt" of step 2 is itself a `cmd.exe`: in it, set the environment with
`set PATH=%CD%\.hecate\toolchain\bin;%PATH%` and `set LUAROCKS_CONFIG=%CD%\.hecate\toolchain\luarocks-config.lua`
(the PowerShell commands of step 2 do the same). In a Windows Terminal PowerShell tab, run the same two settings in
PowerShell syntax from the `hecate` directory. The redirections `>` and the `Get-Content` commands below are
PowerShell; in `cmd.exe` use `type` instead.

| | Command | What to look at |
|---|---|---|
| A | `lua packages\test\manual\run.lua console` | Colours: `TEST` orange, `PASS` green, `FAIL` red, cells of the bar green or red. Does the `passing_test.lua` line redraw in place while it runs (about 2.4 s), or do you see raw `[2K`/`[31m` characters or one line per update? The default is plain output when the terminal is not detected as live: note what you get. |
| B | `lua packages\test\manual\run.lua console --live --color` | The forced live mode: same questions. Raw escape sequences here in `cmd.exe` would mean the console needs virtual-terminal processing enabled by the reporter. |
| C | `lua packages\test\manual\run.lua console --width=60` then `--width=40` | No line wider than the width; the bar and the names shrink. Also resize the window and run without `--width`. |
| D | `lua packages\test\manual\run.lua json > out.jsonl` then `Get-Content out.jsonl -First 3` | Valid JSON per line, no `^M` glitches, accents preserved in the `failing_test` messages (open the file in an editor: UTF-8, `\n` or `\r\n` line ends?). Needs the Rust step. |
| E | `lua packages\test\manual\run.lua tap > out.tap` then `Get-Content out.tap -First 5` | `TAP version 14`, `1..32`, then `ok` / `not ok` lines; line ends; the non-ASCII test name/message. |
| F | `lua packages\test\manual\run.lua junit > out.xml` | Well-formed XML (open it in Edge); the `✓` character appears correctly. |
| G | `lua packages\test\manual\run.lua console > out.txt` then `type out.txt` | Redirected to a file: plain text, no escape sequences, no redraw. |
| H | `lua packages\test\manual\run.lua console --no-color` | No escape sequences; failed cells shown as `F`. |
| I | `lua packages\test\manual\run.lua console packages\test\tests\fixtures\discovery` | Discovery with backslashes and a nested directory; the suite names shown (are the paths printed with `/` or `\`?). |
| J | `$env:HECATE_TEST_LIVE = "1"; lua packages\test\manual\run.lua console` (then `Remove-Item Env:HECATE_TEST_LIVE`) | The environment switch enables live redraw. |

## 5. Report

For each row: Windows Terminal ok / not ok, `cmd.exe` ok / not ok, and a screenshot or the copied text for anything
odd. Also report your Windows version (`winver`) and whether `lua tools\run.lua test test` passed.
