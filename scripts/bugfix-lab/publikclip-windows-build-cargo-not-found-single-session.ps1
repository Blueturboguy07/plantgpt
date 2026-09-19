# bugfix-lab oracle (attempt 2) for cluster publikclip-windows-build-cargo-not-found
# -- plantgpt half (existing break 34ad7647-87fb-3000-6f47-9a594277de43).
#
# POPULATION: web readers of the LIVE plantgpt Windows install guide on publikhq.com
# (all three reports in this cluster have source="web"). The live guide's step 3 is
# "Open PowerShell -- Keep it open beside Iris.", and every later terminal step is run
# in THAT window. Both screenshots in this cluster show exactly one unbroken PowerShell
# session. So this oracle runs the guide's steps 3 -> 8 in ONE continuous session, NOT
# one fresh shell per step (a fresh shell re-reads PATH from the registry and silently
# repairs the very defect under test; that is the Iris-autopilot execution model, not
# this population's).
#
# Guide text: sourceCommit pin is unchanged (0e2cf7ae118beee65d9a07c1659de2b2ab4b85cd, still
# plantgpt main tip), but the "build" step's command was fixed on fix/publikclip-windows-
# build-cargo-not-found in ~publik (lib/guides/plantgpt.ts, version 8 -> 9) to mirror
# publikclip.ts's PATH-insurance line. This harness's step 8 below is kept byte-for-byte in
# sync with that new command (there is no live redeploy to fetch from mid-fix):
#   step 6 install-rust : winget install --id Rustlang.Rustup -e --source winget
#   step 7 clone        : clone + git checkout 0e2cf7ae118beee65d9a07c1659de2b2ab4b85cd
#   step 8 build (v9)   : npm.cmd install
#                          $env:Path = "$env:USERPROFILE\.cargo\bin;$env:LOCALAPPDATA\Microsoft\WinGet\Links;$env:Path"
#                          npm.cmd run tauri build
#
# Exit 1 = bug PRESENT : step 8 prints
#          "failed to run command cargo metadata --no-deps --format-version 1: program not found"
#          while %USERPROFILE%\.cargo\bin\cargo.exe EXISTS on disk.
# Exit 0 = bug ABSENT  : step 8's shell resolves cargo and gets past cargo metadata.
# Exit 2 = oracle could not run (a precondition failed -- printed).
#
# Prints BUGFIX_LAB_PRESENT / BUGFIX_LAB_ABSENT / BUGFIX_LAB_INCONCLUSIVE.

$ErrorActionPreference = 'Continue'
function Say($m) { Write-Host "[oracle] $m" }

# Bounded child-process runner. Used only where a hang would eat the job (winget, npm,
# tauri build). A child process inherits THIS session's environment block, so its view of
# PATH is identical to running the command inline -- which is the only thing this oracle
# measures. Output goes to files, never to a pipe we read synchronously (that is the
# ReadToEnd() deadlock attempt 1 hit).
function Run-Bounded {
    param([string]$File, [string[]]$ArgList, [int]$TimeoutSeconds, [string]$Tag)
    $out = Join-Path $env:TEMP "$Tag.out.txt"
    $err = Join-Path $env:TEMP "$Tag.err.txt"
    Remove-Item -LiteralPath $out, $err -ErrorAction SilentlyContinue
    try {
        $p = Start-Process -FilePath $File -ArgumentList $ArgList -PassThru -NoNewWindow `
            -RedirectStandardOutput $out -RedirectStandardError $err
    } catch {
        return [PSCustomObject]@{ TimedOut = $false; ExitCode = -2; Output = "could not start ${File}: $_" }
    }
    $done = $p.WaitForExit($TimeoutSeconds * 1000)
    if (-not $done) {
        try { & taskkill /pid $p.Id /T /F 2>&1 | Out-Null } catch {}
        Start-Sleep -Seconds 2
    }
    $stdout = if (Test-Path $out) { Get-Content -Raw -LiteralPath $out } else { "" }
    $stderr = if (Test-Path $err) { Get-Content -Raw -LiteralPath $err } else { "" }
    [PSCustomObject]@{
        TimedOut = (-not $done)
        ExitCode = $(if ($done) { $p.ExitCode } else { -1 })
        Output   = "$stdout`n$stderr"
    }
}

$cargoExe = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"

