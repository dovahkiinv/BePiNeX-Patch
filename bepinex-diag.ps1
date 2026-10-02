<#
.SYNOPSIS
  Diagnoza BepInEx 6 (Unity IL2CPP) po aktualizacji gry.

.DESCRIPTION
  Pokazuje: wersje metadata IL2CPP, wersje Unity, stan folderow interop/unity-libs/plugins
  i wersje Cpp2IL zapakowana w BepInEx. Wklej caly output do rozmowy / issue.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\bepinex-diag.ps1
  powershell -ExecutionPolicy Bypass -File .\bepinex-diag.ps1 -GameRoot "D:\Steam\steamapps\common\ASKA"
#>
[CmdletBinding()]
param(
    [string]$GameRoot = (Get-Location).Path,
    [int]$MaxMetadataResults = 5
)

$ErrorActionPreference = 'Continue'
$script:Limits = @(23, 106)   # zakres wspierany przez BepInEx BE <= be.788 (Cpp2IL development.1452)

function Write-H { param([string]$t) Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }

function Get-PEMachine {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $hdr = New-Object byte[] 1024
            $read = $fs.Read($hdr, 0, 1024)
            if ($read -lt 64) { return $null }
            if ($hdr[0] -ne 0x4D -or $hdr[1] -ne 0x5A) { return $null }   # 'MZ'
            $peOff = [BitConverter]::ToInt32($hdr, 0x3C)
            if ($peOff + 6 -gt $read) { return $null }
            if ($hdr[$peOff] -ne 0x50 -or $hdr[$peOff + 1] -ne 0x45) { return $null }  # 'PE'
            return [BitConverter]::ToUInt16($hdr, $peOff + 4)
        } finally { $fs.Dispose() }
    } catch { return $null }
}

function Test-DoorstopBaselibPatch {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $pattern = [System.Text.Encoding]::Unicode.GetBytes("baselib.dll")
        for ($i = 0; $i -le ($bytes.Length - $pattern.Length); $i++) {
            $match = $true
            for ($j = 0; $j -lt $pattern.Length; $j++) {
                if ($bytes[$i + $j] -ne $pattern[$j]) { $match = $false; break }
            }
            if ($match) { return $true }
        }
    } catch {}
    return $false
}

function Get-MachineName {
    param($m)
    if ($null -eq $m) { return 'nie odczytano' }
    switch ($m) {
        0x14c  { return 'x86 (32-bit)' }
        0x8664 { return 'x64 (64-bit)' }
        0xAA64 { return 'ARM64' }
        default { return ('nieznany 0x{0:X}' -f $m) }
    }
}

# Lista DLL-i z tablicy importow PE (bez pelnego parsera - skan ASCII w sekcji naglowkow/imports)
function Get-PEImportedDlls {
    param([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $txt = [System.Text.Encoding]::ASCII.GetString($bytes)
        $found = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in [regex]::Matches($txt, '[A-Za-z0-9_\-\.]{2,40}\.dll')) {
            [void]$found.Add($m.Value.ToLowerInvariant())
        }
        return $found
    } catch { return @() }
}

function Get-GameAssembly {
    param([string]$Root)
    $names = @('GameAssembly.dll','GameAssembly.so','GameAssembly.dylib','UnityFramework')
    foreach ($n in $names) {
        $hit = Get-ChildItem -LiteralPath $Root -Filter $n -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

function Get-MetadataInfo {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $buf = New-Object byte[] 8
            if ($fs.Read($buf, 0, 8) -lt 8) { return $null }
            $sanity  = [BitConverter]::ToUInt32($buf, 0)
            $hex     = [BitConverter]::ToString($buf, 0, 4)
            $version = [BitConverter]::ToInt32($buf, 4)
            return [pscustomobject]@{ Path = $Path; Sanity = $sanity; Hex = $hex; Version = $version }
        } finally { $fs.Dispose() }
    } catch { return $null }
}

