# bugfix-lab oracle recipe for cluster:
#   plantgpt-windows-msvc-build-tools-missing-cascades-to-installer-not-found
#
# Runs the plantgpt guide's Windows branch steps 4-8 (lib/guides/plantgpt.ts, sourceCommit
# 0e2cf7ae118beee65d9a07c1659de2b2ab4b85cd) VERBATIM, non-interactively, to see whether the
# toolchain steps leave the machine with a working MSVC linker before the build runs, the same
# way a reporter's own machine would need to.
#
# FIX round 1 (2026-09-21): the guide gained a new step 4, "install-build-tools"
# (`winget install --id Microsoft.VisualStudio.2022.BuildTools ... --override "...
# Microsoft.VisualStudio.Workload.VCTools..."`), ahead of the pre-existing "Install Rust" step
# (now step 5). Both are pasted here verbatim from the fix branch's rendered guide output --
# see the comment directly above the first winget call below. Steps 0a/0b (hiding the runner's
# preinstalled MSVC toolset) and the pass/fail verdict at the bottom are UNCHANGED from the
# REPRODUCE/MINIMIZE stages.
#
# GH-hosted windows-latest runners ship with a full Visual Studio (incl. the VC++ toolset)
# preinstalled, unlike a typical reporter's fresh Windows machine, so step 0 here hides the
# preinstalled MSVC toolset (metadata-only directory rename -- reversible, nothing is deleted)
# before running the guide's own steps. This recreates the environment the report describes
# ("no separate manual MSVC Build Tools install"), it does not alter what the guide step itself
# does.
#
# Exit contract: 1 = bug PRESENT (MSVC-linker-missing note appears during the build), 0 = bug
# ABSENT (build finishes and the run-the-installer step finds an installer), 2 = oracle could
# not determine.

$ErrorActionPreference = 'Continue'
$logDir = "$env:RUNNER_TEMP\bugfix-lab"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$buildLog = "$logDir\build.log"

function Say($msg) { Write-Host "[oracle] $msg" }

Say "=== Step 0a: pre-existing VS/MSVC state (diagnostic) ==="
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    & $vswhere -all -products * -property installationPath
} else {
    Say "vswhere.exe not found at $vswhere"
}
$existingLinkers = Get-ChildItem -Path 'C:\Program Files*\Microsoft Visual Studio' -Recurse -Filter 'link.exe' -ErrorAction SilentlyContinue
Say "link.exe copies found before hiding: $($existingLinkers.Count)"
$existingLinkers | ForEach-Object { Say "  $($_.FullName)" }

Say "=== Step 0b: hide the preinstalled MSVC toolset (simulate a fresh machine) ==="
$msvcToolDirs = Get-ChildItem -Path 'C:\Program Files*\Microsoft Visual Studio' -Recurse -Directory -Filter 'MSVC' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\VC\\Tools\\MSVC$' }
foreach ($d in $msvcToolDirs) {
    $newName = "$($d.Name)_hidden_by_bugfix_lab"
    Say "renaming $($d.FullName) -> $newName"
    try {
        Rename-Item -Path $d.FullName -NewName $newName -ErrorAction Stop
    } catch {
        Say "  rename failed: $_"
    }
}
$remainingLinkers = Get-ChildItem -Path 'C:\Program Files*\Microsoft Visual Studio' -Recurse -Filter 'link.exe' -ErrorAction SilentlyContinue
Say "link.exe copies found after hiding VC\Tools\MSVC: $($remainingLinkers.Count)"
$remainingLinkers | ForEach-Object { Say "  $($_.FullName)" }

# The recursive VS-tree rename above only removes the copies MSVC-detection logic finds via
# vswhere/registry. Some runner images also carry an unrelated file also named link.exe
# (e.g. Git for Windows' coreutils `link.exe`, a hard-link utility, or an old ScopeCppSDK
# copy) directly on PATH, which a bare PATH search finds regardless of vswhere. Hide any of
# those too -- this is what determines what `Get-Command link.exe` / a bare `link.exe`
# invocation on the command line actually resolves to, same as on a real reporter machine
# with no MSVC linker at all.
$hiddenOnPath = @()
foreach ($dir in ($env:PATH -split ';' | Where-Object { $_ -ne '' })) {
    $candidate = Join-Path $dir 'link.exe'
    if (Test-Path $candidate -PathType Leaf) {
        $hiddenOnPath += $candidate
        Say "hiding PATH link.exe: $candidate"
        try {
            Rename-Item -Path $candidate -NewName 'link.exe.hidden_by_bugfix_lab' -ErrorAction Stop
        } catch {
            Say "  rename failed: $_"
        }
    }
}
Say "link.exe files hidden directly from PATH dirs: $($hiddenOnPath.Count)"

$linkOnPath = Get-Command link.exe -ErrorAction SilentlyContinue
Say "link.exe on PATH right now: $($linkOnPath -ne $null)"
if ($linkOnPath) { Say "  resolves to: $($linkOnPath.Source)" }