# ---------------------------------------------------------------------------
# PHASE 0 (environment, NOT part of the guide): make this look like a
# first-time reader's PC rather than a CI image.
# windows-latest ships a Rust toolchain AND pre-adds %USERPROFILE%\.cargo\bin to the
# PATH the runner hands every step. A reader's freshly opened PowerShell has neither.
# ---------------------------------------------------------------------------
Say "=== PHASE 0: strip the runner image's preinstalled Rust toolchain ==="
Say "rustup on PATH before cleanup: $([bool](Get-Command rustup -ErrorAction SilentlyContinue))"
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    & rustup self uninstall -y 2>&1 | Out-String | Write-Host
}
Remove-Item -Recurse -Force "$env:USERPROFILE\.cargo" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:USERPROFILE\.rustup" -ErrorAction SilentlyContinue

# Rebuild THIS session's PATH the way a newly opened PowerShell builds it: Machine
# then User, straight from the registry. This is what makes the session honest -- the
# reader's window was opened at guide step 3, before Rust existed.
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"
# If the CI image left a %USERPROFILE%\.cargo\bin entry behind in the registry PATH,
# drop it: the reader's window was opened at step 3 on a PC that had never had Rust, so
# no such entry can be in it. Same category of correction as uninstalling the toolchain.
$before = $env:Path
$env:Path = (($env:Path -split ';') | Where-Object { $_ -and ($_ -notlike '*\.cargo\bin*') }) -join ';'
if ($before -ne $env:Path) { Say "removed a leftover .cargo\bin entry the CI image had in the registry PATH" }

Say "session PATH (as a freshly opened PowerShell would see it):"
Write-Host $env:Path

Say "node   : $((Get-Command node.exe -ErrorAction SilentlyContinue).Source)"
Say "npm    : $((Get-Command npm.cmd -ErrorAction SilentlyContinue).Source)"
Say "git    : $((Get-Command git.exe -ErrorAction SilentlyContinue).Source)"
Say "winget : $((Get-Command winget.exe -ErrorAction SilentlyContinue).Source)"
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue) -or -not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Say "BUGFIX_LAB_INCONCLUSIVE: node/git are not in the registry PATH, so this session cannot stand in for a reader's window"
    exit 2
}

$preCargoOnDisk = Test-Path -LiteralPath $cargoExe
$preCargoResolves = [bool](Get-Command cargo -ErrorAction SilentlyContinue)
Say "cargo.exe on disk before the guide runs : $preCargoOnDisk"
Say "cargo resolvable in this session before : $preCargoResolves"
if ($preCargoOnDisk -or $preCargoResolves) {
    Say "BUGFIX_LAB_INCONCLUSIVE: could not return the machine to a rust-less state"
    exit 2
}

# ---------------------------------------------------------------------------
# GUIDE STEP 3 -- "Open PowerShell. Keep it open beside Iris."
# THIS process is that window. Everything below runs in it. Nothing reopens it.
# ---------------------------------------------------------------------------
Say "=== GUIDE STEP 3: Open PowerShell (this process IS the reader's window; it is never reopened) ==="

# Steps 4 and 5 (Install Ollama / ollama pull qwen2.5:3b) are skipped: they install a
# chat model, touch nothing on the Rust/PATH path this oracle measures, and cost GBs.

# ---------------------------------------------------------------------------
# GUIDE STEP 6 -- Install Rust, VERBATIM live command.
# ---------------------------------------------------------------------------
Say "=== GUIDE STEP 6: winget install --id Rustlang.Rustup -e --source winget ==="
$rust = Run-Bounded -File "winget.exe" `
    -ArgList @('install', '--id', 'Rustlang.Rustup', '-e', '--source', 'winget') `
    -TimeoutSeconds 420 -Tag "step6-winget"
Write-Host $rust.Output
Say "winget exit: $($rust.ExitCode) timedOut: $($rust.TimedOut)"

