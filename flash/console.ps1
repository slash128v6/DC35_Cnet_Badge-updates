<#
    flash\console.cmd [-Port COM5] [-NoReset] [-Echo] [-Command "<line>;<line>" [-Wait 3]]

Opens the badge's serial console. What the badge prints appears here, and what
you type goes to the badge; Enter sends the line. Type HELP for the badge's
commands, or DIVE for the CTF's text adventure. Ctrl+] or Ctrl+C quits.

Nothing to install: it uses Windows' own serial port support. It restarts the
badge as it connects, as the Arduino IDE's Serial Monitor and PuTTY do: what
the badge printed while nobody was listening can otherwise come back from the
CP210x USB driver as the same text repeated over and over. Your settings, CTF
progress and place in The Deep are kept. If the badge is unplugged, the
console waits for it to come back.

  -Port COM5       which badge (found automatically if only one is plugged in)
  -NoReset         connect without restarting the badge
  -Echo            show what you type; for firmware 1.0.33 and older, which
                   don't echo it back themselves
  -Command <...>   send these lines (separated by ;) once the badge has
                   started, show the replies for -Wait seconds, and exit:
                   console.cmd -Command "DIVE;LOOK;SURFACE"
  -Baud 115200     the badge's speed; there is no reason to change it

This file is published by the badge's release tooling; edits here are lost on
the next release.
#>
[CmdletBinding()]
param(
    [string]$Port,
    [int]$Baud = 115200,
    [switch]$NoReset,
    [switch]$Echo,
    [string[]]$Command,
    [int]$Wait = 3,
    # Anything that matches no parameter lands here, so a typo is reported.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Unrecognised
)

$ErrorActionPreference = 'Stop'

function Say([string]$t, [string]$c = 'DarkGray') { Write-Host $t -ForegroundColor $c }
function Fail([string]$t) { Say $t 'Red'; exit 1 }

if ($Unrecognised) {
    Say ("Unrecognised argument(s): " + ($Unrecognised -join ' ')) 'Red'
    Say "Valid arguments:" 'Yellow'
    Say "  -Port COM5        which badge (found automatically if only one is plugged in)" 'Gray'
    Say "  -NoReset          connect without restarting the badge" 'Gray'
    Say "  -Echo             show what you type, for firmware 1.0.33 and older" 'Gray'
    Say "  -Command <lines>  send these lines, show the replies, and exit" 'Gray'
    Say "  -Wait 3           with -Command, how many seconds to show replies for" 'Gray'
    exit 2
}