# --- FIX round 1: the guide (lib/guides/plantgpt.ts, version 9) now has a new
# Windows step, "install-build-tools", BEFORE "install-rust". Rendered verbatim
# via `npx tsx render-guide.mts plantgpt windows --json` against the fix
# branch of publik and pasted here unmodified (the harness hardcodes rendered
# steps rather than importing the guide module at runtime).
Say "=== Step 4 (guide, verbatim): Install the C++ build tools ==="
Say 'command: winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"'
# --accept-source-agreements/--accept-package-agreements only answer winget's OWN
# first-run agreement prompt so the command can run at all in a non-interactive shell --
# the same Y/N a first-time interactive user answers themselves, identical to how
# the pre-existing install-rust invocation below already handles it. Nothing else
# added or changed from the guide's own command text.
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" --accept-source-agreements --accept-package-agreements
Say "winget (build tools) exit code: $LASTEXITCODE"

Say "=== simulating 'reopen PowerShell' (install-rust's own new body text: 'Reopen PowerShell first so the build tools just installed are on PATH') ==="
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:PATH = "$machinePath;$userPath"
$linkAfterBuildTools = Get-Command link.exe -ErrorAction SilentlyContinue
Say "link.exe on PATH after build-tools install: $($linkAfterBuildTools -ne $null)"
if ($linkAfterBuildTools) { Say "  resolves to: $($linkAfterBuildTools.Source)" }
$vswhereAfter = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhereAfter) {
    Say "vswhere -products * -property installationPath (after build-tools install):"
    & $vswhereAfter -products * -property installationPath
}

Say "=== Step 5 (guide, verbatim): Install Rust ==="
Say "command: winget install --id Rustlang.Rustup -e --source winget"
# Same CI-only accommodation as above -- the guide's own command text is unchanged
# from before this fix round.
winget install --id Rustlang.Rustup -e --source winget --accept-source-agreements --accept-package-agreements
Say "winget (rustup) exit code: $LASTEXITCODE"

Say "=== simulating 'reopen PowerShell' again by reloading PATH from the registry ==="
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$env:PATH = "$machinePath;$userPath"
Say "cargo --version:"
cargo --version
Say "cargo --version exit code: $LASTEXITCODE"
Say "rustc --version:"
rustc --version
$linkAfterRust = Get-Command link.exe -ErrorAction SilentlyContinue
Say "link.exe on PATH after Rust install: $($linkAfterRust -ne $null)"
if ($linkAfterRust) { Say "  resolves to: $($linkAfterRust.Source)" }

Say "=== Step 6 (guide, verbatim): Get PlantGPT ==="
Set-Location ~
if (-not (Test-Path plantgpt/.git)) {
    git clone https://github.com/Blueturboguy07/plantgpt.git
}
Set-Location plantgpt
git checkout 0e2cf7ae118beee65d9a07c1659de2b2ab4b85cd

# FIX round 1 / cycle 2: cycle 1's CI run proved the build finishes ("Finished
# `release` profile", "Built application at: ...\plantgpt.exe") but leaves no
# installer, because tauri.conf.json's bundle.targets is ["app", "dmg"] --
# both macOS-only. The guide's build command now carries an explicit
# --bundles nsis override (same shape as the macOS branch's own --bundles app
# override), pasted here verbatim from the fix branch's rendered guide output.
Say "=== Step 7 (guide, verbatim): Build PlantGPT ==="
Say "command: npm.cmd install; npm.cmd run tauri build -- --bundles nsis"
npm.cmd install 2>&1 | Tee-Object -FilePath $buildLog
npm.cmd run tauri build -- --bundles nsis 2>&1 | Tee-Object -FilePath $buildLog -Append
$buildExit = $LASTEXITCODE
Say "build exit code: $buildExit"

Say "=== Step 8 (guide, verbatim): Run the installer ==="
$installerErr = $null
$setup = Get-ChildItem src-tauri\target\release\bundle\nsis -Filter *-setup.exe -ErrorVariable installerErr -ErrorAction SilentlyContinue | Select-Object -First 1
if ($setup) {
    Say "INSTALLER_FOUND: $($setup.FullName)"
} else {
    Say "INSTALLER_NOT_FOUND. Native error: $installerErr"
}

$log = Get-Content $buildLog -Raw -ErrorAction SilentlyContinue
$msvcNoteHit = $log -match 'Visual Studio 2017 or later, or Build Tools for Visual Studio'
$linkerHit = $log -match 'link\.exe'
$compileErrHit = $log -match 'error: could not compile'

Say "MSVC note present in build log: $msvcNoteHit"
Say "link.exe mention present in build log: $linkerHit"
Say "'could not compile' present in build log: $compileErrHit"

if ($msvcNoteHit -or ($linkerHit -and $compileErrHit)) {
    Say "BUGFIX_LAB_PRESENT"
    exit 1
} elseif ($setup -and $buildExit -eq 0) {
    Say "BUGFIX_LAB_ABSENT"
    exit 0
} else {
    Say "BUGFIX_LAB_INDETERMINATE"
    exit 2
}
