<#
    flash\flash.cmd [-Port COM5] [-Full] [-Erase] [-Baud 115200]
                    [-VerifyOnly] [-DryRun] [-Esptool <path>]

Flashes the DC35 CNet badge firmware in this folder's parent onto a badge over
USB - but only after checking it is the release that was signed:

  1. manifest.json.sig is a valid signature over manifest.json under one of
     the public keys in keys\ (the same keys every badge has built in);
  2. the firmware image named in the manifest is here, with exactly the size
     and SHA-256 the signed manifest gives.

If either check fails, nothing is written. The checks need nothing installed:
they use Windows' own cryptography. Writing the flash needs esptool.

The badge KEEPS its name, Wi-Fi details, settings, scores and CTF progress:
only the firmware and the boot selector are written. -Erase wipes everything.

This file is published by the badge's release tooling; edits here are lost on
the next release.
#>
[CmdletBinding()]
param(
    [string]$Port,
    [int]$Baud = 921600,
    [switch]$Full,
    [switch]$Erase,
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [string]$Esptool,
    # Anything that matches no parameter lands here, so a typo is reported.
    # Without it, `powershell -File` exits silently on a bad argument.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Unrecognised
)

$ErrorActionPreference = 'Stop'
$kit = $PSScriptRoot
$top = Split-Path -Parent $kit

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Fail([string]$t) { Say $t 'Red'; exit 1 }

if ($Unrecognised) {
    Say ("Unrecognised argument(s): " + ($Unrecognised -join ' ')) 'Red'
    Say ""
    Say "Valid arguments:" 'Yellow'
    Say "  -Port COM5        which badge (found automatically if only one is plugged in)"
    Say "  -Baud 115200      slower, for a flaky cable (default 921600)"
    Say "  -Full             also write the bootloader and partition table"
    Say "  -Erase            wipe the badge completely first; implies -Full"
    Say "  -VerifyOnly       check the files and stop"
    Say "  -DryRun           check the files, print the esptool command, write nothing"
    Say "  -Esptool <path>   use this esptool"
    Say "Switches take no space after the dash: -Full, not - Full." 'DarkGray'
    exit 2
}

# --- 1. the signature --------------------------------------------------------
# ECDSA P-256 over SHA-256, checked with CNG so no openssl or Python is needed.

