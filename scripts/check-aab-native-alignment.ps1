<#
.SYNOPSIS
    Verifies that an AAB (or APK) is 16 KB page-size ready, and reports the
    release attributes Play evaluates.

.DESCRIPTION
    Google Play requires apps targeting Android 15+ to support 16 KB memory
    page sizes on 64-bit devices; from 1 February 2027 an update that does not
    will be refused.

    That requirement is about ELF segment alignment and nothing else: every
    PT_LOAD segment of every 64-bit .so must report p_align of at least 16384.
    It comes from the NDK (r27+), not from any packaging option -- worth
    stating plainly, because this project once carried `useLegacyPackaging true`
    in the belief that the flag delivered compliance.

    What the flag decides is whether each .so is duplicated onto the device.
    Compressed, Android extracts them into /data at install time, so the APK's
    copy and the extracted copy both occupy storage.

    Reading that correctly depends on the archive:

      * In an **APK**, an uncompressed library is a STORED zip entry, so the
        entry's compression method is the answer.
      * In an **AAB**, it is not. A bundle is a distribution format, and its
        `base/lib/**` entries are always deflated regardless of the setting.
        The real signal is `extractNativeLibs` in the bundle manifest, which is
        what bundletool applies when Play generates the split APKs it serves.

    No external tooling required -- reads the archive, the protobuf manifest
    and the ELF headers directly, so it runs anywhere the repo does.

.PARAMETER Path
    Path to the .aab or .apk to inspect. Defaults to the production bundle
    produced by scripts/build-android-release.ps1.

.EXAMPLE
    scripts/check-aab-native-alignment.ps1

.EXAMPLE
    scripts/check-aab-native-alignment.ps1 -Path artifacts/android/adfoot-production-20260819T145235Z.aab
#>