# --- which badge ---------------------------------------------------------------
if (-not $Port) {
    $found = @(Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%(COM%'" -ErrorAction SilentlyContinue |
               Where-Object { $_.PNPDeviceID -match '^(USB|FTDIBUS)\\' } |
               ForEach-Object {
                   if ($_.Name -match '\((COM\d+)\)') { [pscustomobject]@{ Port = $Matches[1]; Name = $_.Name } }
               })
    if ($found.Count -eq 0) {
        Fail ("No USB serial port found. Is the badge plugged in and switched on, with a " +
              "cable that carries data (some are charge-only)? If Device Manager shows it " +
              "under 'Other devices', it needs the driver for its USB chip (CP210x or CH340): " +
              "see flash\README.md. Or name the port with -Port.")
    }
    if ($found.Count -gt 1) {
        Say "More than one USB serial port is plugged in:" 'Yellow'
        $found | ForEach-Object { Say ("  {0}  {1}" -f $_.Port, $_.Name) 'Gray' }
        Fail "Say which one is the badge, for example:  flash\console.cmd -Port $($found[0].Port)"
    }
    $Port = $found[0].Port
}

# --- the port ------------------------------------------------------------------
# On the badge's board DTR drives the boot pin and RTS the reset pin. Both
# stay low, except for the one RTS pulse that restarts the badge.
function Open-Badge {
    $p = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
    $p.DtrEnable = $false
    $p.RtsEnable = $false
    $p.ReadTimeout = 20
    $p.Open()
    if (-not $NoReset) {
        $p.RtsEnable = $true; Start-Sleep -Milliseconds 100; $p.RtsEnable = $false
        # Anything that arrives in the first moments is stale: drop it.
        $junk = New-Object byte[] 4096
        $end = (Get-Date).AddMilliseconds(300)
        while ((Get-Date) -lt $end) {
            try { $null = $p.BaseStream.Read($junk, 0, $junk.Length) } catch [TimeoutException] {}
        }
    }
    $p
}

# One decoder for the session, so a character split across two reads still
# comes out whole. The last few hundred characters are kept, for -Command to
# see when the badge has finished starting.
$script:dec = [Text.Encoding]::UTF8.GetDecoder()
$script:buf = New-Object byte[] 4096
$script:chars = New-Object char[] 4200
$script:recent = ''
function Pump {
    try { $n = $sp.BaseStream.Read($script:buf, 0, $script:buf.Length) }
    catch [TimeoutException] { return 0 }
    $c = $script:dec.GetChars($script:buf, 0, $n, $script:chars, 0)
    $t = New-Object string ($script:chars, 0, $c)
    Show $t
    $script:recent = ($script:recent + $t)
    if ($script:recent.Length -gt 400) { $script:recent = $script:recent.Substring($script:recent.Length - 400) }
    $n
}

if (-not $NoReset) { Say "[console] restarting the badge on $Port so the connection starts clean (-NoReset to skip)" }
try { $sp = Open-Badge }
catch {
    $why = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
    Fail ("Couldn't open ${Port}: $why`nIs something else using it - Arduino's Serial " +
          "Monitor, PuTTY, a flash in progress, or another console window?")
}

# Text from the badge: NULs are line noise from the moment the port opens.
function Show([string]$t) { [Console]::Write(($t -replace "`0", '')) }

# --- one-shot: -Command ----------------------------------------------------------
if ($Command) {
    try {
        if (-not $NoReset) {
            # The badge reads commands once it has started: wait for that.
            $end = (Get-Date).AddSeconds(20)
            while ((Get-Date) -lt $end -and -not $script:recent.Contains('setup done')) { $null = Pump }
        }
        # From cmd.exe the lines arrive as one argument: ; separates them.
        foreach ($line in @($Command | ForEach-Object { $_ -split ';' } | Where-Object { $_.Trim() })) {
            $sp.Write("$line`r`n")
            $end = (Get-Date).AddMilliseconds(400)
            while ((Get-Date) -lt $end) { $null = Pump }
        }
        $end = (Get-Date).AddSeconds($Wait)
        while ((Get-Date) -lt $end) { $null = Pump }
        [Console]::WriteLine()
    } finally { $sp.Close() }
    exit 0
}

# --- interactive -----------------------------------------------------------------
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$oldCtrlC = [Console]::TreatControlCAsInput
[Console]::TreatControlCAsInput = $true
Say "[console] $Port at $Baud. HELP lists the badge's commands, DIVE starts The Deep. Ctrl+] or Ctrl+C quits."

# Enter sends CR LF: firmware 1.0.34 and later take either, and older firmware
# needs the LF.
function Send-Key($k) {
    $ch = $k.KeyChar
    if ($k.Key -eq 'Enter') {
        $sp.Write("`r`n"); if ($Echo) { [Console]::Write("`r`n") }
    } elseif ($k.Key -eq 'Backspace') {
        $sp.Write([string][char]8); if ($Echo) { [Console]::Write("`b `b") }
    } elseif ($ch -ge ' ' -or $ch -eq "`t") {
        $sp.Write([string]$ch); if ($Echo) { [Console]::Write($(if ($ch -eq "`t") { ' ' } else { $ch })) }
    }
    # Arrow keys, function keys and the like have no character: not sent.
}

function Is-Quit($k) {
    ($k.KeyChar -eq [char]3) -or ($k.KeyChar -eq [char]0x1d) -or
    (($k.Modifiers -band [ConsoleModifiers]::Control) -and ($k.Key -eq 'C' -or $k.Key -eq 'Oem6'))
}

$quit = $false
try {
    while (-not $quit) {
        $busy = $false
        try {
            if ((Pump) -gt 0) { $busy = $true }
        } catch {
            # Unplugged, or the driver went away: wait for the badge to return.
            try { $sp.Close() } catch {}
            Say "`n[console] lost $Port - waiting for the badge to come back (Ctrl+C quits)" 'Yellow'
            while (-not $quit) {
                if ([Console]::KeyAvailable -and (Is-Quit ([Console]::ReadKey($true)))) { $quit = $true; break }
                if ([IO.Ports.SerialPort]::GetPortNames() -contains $Port) {
                    try { $sp = Open-Badge; Say "[console] $Port is back" 'Yellow'; break } catch {}
                }
                Start-Sleep -Milliseconds 500
            }
            continue
        }
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if (Is-Quit $k) { $quit = $true; break }
            try { Send-Key $k } catch {}
            $busy = $true
        }
        # No sleep needed: Pump waits up to 20 ms for the badge when it's quiet.
    }
} finally {
    try { $sp.Close() } catch {}
    [Console]::TreatControlCAsInput = $oldCtrlC
    Say "`n[console] closed $Port"
}
