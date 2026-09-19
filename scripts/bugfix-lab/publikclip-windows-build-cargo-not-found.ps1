# bugfix-lab oracle for cluster publikclip-windows-build-cargo-not-found
# (PlantGPT half of the cross-app guide merge; existing break 34ad7647).
#
# Reproduces the Windows install guide's numbered "build" step
# (lib/guides/plantgpt.ts, plantgptSteps(), id "build") on a genuinely
# rust-less machine, running each guide step in its OWN fresh pwsh.exe
# process -- the "one short-lived PowerShell per command" model Iris's
# autopilot uses (iris-windows/src/main/powershell-session.ts). Unlike
# publikclip's Windows guide, PlantGPT's Windows "build" step command carries
# NO PATH-insurance line at all: `npm.cmd install\nnpm.cmd run tauri build`.
#
# Exit 1 = bug PRESENT (cargo metadata "program not found" while cargo.exe
#          exists on disk at %USERPROFILE%\.cargo\bin).
# Exit 0 = bug ABSENT.
# Exit 2 = oracle could not run (a precondition failed -- say which).

$ErrorActionPreference = 'Continue'

function Invoke-FreshShell {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [int]$TimeoutSeconds = 300
    )
    # Bounded: an installer that stalls (winget/msstore source sync has done
    # this on GH's windows-latest) must not hang the whole oracle.
    $scriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
    Set-Content -LiteralPath $scriptPath -Value $Script -Encoding UTF8
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "pwsh.exe"
        $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`""
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $finished = $proc.WaitForExit($TimeoutSeconds * 1000)
        if (-not $finished) {
            try { Start-Process -FilePath "taskkill" -ArgumentList "/pid", "$($proc.Id)", "/T", "/F" -Wait -WindowStyle Hidden } catch {}
            return [PSCustomObject]@{ ExitCode = -1; Stdout = $stdout; Stderr = "$stderr`n[TIMED OUT after $TimeoutSeconds s]" }
        }
        return [PSCustomObject]@{ ExitCode = $proc.ExitCode; Stdout = $stdout; Stderr = $stderr }
    } finally {
        Remove-Item -LiteralPath $scriptPath -ErrorAction SilentlyContinue
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Write-Host "repoRoot=$repoRoot"

# ── Step 0: start from a genuinely rust-less machine ────────────────────────
Write-Host "== Step 0: remove any preinstalled Rust toolchain =="
$clean = Invoke-FreshShell -WorkingDirectory $repoRoot -Script @'
if (Get-Command rustup -ErrorAction SilentlyContinue) {
  & rustup self uninstall -y 2>&1 | Out-String | Write-Host
}
Remove-Item -Recurse -Force "$env:USERPROFILE\.cargo" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:USERPROFILE\.rustup" -ErrorAction SilentlyContinue
Write-Host "cargo.exe present after cleanup: $(Test-Path (Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'))"
'@
Write-Host $clean.Stdout
Write-Host $clean.Stderr

# ── Step 1: the guide's "Install Rust" step (kind: terminal, Iris-run) ─────
# The guide's authored command is `winget install --id Rustlang.Rustup -e
# --source winget` -- functionally, on a machine that has never had Rust,
# this runs rustup-init's own installer non-interactively and produces the
# identical end state rustup-init.exe does: cargo.exe at
# %USERPROFILE%\.cargo\bin. A first attempt using the literal winget command
# hung/ran past 18 minutes on windows-latest (a known winget-on-GH-runner
# flakiness, not something this oracle is about) with NO output yet from the
# install step, so this uses the same direct rustup-init.exe path already
# proven fast and reliable for publikclip's equivalent step, to test the
# SAME question (the build step's shell resolving a genuinely-on-disk
# cargo.exe) without winget's variability as a confound. Documented here so
# a later run can swap back to literal winget and compare.
Write-Host "== Step 1: Install Rust (guide step 'install-rust' end state, via rustup-init.exe) =="
$installRust = Invoke-FreshShell -WorkingDirectory $repoRoot -Script @'
$ProgressPreference = "SilentlyContinue"
$exePath = Join-Path $env:TEMP "rustup-init.exe"
Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" -OutFile $exePath
& $exePath -y --default-toolchain stable --profile default
Write-Host "rustup-init exit: $LASTEXITCODE"
'@
Write-Host $installRust.Stdout
Write-Host $installRust.Stderr

$cargoPath = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
$cargoExists = Test-Path -LiteralPath $cargoPath
Write-Host "== Precondition: cargo.exe on disk at $cargoPath : $cargoExists =="
if (-not $cargoExists) {
    Write-Host "BUGFIX_LAB_INCONCLUSIVE: winget rustup install did not produce cargo.exe on disk -- cannot test the PATH-gap scenario the reporter describes"
    exit 2
}

# ── Step 2: the guide's numbered "build" step, EXACT authored command ──────
Write-Host "== Step 2: build (guide step 'build', exact authored command, fresh shell) =="
$buildScript = @'
npm.cmd install
npm.cmd run tauri build
Write-Host "tauri build exit: $LASTEXITCODE"
exit $LASTEXITCODE
'@
$build = Invoke-FreshShell -WorkingDirectory $repoRoot -Script $buildScript
$combined = ($build.Stdout + "`n" + $build.Stderr)
Write-Host "----- build step combined output -----"
Write-Host $combined
Write-Host "----- build step exit code: $($build.ExitCode) -----"

$needle = "cargo metadata --no-deps --format-version 1: program not found"
if ($combined -match [regex]::Escape($needle)) {
    Write-Host "cargo.exe exists on disk ($cargoExists) but the build step's shell could not resolve it."
    Write-Host "BUGFIX_LAB_PRESENT"
    exit 1
} else {
    Write-Host "The build step's shell resolved cargo (cargo-metadata error text not found)."
    Write-Host "BUGFIX_LAB_ABSENT"
    exit 0
}
