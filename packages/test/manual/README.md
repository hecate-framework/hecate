# Manual check of `hecate.test` on Windows

For a person on a fresh Windows 10 or 11 machine, 64-bit (x64), who has not developed on Windows before. The goal is
to look at the reporters on a real console, which no CI run can show. Record what you see in `HANDOFF.md` (pull
request of the `test` item), under "Next steps", item 3.

Allow about an hour, most of it installers. You need an administrator account (installers ask for permission), an
internet connection and about 10 GB of free disk.

## 0. Vocabulary

- **Terminal**: the window where you type commands. **Windows Terminal** is the modern one (default on Windows 11).
  **`cmd.exe`** is the old command interpreter, **PowerShell** the newer one; both run inside a terminal window.
- **PATH**: the list of folders searched when you type a program name (`git`, `lua`). A program installed after a
  window was opened is found only in windows opened after the installation.
- **winget**: the command-line installer of Windows (like `apt` on Linux). It asks you to accept its terms the first
  time: type `Y`.
- **MSVC**: the Microsoft C compiler, needed to build Lua and the native parts. It is installed by *Visual Studio
  Build Tools* and is on the PATH only inside a special window, the **x64 Native Tools Command Prompt**.

## 1. Check the machine

1. Press **Win + R**, type `winver`, Enter. Write down the version (for example "Windows 11, 23H2").
2. Settings, System, About: "System type" must say **64-bit operating system, x64-based processor**. If it says
   32-bit or ARM, stop and tell the maintainers.
3. Open the Start menu, type `terminal`, open **Terminal** (Windows Terminal). If there is none, open
   **Windows PowerShell** instead and install it in step 2.
4. In that window run `winget --version`. If the command is not found, install "App Installer" from the Microsoft
   Store, then reopen the window.

## 2. Install the tools (once)

