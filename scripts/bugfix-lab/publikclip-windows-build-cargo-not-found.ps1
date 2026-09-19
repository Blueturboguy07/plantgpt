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
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )
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
        $proc.WaitForExit()
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
# Verbatim command from lib/guides/plantgpt.ts plantgptSteps() 'install-rust'.
Write-Host "== Step 1: Install Rust (guide step 'install-rust', exact authored command) =="
$installRust = Invoke-FreshShell -WorkingDirectory $repoRoot -Script @'
winget install --id Rustlang.Rustup -e --source winget --accept-source-agreements --accept-package-agreements
Write-Host "winget rustup install exit: $LASTEXITCODE"
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