param(
    [string]$Path = "build/app/outputs/bundle/productionRelease/app-production-release.aab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

# 16 KB. Anything below this on a 64-bit ABI is a Play blocker.
$requiredAlignment = 16384

# Only 64-bit ABIs are subject to the requirement.
$sixtyFourBitAbis = @("arm64-v8a", "x86_64", "riscv64")

# Both ARM ABIs must be present. Play's rule is that a 64-bit variant must
# exist, not that the 32-bit one be dropped -- shipping arm64-v8a alone once
# made this app invisible on the Play Store to every armeabi-v7a handset.
#
# build.gradle carries an `abiFilters` line, but it does not decide this: the
# Flutter Gradle plugin clears defaultConfig.ndk.abiFilters and reinstates its
# own list on every build. The ABI set is therefore only ever true of an
# artifact, which is why it is checked here rather than by reading the source.
$requiredAbis = @("armeabi-v7a", "arm64-v8a")

function Read-EntryBytes {
    param(
        [Parameter(Mandatory = $true)] [System.IO.Compression.ZipArchiveEntry]$Entry,
        [int]$ByteCount = 65536
    )

    $stream = $Entry.Open()
    try {
        $buffer = New-Object byte[] $ByteCount
        $filled = 0
        while ($filled -lt $ByteCount) {
            $read = $stream.Read($buffer, $filled, $ByteCount - $filled)
            if ($read -le 0) { break }
            $filled += $read
        }
        if ($filled -lt $ByteCount) {
            $trimmed = New-Object byte[] $filled
            [Array]::Copy($buffer, $trimmed, $filled)
            return $trimmed
        }
        return $buffer
    } finally {
        $stream.Dispose()
    }
}

function Get-ManifestAttribute {
    <#
      The bundle manifest is protobuf-encoded XML, but attribute names and
      their string values survive as plain ASCII, separated by a couple of
      protobuf framing bytes. That is enough to read the handful of release
      attributes this script reports, without pulling in a protobuf runtime.
    #>
    param(
        [byte[]]$Bytes,
        [string]$Name
    )

    $text = [System.Text.Encoding]::GetEncoding(28591).GetString($Bytes)
    # The value stops at the next protobuf framing byte, so the character class
    # is restricted to what these attributes can actually contain. A broader
    # class swallows the framing byte too, and "36" arrives as '36"'.
    $pattern = [regex]::Escape($Name) + '[\x00-\x1f]{1,3}([0-9A-Za-z._+-]{1,24})'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function Get-LoadSegmentAlignments {
    <#
      Returns the p_align of every PT_LOAD program header, or $null when the
      bytes are not a little-endian ELF we can read.
    #>
    param([byte[]]$Bytes)

    if ($Bytes.Length -lt 64) { return $null }
    if ($Bytes[0] -ne 0x7F -or $Bytes[1] -ne 0x45 -or $Bytes[2] -ne 0x4C -or $Bytes[3] -ne 0x46) {
        return $null
    }
    # EI_DATA must be ELFDATA2LSB; every Android ABI is little-endian.
    if ($Bytes[5] -ne 1) { return $null }

    $is64 = ($Bytes[4] -eq 2)

    if ($is64) {
        $phoff = [BitConverter]::ToInt64($Bytes, 0x20)
        $phentsize = [BitConverter]::ToUInt16($Bytes, 0x36)
        $phnum = [BitConverter]::ToUInt16($Bytes, 0x38)
        $alignOffset = 0x30
    } else {
        $phoff = [BitConverter]::ToUInt32($Bytes, 0x1C)
        $phentsize = [BitConverter]::ToUInt16($Bytes, 0x2A)
        $phnum = [BitConverter]::ToUInt16($Bytes, 0x2C)
        $alignOffset = 0x1C
    }

    $alignments = New-Object System.Collections.Generic.List[long]
    for ($i = 0; $i -lt $phnum; $i++) {
        $base = [int]$phoff + ($i * [int]$phentsize)
        if (($base + $phentsize) -gt $Bytes.Length) { break }

        $pType = [BitConverter]::ToUInt32($Bytes, $base)
        if ($pType -ne 1) { continue }   # PT_LOAD only

        if ($is64) {
            $alignments.Add([BitConverter]::ToInt64($Bytes, $base + $alignOffset))
        } else {
            $alignments.Add([BitConverter]::ToUInt32($Bytes, $base + $alignOffset))
        }
    }

    return $alignments
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "Archive introuvable : $Path" -ForegroundColor Red
    Write-Host "Construisez d'abord un bundle, ou passez -Path."
    exit 1
}

$resolved = (Resolve-Path -LiteralPath $Path).Path
Write-Host ""
Write-Host "Archive : $resolved"
Write-Host "Seuil   : p_align >= $requiredAlignment (16 KB) sur les ABI 64 bits"
Write-Host ""

$archive = [System.IO.Compression.ZipFile]::OpenRead($resolved)
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$storedCount = 0
$deflatedCount = 0
$inspected = 0
$seenAbis = New-Object System.Collections.Generic.HashSet[string]

try {
    # ── Release attributes, straight from the manifest ────────────────────
    $manifestEntry = $archive.Entries |
        Where-Object { $_.FullName -eq "base/manifest/AndroidManifest.xml" } |
        Select-Object -First 1
    $isBundle = ($null -ne $manifestEntry)

    if (-not $isBundle) {
        $manifestEntry = $archive.Entries |
            Where-Object { $_.FullName -eq "AndroidManifest.xml" } |
            Select-Object -First 1
    }

    $extractNativeLibs = $null

    if ($null -ne $manifestEntry) {
        $manifestBytes = Read-EntryBytes -Entry $manifestEntry -ByteCount 262144

        $versionCode = Get-ManifestAttribute -Bytes $manifestBytes -Name "versionCode"
        $versionName = Get-ManifestAttribute -Bytes $manifestBytes -Name "versionName"
        $targetSdk = Get-ManifestAttribute -Bytes $manifestBytes -Name "targetSdkVersion"
        $minSdk = Get-ManifestAttribute -Bytes $manifestBytes -Name "minSdkVersion"
        $extractNativeLibs = Get-ManifestAttribute -Bytes $manifestBytes -Name "extractNativeLibs"

        Write-Host "Format          : $(if ($isBundle) { 'App Bundle (.aab)' } else { 'APK' })"
        Write-Host "versionCode     : $versionCode"
        Write-Host "versionName     : $versionName"
        Write-Host "minSdkVersion   : $minSdk"
        Write-Host "targetSdkVersion: $targetSdk"
        Write-Host "extractNativeLibs: $extractNativeLibs"
        Write-Host ""

        # Play refuses updates whose target API is more than a year behind the
        # latest Android release. Android 16 is API 36.
        if ($targetSdk -and [int]$targetSdk -lt 36) {
            $errors.Add("targetSdkVersion $targetSdk : Play exige 36 (Android 16) au minimum.")
        }
    } else {
        $warnings.Add("Manifeste introuvable dans l'archive : attributs de release non verifies.")
    }

    # ── ELF alignment, the actual 16 KB requirement ───────────────────────
    $soEntries = $archive.Entries | Where-Object { $_.FullName -like "*.so" } | Sort-Object FullName

    if (-not $soEntries) {
        Write-Host "Aucune bibliotheque native trouvee dans l'archive." -ForegroundColor Yellow
        exit 1
    }

    $header = "{0,-52} {1,-10} {2,-14} {3}" -f "BIBLIOTHEQUE", "ZIP", "P_ALIGN", "VERDICT"
    Write-Host $header
    Write-Host ("-" * 100)

    foreach ($entry in $soEntries) {
        # .../lib/<abi>/<name>.so in both bundle and APK layouts.
        $abiMatch = [regex]::Match($entry.FullName, '(?:^|/)lib/([^/]+)/[^/]+\.so$')
        if ($abiMatch.Success) { $null = $seenAbis.Add($abiMatch.Groups[1].Value) }

        $abi = "?"
        foreach ($candidate in $sixtyFourBitAbis) {
            if ($entry.FullName -like "*/$candidate/*") { $abi = $candidate }
        }
        $is64BitAbi = ($abi -ne "?")

        $stored = ($entry.CompressedLength -eq $entry.Length)
        $storage = if ($stored) { "STORED" } else { "DEFLATE" }
        if ($stored) { $storedCount++ } else { $deflatedCount++ }

        if (-not $is64BitAbi) {
            $line = "{0,-52} {1,-10} {2,-14} {3}" -f $entry.FullName, $storage, "-", "32 bits, hors perimetre"
            Write-Host $line -ForegroundColor DarkGray
            continue
        }

        $inspected++
        $bytes = Read-EntryBytes -Entry $entry
        $alignments = Get-LoadSegmentAlignments -Bytes $bytes

        if ($null -eq $alignments -or $alignments.Count -eq 0) {
            $errors.Add("$($entry.FullName) : en-tetes ELF illisibles")
            $line = "{0,-52} {1,-10} {2,-14} {3}" -f $entry.FullName, $storage, "?", "ILLISIBLE"
            Write-Host $line -ForegroundColor Red
            continue
        }

        $worst = ($alignments | Measure-Object -Minimum).Minimum
        $distinct = ($alignments | Sort-Object -Unique) -join "/"

        if ($worst -lt $requiredAlignment) {
            $errors.Add("$($entry.FullName) : p_align $worst < $requiredAlignment")
            $line = "{0,-52} {1,-10} {2,-14} {3}" -f $entry.FullName, $storage, $distinct, "NON CONFORME 16 KB"
            Write-Host $line -ForegroundColor Red
        } else {
            $line = "{0,-52} {1,-10} {2,-14} {3}" -f $entry.FullName, $storage, $distinct, "OK 16 KB"
            Write-Host $line -ForegroundColor Green
        }
    }
} finally {
    $archive.Dispose()
}

Write-Host ""
Write-Host "Bibliotheques 64 bits inspectees : $inspected"

$abiList = ($seenAbis | Sort-Object) -join ", "
Write-Host "ABI presentes                    : $abiList"
foreach ($required in $requiredAbis) {
    if (-not $seenAbis.Contains($required)) {
        $errors.Add("ABI manquante : $required. Play masquerait l'application aux appareils concernes.")
    }
}

# ── Packaging verdict, read from the right place for the format ───────────
Write-Host ""
if ($isBundle) {
    Write-Host "Empaquetage natif (source de verite : le manifeste)"
    Write-Host "  Dans un bundle, base/lib/** est toujours deflate : c'est un format de"
    Write-Host "  distribution, pas d'installation. Seul extractNativeLibs compte, et"
    Write-Host "  bundletool l'applique aux APK que Play genere."
    if ($extractNativeLibs -eq "false") {
        Write-Host "  extractNativeLibs=false : une seule copie des .so sur l'appareil." -ForegroundColor Green
    } elseif ($extractNativeLibs -eq "true") {
        $warnings.Add("extractNativeLibs=true : chaque .so sera duplique sur l'appareil (copie APK + copie extraite dans /data).")
        Write-Host "  extractNativeLibs=true : chaque .so sera duplique sur l'appareil." -ForegroundColor Yellow
    } else {
        Write-Host "  extractNativeLibs absent : le defaut AGP s'applique (false pour minSdk >= 23)."
    }
} else {
    Write-Host "Empaquetage natif (source de verite : la methode de compression zip)"
    if ($deflatedCount -gt 0) {
        $warnings.Add("$deflatedCount bibliotheque(s) compressee(s) dans l'APK : elles seront extraites dans /data a l'installation.")
        Write-Host "  $deflatedCount compressee(s), $storedCount stockee(s) non compressee(s)." -ForegroundColor Yellow
    } else {
        Write-Host "  Toutes stockees non compressees : une seule copie sur l'appareil." -ForegroundColor Green
        Write-Host "  Pensez a verifier l'alignement zip : zipalign -c -P 16 -v 4 <apk>"
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    foreach ($item in $warnings) { Write-Host "AVERTISSEMENT : $item" -ForegroundColor Yellow }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "ECHEC." -ForegroundColor Red
    foreach ($item in $errors) { Write-Host "  - $item" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Pour un defaut d'alignement : verifiez ndkVersion dans"
    Write-Host "android/app/build.gradle (r27 minimum, r29 ici) puis reconstruisez"
    Write-Host "apres un flutter clean."
    exit 1
}

Write-Host ""
Write-Host "OK : bibliotheques 64 bits alignees 16 KB, attributs de release conformes." -ForegroundColor Green
exit 0