In PowerShell (the Windows Terminal default tab). Accept the user-account-control prompts. Each command may take a
while and print progress bars.

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.WindowsTerminal -e
winget install --id Kitware.CMake -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
winget install --id Rustlang.Rustup -e
winget install --id Ninja-build.Ninja -e
```

If `winget` fails with `msstore` or a certificate error, add `--source winget` to each command.

- The Build Tools install is large (several GB, 10 to 30 minutes) and opens a progress window by itself. Wait for the
  command to return. If `winget` fails on it, download "Build Tools for Visual Studio 2022" from
  <https://visualstudio.microsoft.com/downloads/> (section "Tools for Visual Studio"), run it, tick **Desktop
  development with C++**, install.
- The Rust installer (`rustup`) may open a console asking how to proceed: press **Enter** for the standard
  installation. Rust is needed only for the `json` reporter (row D).

**Close the window and open a new one** so that the new programs are found. Check, in a new Windows Terminal:

```powershell
git --version
cmake --version
cargo --version
```

All three must print a version (and `ninja --version`). (If `cmake` is not found, the Build Tools bring their own, available in the window of
step 3; check it there with `cmake --version`.)

## 3. Open the build window

Open the Start menu, type `x64 Native Tools`, and open **x64 Native Tools Command Prompt for VS 2022**. It is a black
`cmd.exe` window in which the compiler is on the PATH. Make sure it says **x64**, not x86. Check:

```bat
cl
```

It prints "Microsoft (R) C/C++ Optimizing Compiler ... for x64". Then start PowerShell *inside this same window*, so
that the compiler stays available:

```bat
powershell
```

The prompt changes to `PS C:\...>`. All the commands of steps 4 and 5 run in this window.

## 4. Get the code and build Lua

```powershell
mkdir C:\dev
cd C:\dev
git clone https://github.com/hecate-framework/hecate.git
cd hecate
git checkout claude/relay-test
```

If Git asks you to sign in to GitHub, a browser window opens: sign in with an account that can read the repository.
Then build Lua 5.5 and LuaRocks (a few minutes; the `-ExecutionPolicy Bypass` lets this one script run):

```powershell
powershell -ExecutionPolicy Bypass -File tools\bootstrap\bootstrap.ps1
```

It ends with lines such as `Lua 5.5.1` and `LuaRocks 3.13.0`, and "Add ... to PATH". Do that now, for this window:

```powershell
$env:PATH = "$PWD\.hecate\toolchain\bin;$env:PATH"
$env:LUAROCKS_CONFIG = "$PWD\.hecate\toolchain\luarocks-config.lua"
lua -v
```

`lua -v` must print `Lua 5.5.1`. Then install the library the runtime uses (`luv`, compiled from C, a few minutes). LuaRocks asks CMake for the
MinGW generator by default, which this setup does not have, so first tell it to use Ninja (observed on a fresh
machine, 2026-11-15):

```powershell
Add-Content -Path .hecate\toolchain\luarocks-config.lua -Value 'cmake_generator = "Ninja"' -Encoding ASCII
luarocks --tree .hecate\rocks install luv 1.53.0-0
```

This must run in the **x64 Native Tools** window (step 3). "No CMAKE_C_COMPILER could be found" means the window is a
plain terminal: `cl` is not on its PATH.

## 5. The `json` reporter's native module (only for row D)

```powershell
cd packages\json\native
rustup toolchain install
cd ..\..\..
$tc = "$PWD\.hecate\toolchain" -replace '\\', '/'
$env:LUA_LIB_NAME = 'lua55'
$env:LUA_LIB = "$tc/lib"
$env:LUA_INC = "$tc/include"
lua tools\run.lua build-native json
```

It ends with `build-native: ok`. If it fails, skip row D and copy the error into the report: the other rows do not
need it.

## 6. Sanity check

```powershell
lua tools\run.lua test test
```

It must end with `test: ok` (a minute at most). Any other ending: copy the whole output into the report and stop.

## 7. Prepare the two windows for the manual rows

The rows are run in **both** windows below; set up each one (the compiler is not needed any more).

**Window 1, Windows Terminal, PowerShell tab**: open a new Terminal window, then:

```powershell
cd C:\dev\hecate
$env:PATH = "$PWD\.hecate\toolchain\bin;$env:PATH"
$env:LUAROCKS_CONFIG = "$PWD\.hecate\toolchain\luarocks-config.lua"
```

**Window 2, the old console**: since Windows 11 22H2, `cmd.exe` opens inside Windows Terminal by default, which hides
the old console. To get the old one, press **Win + R**, type `conhost.exe cmd.exe`, Enter (if the window looks like
Windows Terminal anyway, say so in the report). In it:

```bat
cd /d C:\dev\hecate
set PATH=%CD%\.hecate\toolchain\bin;%PATH%
set LUAROCKS_CONFIG=%CD%\.hecate\toolchain\luarocks-config.lua
```

In each new window, `lua -v` must print `Lua 5.5.1` before you go on.

## 8. The manual rows

The demo (`packages\test\manual\demo`) has 32 tests on purpose: passing ones, a failure with a structural diff, an
error, a message with non-ASCII characters, a suite of 2000 assertions and a long case name in a nested directory.
**The expected exit status is 1** (some tests fail on purpose). Show it with `echo $LASTEXITCODE` in PowerShell or
`echo %ERRORLEVEL%` in `cmd.exe`.

Commands are written for `cmd.exe`. In PowerShell, the same commands work unchanged, **except redirections**: write
them as `cmd /c "lua packages\test\manual\run.lua tap > out.tap"`, because PowerShell 5.1 saves the output of `>`
as UTF-16, which is not what the program wrote.

| | Command | What to look at |
|---|---|---|
| A | `lua packages\test\manual\run.lua console` | Four suite lines then a report. Colours: `FAIL` red, `PASS` green, cells of the bar green or red. Is there one line per suite, or does the `passing_test.lua` line redraw in place while it runs (about 2.4 s)? Raw characters such as `[31m` or `←[2K` in the text are a failure. Note exactly what you see. |
| B | `lua packages\test\manual\run.lua console --live --color` | Live mode forced on: the line of `passing_test.lua` fills its bar in place, one cell every 0.1 s. Raw escape characters here in the old console mean the console needs virtual-terminal processing switched on by the reporter. |
| C | `lua packages\test\manual\run.lua console --width=60`, then `--width=40` | No line wider than the width. Then resize the window narrow and run without `--width`: does the line fit? |
| D | `lua packages\test\manual\run.lua json > out.jsonl` then `type out.jsonl` | One JSON object per line. The accents of `failing_test` messages must read `héllo wörld ✓` in the file (open it in Notepad; it must be UTF-8). Needs step 5. |
| E | `lua packages\test\manual\run.lua tap > out.tap` then `type out.tap` | Starts with `TAP version 14` then `1..32`, then `ok` and `not ok` lines. Check the line endings by opening it in Notepad (status bar, bottom right: `Unix (LF)` or `Windows (CRLF)`). |
| F | `lua packages\test\manual\run.lua junit > out.xml` | Open `out.xml` in Microsoft Edge (drag it onto the window): it must show a tree, not an error. Look for the character `✓` in a failure message. |
| G | `lua packages\test\manual\run.lua console > out.txt` then `type out.txt` | Redirected to a file the output is plain text: no escape characters, no redraw. |
| H | `lua packages\test\manual\run.lua console --no-color` | No colours; failed cells of the bar are drawn as `F`. |
| I | `lua packages\test\manual\run.lua console packages\test\tests\fixtures\discovery` | Discovery with backslashes and a nested directory. Which suite names are printed, with `/` or `\`? |
| J | `set HECATE_TEST_LIVE=1` then `lua packages\test\manual\run.lua console` (then `set HECATE_TEST_LIVE=`). PowerShell: `$env:HECATE_TEST_LIVE = "1"`, later `Remove-Item Env:HECATE_TEST_LIVE`. | The environment switch turns live redraw on, as in B. |

Observed on a fresh machine (2026-11-15): in both windows the accents of `failing_test` read `h├-llo w╢rld Γ£ô`
(the UTF-8 bytes shown in code page 437). For a file, redirect in `cmd.exe`, or write
`cmd /c "lua ... > out.jsonl"` in PowerShell, then open it in Notepad: a PowerShell `>` converts the text through the
console code page first, and the file then holds the garbled text, which hides the real result of row D.

**Accents look broken in the console** (for example `hÃ©llo` or `h?llo`)? The program writes UTF-8 and the console
may use an older code page. Run `chcp 65001`, then repeat the row, and report both results: it is a console setting
to document, not necessarily a defect.

## 9. Report

For each row A to J: in Windows Terminal, *ok* / *not ok*; in the old console, *ok* / *not ok*; and the copied text or
a screenshot of anything odd (Win + Shift + S takes a screenshot). Also give: the Windows version from step 1, the
result of step 6, and whether step 5 worked.

## If something goes wrong

- *"cl is not recognized"*: you are not in the x64 Native Tools window (step 3).
- *"cmake is not recognized"*, `git`, `cargo`, `lua`: open a new window (PATH), and for `lua` redo the two `set`
  lines of step 4 or 7.
- *"running scripts is disabled"*: use the `powershell -ExecutionPolicy Bypass -File ...` form of step 4.
- Disk full, a download blocked by a firewall, a failing installer: copy the message, stop, and report it.