function Get-UnityVersion {
    param([string]$Dir)
    $f = Get-ChildItem -LiteralPath $Dir -Filter 'globalgamemanagers' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) {
        $f = Get-ChildItem -LiteralPath $Dir -Filter 'data.unity3d' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $f) { return $null }
    try {
        $fs = [System.IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
        try {
            $len = [Math]::Min(262144, $fs.Length)
            $buf = New-Object byte[] $len
            [void]$fs.Read($buf, 0, $len)
        } finally { $fs.Dispose() }
        $txt = [System.Text.Encoding]::ASCII.GetString($buf)
        $m = [regex]::Match($txt, '(20[0-9]{2}|6000)\.[0-9]+\.[0-9]+[a-z]?\d*')
        if ($m.Success) { return $m.Value }
    } catch { }
    return $null
}

function Get-Cpp2IlSupport {
    param([string]$Dll)
    # Wyciaga komunikat "We support 23-106, got " z LibCpp2IL.dll (string w heapie #US, UTF-16).
    # Stringi w #US nie sa wyrównane do parzystego offsetu, wiec dopasowujemy wyrównanie.
    try {
        $bytes  = [System.IO.File]::ReadAllBytes($Dll)
        $needle = [System.Text.Encoding]::Unicode.GetBytes('We support ')
        $found  = -1
        for ($i = 0; $i -lt ($bytes.Length - $needle.Length); $i++) {
            $ok = $true
            for ($j = 0; $j -lt $needle.Length; $j++) {
                if ($bytes[$i + $j] -ne $needle[$j]) { $ok = $false; break }
            }
            if ($ok) { $found = $i; break }
        }
        if ($found -lt 0) { return $null }

        foreach ($k in @($found, ($found + 1), ($found - 1))) {
            if ($k -lt 0 -or $k + 4 -ge $bytes.Length) { continue }
            $len = [Math]::Min(240, $bytes.Length - $k)
            $s = [System.Text.Encoding]::Unicode.GetString($bytes, $k, $len)
            $z = $s.IndexOf([char]0)
            if ($z -lt 0) { $z = $s.Length }
            $txt = $s.Substring(0, $z)
            $m = [regex]::Match($txt, 'We support\s+[0-9]+\s*-\s*[0-9]+')
            if ($m.Success) { return $m.Value.Trim() }
        }
    } catch { }
    return $null
}

Write-H "1. Lokalizacja"
Write-Host ("GameRoot : {0}" -f $GameRoot)
Write-Host ("Istnieje : {0}" -f (Test-Path -LiteralPath $GameRoot))

# --- 1b. Dlaczego BepInEx moze nie startowac (brak LogOutput.log) ---
Write-H "1b. Boot: czy Doorstop w ogole ma szanse sie zaladowac"
$proxyNames = @('winhttp.dll','version.dll','xinput1_3.dll','xinput1_4.dll','xinput9_1_0.dll','dxgi.dll','d3d11.dll','winmm.dll','dbghelp.dll')
$present = @()
foreach ($pn in $proxyNames) {
    $pp = Join-Path $GameRoot $pn
    if (Test-Path -LiteralPath $pp) { $present += $pn }
}
if ($present.Count -eq 0) {
    Write-Host "BRAK jakiegokolwiek proxy DLL (winhttp.dll / version.dll / ...) w katalogu gry -> Doorstop nie ma jak sie zaladowac." -ForegroundColor Red
} else {
    foreach ($pn in $present) {
        $pp = Join-Path $GameRoot $pn
        $isPatched = Test-DoorstopBaselibPatch -Path $pp
        $patchStatus = if ($isPatched) { " [Unity 6 / baselib hook PATCH: OK]" } else { " [Brak patcha baselib: Unity 6 moze nie wywolac hooka]" }
        Write-Host ("{0}  ({1:N0} B, {2}){3}" -f $pn, (Get-Item -LiteralPath $pp).Length, (Get-Item -LiteralPath $pp).LastWriteTime, $patchStatus)
    }
}