if (-not (Test-Path -LiteralPath $cargoExe)) {
    # winget on GH's windows-latest has stalled on agreement prompts before (attempt 1
    # burned 20+ minutes on it). Fall back to what the winget package itself runs:
    # rustup-init.exe with the default install. END STATE IS THE SAME THING THIS ORACLE
    # MEASURES -- cargo.exe on disk under %USERPROFILE%\.cargo\bin, installed from
    # inside this already-open session, with the session's own PATH untouched.
    Say "winget did not produce cargo.exe; falling back to rustup-init.exe (documented deviation)"
    $ProgressPreference = "SilentlyContinue"
    $initExe = Join-Path $env:TEMP "rustup-init.exe"
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile $initExe
    $fb = Run-Bounded -File $initExe -ArgList @('-y', '--default-toolchain', 'stable', '--profile', 'default') `
        -TimeoutSeconds 420 -Tag "step6-rustup-init"
    Write-Host $fb.Output
    Say "rustup-init exit: $($fb.ExitCode) timedOut: $($fb.TimedOut)"
}

$cargoOnDisk = Test-Path -LiteralPath $cargoExe
Say "PRECONDITION -- cargo.exe on disk at ${cargoExe}: $cargoOnDisk"
if (-not $cargoOnDisk) {
    Say "BUGFIX_LAB_INCONCLUSIVE: guide step 6 did not put cargo.exe on disk at all"
    exit 2
}
# The reader's window is NOT reopened. This is the whole point.
Say "cargo resolvable in THIS (still-open) session after step 6: $([bool](Get-Command cargo -ErrorAction SilentlyContinue))"
Say "session PATH still contains .cargo\bin? $($env:Path -like '*\.cargo\bin*')"

# ---------------------------------------------------------------------------
# GUIDE STEP 7 -- clone + pin, VERBATIM live command, run inline in this session.
# ---------------------------------------------------------------------------
Say "=== GUIDE STEP 7: clone + pin ==="
cd ~
if (-not (Test-Path plantgpt/.git)) {
    git clone https://github.com/Blueturboguy07/plantgpt.git
}
cd plantgpt
$origin = git config --get remote.origin.url 2>$null
if ($origin) { $origin = $origin -replace '^git@github\.com:', 'https://github.com/' -replace '\.git$', '' }
$dirty = git status --porcelain 2>$null
if ($origin -ne "https://github.com/Blueturboguy07/plantgpt" -or $dirty) {
    Say "BUGFIX_LAB_INCONCLUSIVE: clone guard tripped (origin=$origin dirty=$dirty)"
    exit 2
}
git checkout 0e2cf7ae118beee65d9a07c1659de2b2ab4b85cd
Say "HEAD: $(git rev-parse HEAD)"
Say "cwd: $((Get-Location).Path)"

# ---------------------------------------------------------------------------
# GUIDE STEP 8 -- "Build PlantGPT" (plantgpt.ts v9), VERBATIM 3-line command,
# in the SAME session, which is exactly what the guide instructs:
#   npm.cmd install
#   $env:Path = "$env:USERPROFILE\.cargo\bin;$env:LOCALAPPDATA\Microsoft\WinGet\Links;$env:Path"
#   npm.cmd run tauri build
# The middle line is a PowerShell statement, not an external command -- a
# reader's terminal runs it inline in their own session, so it must run
# inline HERE too (not via Run-Bounded, which spawns a child process and
# could not mutate this process's own environment block).
# ---------------------------------------------------------------------------
Say "=== GUIDE STEP 8 line 1: npm.cmd install ==="
$npm = Run-Bounded -File "npm.cmd" -ArgList @('install') -TimeoutSeconds 600 -Tag "step8-npm-install"
Write-Host $npm.Output
Say "npm install exit: $($npm.ExitCode) timedOut: $($npm.TimedOut)"
if ($npm.ExitCode -ne 0) {
    Say "BUGFIX_LAB_INCONCLUSIVE: npm install failed, cannot reach the build"
    exit 2
}

Say "=== GUIDE STEP 8 line 2 (v9, PATH insurance): env:Path = ...cargo\bin;...WinGet\Links;... ==="
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:LOCALAPPDATA\Microsoft\WinGet\Links;$env:Path"
Say "cargo resolvable in THIS session right after the PATH insurance line: $([bool](Get-Command cargo -ErrorAction SilentlyContinue))"

Say "=== GUIDE STEP 8 line 3: npm.cmd run tauri build ==="
$build = Run-Bounded -File "npm.cmd" -ArgList @('run', 'tauri', 'build') -TimeoutSeconds 600 -Tag "step8-tauri-build"
Write-Host "----- step 8 build output -----"
Write-Host $build.Output
Write-Host "----- exit: $($build.ExitCode) timedOut: $($build.TimedOut) -----"

$needle = "failed to run command cargo metadata --no-deps --format-version 1: program not found"
$hit = $build.Output -match [regex]::Escape($needle)
$cargoStillOnDisk = Test-Path -LiteralPath $cargoExe

Say "reporters' error text present : $hit"
Say "cargo.exe on disk at verdict  : $cargoStillOnDisk ($cargoExe)"
Say "cargo resolvable in session   : $([bool](Get-Command cargo -ErrorAction SilentlyContinue))"

if ($hit -and $cargoStillOnDisk) {
    Say "The guide installed Rust in step 6 and built in the same window in step 8; the build could not see cargo."
    Say "BUGFIX_LAB_PRESENT"
    exit 1
}
elseif ($hit) {
    Say "BUGFIX_LAB_INCONCLUSIVE: error text present but cargo.exe is not on disk (different failure mode)"
    exit 2
}
else {
    Say "BUGFIX_LAB_ABSENT"
    exit 0
}