function Read-PublicKey([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $b64 = ($text -replace '-----[A-Z ]+-----', '') -replace '\s', ''
    $der = [Convert]::FromBase64String($b64)
    # SubjectPublicKeyInfo for an uncompressed P-256 point is always these
    # 26 bytes, then 0x04, then X and Y.
    $prefix = '3059301306072a8648ce3d020106082a8648ce3d030107034200'
    $head = -join ($der[0..25] | ForEach-Object { $_.ToString('x2') })
    if ($der.Length -ne 91 -or $head -ne $prefix -or $der[26] -ne 4) {
        throw "$path is not a P-256 public key"
    }
    # BCRYPT_ECCKEY_BLOB: magic 'ECS1', key length 32, then X and Y.
    $blob = New-Object byte[] 72
    [Array]::Copy([byte[]](0x45, 0x43, 0x53, 0x31, 0x20, 0, 0, 0), 0, $blob, 0, 8)
    [Array]::Copy($der, 27, $blob, 8, 64)
    $key = [Security.Cryptography.CngKey]::Import(
        $blob, [Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
    $ecdsa = New-Object Security.Cryptography.ECDsaCng $key
    $ecdsa.HashAlgorithm = [Security.Cryptography.CngAlgorithm]::Sha256
    return $ecdsa
}

# The signature file is DER (SEQUENCE of two INTEGERs); CNG wants r and s as
# two 32-byte big-endian halves.
function Convert-Signature([byte[]]$d) {
    if ($d.Length -lt 8 -or $d[0] -ne 0x30) { throw "not a DER ECDSA signature" }
    $i = 2
    if ($d[1] -band 0x80) { $i = 2 + ($d[1] -band 0x7f) }
    $out = New-Object byte[] 64
    foreach ($half in 0, 1) {
        if ($d[$i] -ne 0x02) { throw "not a DER ECDSA signature" }
        $len = [int]$d[$i + 1]
        $start = $i + 2
        $end = $start + $len
        while ($len -gt 1 -and $d[$start] -eq 0) { $start++; $len-- }
        if ($len -gt 32) { throw "signature value too long for P-256" }
        [Array]::Copy($d, $start, $out, $half * 32 + 32 - $len, $len)
        $i = $end
    }
    return $out
}

$manifestPath = Join-Path $top 'manifest.json'
$sigPath = Join-Path $top 'manifest.json.sig'
foreach ($p in $manifestPath, $sigPath) {
    if (-not (Test-Path $p)) {
        Fail ("Missing $p. Keep the flash folder inside the downloaded repository " +
              "folder, next to manifest.json.")
    }
}
$keyFiles = @(Get-ChildItem (Join-Path $kit 'keys\*.pem') -ErrorAction SilentlyContinue)
if ($keyFiles.Count -eq 0) { Fail "No public keys in $kit\keys - the kit is incomplete." }

$manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
$sig = Convert-Signature ([IO.File]::ReadAllBytes($sigPath))
$signer = $null
foreach ($k in $keyFiles) {
    $ecdsa = Read-PublicKey $k.FullName
    try {
        if ($ecdsa.VerifyData($manifestBytes, $sig)) { $signer = $k.BaseName; break }
    } finally { $ecdsa.Dispose() }
}
if (-not $signer) {
    Say "FAIL: manifest.json is not signed by any key in keys\. Nothing was written." 'Red'
    Say ("If you downloaded the files one at a time within a few minutes of a " +
         "release, they can be from two different releases: GitHub caches each " +
         "file separately for five minutes. Download the whole repository as a " +
         "ZIP and try again. Otherwise, do not flash these files.") 'Yellow'
    exit 1
}
Say ("signature   OK, signed with the '$signer' key") 'Green'

# --- 2. the image --------------------------------------------------------------
$manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
$version = $manifest.version
$build = $manifest.builds.badge
if (-not $build) { Fail "The manifest has no firmware for this badge." }
$imageName = ($build.url -split '/')[-1]
$image = Join-Path $top $imageName
if (-not (Test-Path $image)) { Fail "The manifest names $imageName, which is not in $top." }
$len = (Get-Item $image).Length
$hash = (Get-FileHash $image -Algorithm SHA256).Hash.ToLower()
if ($len -ne [int64]$build.size -or $hash -ne $build.sha256.ToLower()) {
    Say "FAIL: $imageName is not the image the signed manifest describes. Nothing was written." 'Red'
    Say ("  manifest {0} bytes, {1}" -f $build.size, $build.sha256)
    Say ("  file     {0} bytes, {1}" -f $len, $hash)
    exit 1
}
Say ("image       OK, $imageName is firmware $version, {0:N0} bytes, SHA-256 matches" -f $len) 'Green'

if ($VerifyOnly) {
    Say "-VerifyOnly: the files check out. Nothing was written." 'Cyan'
    exit 0
}

# --- 3. esptool ----------------------------------------------------------------
$writeBoot = $Full.IsPresent -or $Erase.IsPresent
if ($Erase -and -not $Full) {
    Say ("-Erase implies -Full: wiping the chip removes the bootloader and " +
         "partition table too, so they are written back.") 'Yellow'
}
$bootApp0 = Join-Path $kit 'boot_app0.bin'
$needed = @($bootApp0)
if ($writeBoot) { $needed += (Join-Path $kit 'bootloader.bin'), (Join-Path $kit 'partitions.bin') }
foreach ($f in $needed) { if (-not (Test-Path $f)) { Fail "Missing $f - the kit is incomplete." } }

function Find-Esptool {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($Esptool) {
        if (-not (Test-Path $Esptool)) { Fail "-Esptool: no such file $Esptool" }
        if ($Esptool -like '*.py') {
            if (-not $py) { Fail "-Esptool names a .py file, and python was not found." }
            return , @($py.Source, $Esptool)
        }
        return , @((Resolve-Path $Esptool).Path)
    }
    # Espressif's Windows download, unzipped into this folder.
    $here = Get-ChildItem $kit -Recurse -Depth 2 -Filter 'esptool.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
    if ($here) { return , @($here.FullName) }
    foreach ($n in 'esptool.exe', 'esptool') {
        $c = Get-Command $n -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } |
             Select-Object -First 1
        if ($c) { return , @($c.Source) }
    }
    # The copy the Arduino IDE installs with the ESP32 core, newest first.
    $ard = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Arduino15\packages\esp32\tools\esptool_py\*\esptool.exe') `
           -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($ard) { return , @($ard.FullName) }
    if ($py) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $py.Source -m esptool version *> $null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $old
        if ($ok) { return , @($py.Source, '-m', 'esptool') }
    }
    return $null
}

$tool = Find-Esptool
if (-not $tool) {
    Say "esptool was not found, so nothing was written. Any one of these works:" 'Red'
    Say "  - download the Windows build from https://github.com/espressif/esptool/releases"
    Say "    and unzip it into this folder ($kit)"
    Say "  - or, with Python installed:  pip install esptool"
    Say "  - or install the Arduino IDE with the esp32 boards package"
    Say "The files themselves checked out; run with -VerifyOnly to check without esptool." 'DarkGray'
    exit 1
}
$exe = $tool[0]
$pre = @()
if ($tool.Count -gt 1) { $pre = $tool[1..($tool.Count - 1)] }

# esptool 5 spells its commands with dashes (write-flash); 4 with underscores.
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$verText = (& $exe @pre version 2>&1 | Out-String)
$ErrorActionPreference = $old
$major = 5
if ($verText -match 'v?(\d+)\.(\d+)') { $major = [int]$Matches[1] }
Say ("esptool     {0} (version {1})" -f (($tool) -join ' '), $major) 'DarkGray'

# --- 4. which badge --------------------------------------------------------------
if (-not $Port) {
    $found = @(Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%(COM%'" -ErrorAction SilentlyContinue |
               Where-Object { $_.PNPDeviceID -match '^(USB|FTDIBUS)\\' } |
               ForEach-Object {
                   if ($_.Name -match '\((COM\d+)\)') { [pscustomobject]@{ Port = $Matches[1]; Name = $_.Name } }
               })
    if ($found.Count -eq 0) {
        Fail ("No USB serial port found. Is the badge plugged in and switched on, with a " +
              "cable that carries data (some are charge-only)? If Device Manager shows it " +
              "under 'Other devices', it needs the driver for its USB chip (CP210x or CH340). " +
              "Or name the port with -Port.")
    }
    if ($found.Count -gt 1) {
        Say "More than one USB serial port is plugged in:" 'Yellow'
        $found | ForEach-Object { Say ("  {0}  {1}" -f $_.Port, $_.Name) }
        Fail "Say which one is the badge, for example:  flash\flash.cmd -Port $($found[0].Port)"
    }
    $Port = $found[0].Port
    Say ("port        $Port, {0}" -f $found[0].Name) 'DarkGray'
}

# --- 5. write --------------------------------------------------------------------
# boot_app0.bin at 0xe000 is NOT optional. A badge that has taken an update
# over Wi-Fi runs from the second app slot; writing the first slot without
# resetting the selector leaves it booting the OLD firmware.
if ($major -ge 5) {
    $a = @('--chip', 'esp32', '--port', $Port, '--baud', "$Baud",
           '--before', 'default-reset', '--after', 'hard-reset', 'write-flash')
    $keep = @('-z', '--flash-mode', 'keep', '--flash-freq', 'keep', '--flash-size', 'keep')
} else {
    $a = @('--chip', 'esp32', '--port', $Port, '--baud', "$Baud",
           '--before', 'default_reset', '--after', 'hard_reset', 'write_flash')
    $keep = @('-z', '--flash_mode', 'keep', '--flash_freq', 'keep', '--flash_size', 'keep')
}
if ($Erase) {
    Say ("-Erase: the badge will forget its name, Wi-Fi details, settings, " +
         "scores and CTF progress.") 'Yellow'
    $a += '--erase-all'
}
$a += $keep
if ($writeBoot) {
    $a += @('0x1000', (Join-Path $kit 'bootloader.bin'), '0x8000', (Join-Path $kit 'partitions.bin'))
}
$a += @('0xe000', $bootApp0, '0x10000', $image)

if ($DryRun) {
    Say "-DryRun: the files check out. Nothing was written. The command would be:" 'Yellow'
    Say (((@($exe) + $pre + $a) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    exit 0
}

Say "writing firmware $version to $Port" 'Cyan'
& $exe @pre @a
if ($LASTEXITCODE -ne 0) {
    Say ("esptool failed. If it could not connect, hold the badge's BOOT button while " +
         "it says 'Connecting...', or try -Baud 115200 or another cable.") 'Red'
    exit 1
}
Say "Done: the badge is restarting on firmware $version." 'Green'