$exes = Get-ChildItem -LiteralPath $GameRoot -Filter '*.exe' -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending
foreach ($e in $exes) {
    $em = Get-PEMachine -Path $e.FullName
    Write-Host ("EXE : {0}  -> {1}" -f $e.Name, (Get-MachineName $em))
}
foreach ($pn in $present) {
    $pm = Get-PEMachine -Path (Join-Path $GameRoot $pn)
    Write-Host ("DLL : {0}  -> {1}" -f $pn, (Get-MachineName $pm))
}
if ($exes -and $present) {
    $em = Get-PEMachine -Path $exes[0].FullName
    $pm = Get-PEMachine -Path (Join-Path $GameRoot $present[0])
    if ($em -and $pm -and $em -ne $pm) {
        Write-Host ("UWAGA: {0} jest {1}, a {2} jest {3}. Windows NIE zaladuje proxy o innej bitowosci -> BepInEx milczy, brak logow." -f $exes[0].Name, (Get-MachineName $em), $present[0], (Get-MachineName $pm)) -ForegroundColor Red
    } elseif ($em -and $pm) {
        Write-Host "Bitowosc EXE i proxy sie zgadza."
    }
}

# czy EXE w ogole importuje winhttp / version
$gameExes = $exes | Where-Object { $_.Name -notmatch 'CrashHandler' }
$mainExe = if ($gameExes) { $gameExes | Select-Object -First 1 } else { $exes | Select-Object -First 1 }
if ($mainExe) {
    $imports = Get-PEImportedDlls -Path $mainExe.FullName
    Write-Host ("{0} importuje DLL ({1}):" -f $mainExe.Name, $imports.Count)
    $imports | Sort-Object | ForEach-Object { Write-Host ("    - {0}" -f $_) }

    foreach ($probe in @('winhttp.dll','version.dll','dxgi.dll','d3d11.dll','winmm.dll','dbghelp.dll','steam_api64.dll')) {
        if ($imports -contains $probe) {
            Write-Host ("   -> Znaleziono pasujacy import proxy: {0}" -f $probe) -ForegroundColor Green
        }
    }
}

$up = Join-Path $GameRoot 'UnityPlayer.dll'
if (Test-Path -LiteralPath $up) {
    $upImports = Get-PEImportedDlls -Path $up
    Write-Host ("UnityPlayer.dll importuje DLL ({0}):" -f $upImports.Count)
    $upImports | Sort-Object | ForEach-Object { Write-Host ("    - {0}" -f $_) }
} else {
    Write-Host "UnityPlayer.dll: BRAK w katalogu gry" -ForegroundColor Yellow
}

$ds = Join-Path $GameRoot 'doorstop_config.ini'
if (Test-Path -LiteralPath $ds) {
    $enabled = (Select-String -LiteralPath $ds -Pattern '^\s*enabled\s*=' -ErrorAction SilentlyContinue | Select-Object -First 1).Line
    $target  = (Select-String -LiteralPath $ds -Pattern '^\s*target_assembly\s*=' -ErrorAction SilentlyContinue | Select-Object -First 1).Line
    $redir   = (Select-String -LiteralPath $ds -Pattern '^\s*redirect_output_log\s*=' -ErrorAction SilentlyContinue | Select-Object -First 1).Line
    Write-Host ("doorstop: {0} | {1} | {2}" -f $enabled, $target, $redir)
    if ($target) {
        $t = ($target -split '=', 2)[1].Trim().Replace('\', '\')
        $tp = Join-Path $GameRoot $t
        if (Test-Path -LiteralPath $tp) { Write-Host "   target_assembly istnieje: $t" }
        else { Write-Host "   target_assembly NIE ISTNIEJE: $t  <- Doorstop zakonczy sie cicho, bez logow BepInEx" -ForegroundColor Red }
    }
    $cl = Join-Path $GameRoot 'dotnet\coreclr.dll'
    Write-Host ("dotnet\coreclr.dll : {0}" -f (Test-Path -LiteralPath $cl))
    $dv = Join-Path $GameRoot '.doorstop_version'
    if (Test-Path -LiteralPath $dv) { Write-Host ("Doorstop version   : {0}" -f (Get-Content -LiteralPath $dv -Raw).Trim()) }
    else { Write-Host "Doorstop version   : brak pliku .doorstop_version (stary Doorstop?)" -ForegroundColor Yellow }
    $ol = Join-Path $GameRoot 'output_log.txt'
    Write-Host ("output_log.txt     : {0}" -f (Test-Path -LiteralPath $ol))
}

$ga = Get-GameAssembly -Root $GameRoot
Write-H "2. GameAssembly (natywny binary IL2CPP)"
if ($ga) {
    Write-Host ("znaleziono: {0}" -f $ga.FullName)
    Write-Host ("rozmiar   : {0:N0} B   modyfikacja: {1}" -f $ga.Length, $ga.LastWriteTime)
} else {
    Write-Host "NIE znaleziono GameAssembly.dll/.so/.dylib -> to prawdopodobnie NIE jest gra IL2CPP (sprawdz BepInEx Unity.Mono zamiast IL2CPP)." -ForegroundColor Yellow
}

Write-H "3. global-metadata.dat (wersja metadata IL2CPP)"
$meta = Get-ChildItem -LiteralPath $GameRoot -Filter 'global-metadata.dat' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First $MaxMetadataResults
if (-not $meta) {
    Write-Host "NIE znaleziono global-metadata.dat. Moze byc zaszyfrowany/usuniety (ochrona) albo w innym miejscu - wtedy ustaw [IL2CPP] GlobalMetadataPath w BepInEx/config/BepInEx.cfg." -ForegroundColor Yellow
} else {
    foreach ($m in $meta) {
        $info = Get-MetadataInfo -Path $m.FullName
        if (-not $info) { Write-Host ("{0}  -> nie udalo sie odczytac" -f $m.FullName); continue }
        if ($info.Sanity -ne 0xFAB11BAF) {
            Write-Host ("{0}" -f $m.FullName)
            Write-Host ("   magic = {0} (oczekiwano AF-1B-B1-FA / 0xFAB11BAF) -> plik prawdopodobnie ZASZYFROWANY lub zmodyfikowany" -f $info.Hex) -ForegroundColor Yellow
            continue
        }
        $supported = ($info.Version -ge $script:Limits[0]) -and ($info.Version -le $script:Limits[1])
        $verdict = if ($supported) { "OK - wspierana przez BepInEx BE <= be.788" } else { "ZA NOWA - BepInEx BE <= be.788 tego nie przeczyta (Cpp2IL wspiera 23-106)" }
        Write-Host ("{0}" -f $m.FullName)
        Write-Host ("   wersja metadata = {0}   -> {1}" -f $info.Version, $verdict)
        if (-not $supported) { Write-Host ("   => to jest przyczyna: potrzebny nowy build BepInEx z nowszym Cpp2IL" ) -ForegroundColor Red }
    }
}

Write-H "4. Wersja Unity"
$dataDir = Get-ChildItem -LiteralPath $GameRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*_Data' } | Select-Object -First 1
if ($dataDir) {
    $uv = Get-UnityVersion -Dir $dataDir.FullName
    Write-Host ("{0} -> Unity {1}" -f $dataDir.Name, $(if ($uv) { $uv } else { 'nie udalo sie odczytac' }))
    if ($uv) {
        Write-Host ("   base libs: https://unity.bepinex.dev/libraries/{0}.zip" -f $uv)
    }
} else {
    Write-Host "nie znaleziono katalogu *_Data"
}

Write-H "5. Instalacja BepInEx"
$be = Join-Path $GameRoot 'BepInEx'
if (-not (Test-Path -LiteralPath $be)) {
    Write-Host "brak folderu BepInEx w GameRoot (albo zly GameRoot)" -ForegroundColor Yellow
} else {
    $changelog = Join-Path $GameRoot 'changelog.txt'
    if (Test-Path -LiteralPath $changelog) {
        $ver = (Get-Content -LiteralPath $changelog -TotalCount 20) -match 'be\.\d+|pre\.\d+|\d+\.\d+\.\d+' | Select-Object -First 1
        Write-Host ("changelog.txt : {0}" -f $ver)
    }
    $lib = Join-Path $be 'core\LibCpp2IL.dll'
    if (Test-Path -LiteralPath $lib) {
        $s = Get-Cpp2IlSupport -Dll $lib
        Write-Host ("LibCpp2IL.dll : {0}" -f $(if ($s) { $s } else { 'nie udalo sie odczytac zakresu' }))
    } else {
        Write-Host "brak core\LibCpp2IL.dll -> to nie jest build IL2CPP?" -ForegroundColor Yellow
    }

    $interop = Join-Path $be 'interop'
    if (Test-Path -LiteralPath $interop) {
        $n = (Get-ChildItem -LiteralPath $interop -Filter '*.dll' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        $h = Join-Path $interop 'assembly-hash.txt'
        Write-Host ("interop\      : {0} dll, assembly-hash.txt = {1}" -f $n, (Test-Path -LiteralPath $h))
    } else {
        Write-Host "interop\      : BRAK (pierwsze uruchomienie / regeneracja nie zakonczyla sie)"
    }

    $ul = Join-Path $be 'unity-libs'
    if (Test-Path -LiteralPath $ul) {
        $z = (Get-ChildItem -LiteralPath $ul -Filter '*.zip' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', '
        $d = (Get-ChildItem -LiteralPath $ul -Filter '*.dll' -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("unity-libs\   : {0} dll rozpakowane; zip: {1}" -f $d, $(if ($z) { $z } else { 'brak' }))
    } else {
        Write-Host "unity-libs\   : BRAK"
    }

    $plug = Join-Path $be 'plugins'
    if (Test-Path -LiteralPath $plug) {
        $p = Get-ChildItem -LiteralPath $plug -Filter '*.dll' -Recurse -File -ErrorAction SilentlyContinue
        Write-Host ("plugins\      : {0} dll" -f ($p | Measure-Object).Count)
        $p | Select-Object -First 15 | ForEach-Object { Write-Host ("    - {0}" -f $_.FullName.Substring($GameRoot.Length).TrimStart('\')) }
    }

    $cfg = Join-Path $be 'config\BepInEx.cfg'
    if (Test-Path -LiteralPath $cfg) {
        $hit = Select-String -LiteralPath $cfg -Pattern '^\s*(UpdateInteropAssemblies|UnityBaseLibrariesSource|GlobalMetadataPath)\s*=' -ErrorAction SilentlyContinue
        if ($hit) { Write-Host "config (sekcja IL2CPP):"; $hit | ForEach-Object { Write-Host ("    " + $_.Line.Trim()) } }
    }

    $log = Join-Path $be 'LogOutput.log'
    Write-H "6. Ostatnie bledy z LogOutput.log"
    if (Test-Path -LiteralPath $log) {
        Write-Host ("plik: {0}  ({1:N0} B, {2})" -f $log, (Get-Item -LiteralPath $log).Length, (Get-Item -LiteralPath $log).LastWriteTime)
        Select-String -LiteralPath $log -Pattern 'Error|Exception|Unsupported|Failed' -ErrorAction SilentlyContinue |
            Select-Object -Last 12 | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) -ForegroundColor Yellow }
    } else {
        Write-Host "brak LogOutput.log (BepInEx w ogole nie wystartowal? sprawdź winhttp.dll/doorstop_config.ini i antywirusa)"
    }
}
Write-Host ""
Write-Host "Gotowe. Wklej caly powyższy output." -ForegroundColor Green
