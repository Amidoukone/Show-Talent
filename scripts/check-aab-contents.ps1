<#
.SYNOPSIS
    Verifies that an AAB actually contains the code of this checkout, before it
    is uploaded to Play.

.DESCRIPTION
    On 2 September 2026, `1.0.7+31` was built, signed, and did not contain the
    day's fixes: the build cache served an old `libapp.so`. The manifest still
    carried `versionCode 31`, correctly. Nothing in the chain could see it --
    not `flutter analyze`, not the 845 tests, because they all read the source
    and never the artifact. A versionCode was burned for nothing, and Play does
    not give one back.

    This script reads the artifact and never the source. It answers one
    question: *does this bundle contain the code I just wrote?*

    It asks four independent ways, because none of them is sufficient alone:

      1. **versionCode / versionName** from the manifest against
         `pubspec.yaml`. Necessary, and very far from sufficient: a cached
         build still stamps the right versionCode into the manifest. That is
         precisely what made `31` look fine.
      2. **Witness strings** inside `base/lib/<abi>/libapp.so`, the AOT
         snapshot where Dart literals live. A string the release adds must be
         there; a string it deletes must be gone. This is the only check that
         speaks about the *content* of the release.
         Each string is searched in Latin-1, UTF-8 and UTF-16LE: Dart stores a
         literal as a OneByteString (one byte per character) when it fits, as a
         TwoByteString (UTF-16) otherwise, and which one it picked is not a
         visible property of the text you read in the editor. Searching UTF-8
         alone reports a French label as missing when it is present.
      3. **`libapp.so` fingerprint** against the previous release's bundle. Two
         successive builds with modified Dart in between cannot produce the
         same snapshot. Identical means the build served a cache -- a verdict
         with no list to maintain and no judgement call.
      4. **Timestamps**: the bundle against the most recent `lib/**.dart`. A
         bundle older than the code was not rebuilt.

    No external tooling: reads the zip, the protobuf manifest and the snapshot
    bytes directly, like scripts/check-aab-native-alignment.ps1 next to it.
    That script answers "will Play accept this?"; this one answers "is this the
    build I think it is?".

.PARAMETER Path
    The .aab to inspect. Defaults to the production bundle.

.PARAMETER ExpectationsPath
    JSON file holding the witness strings.
    Defaults to scripts/aab-content-expectations.json

.PARAMETER Baseline
    The previous .aab, for the fingerprint comparison. By default, the most
    recent bundle in artifacts/android carrying a *different* versionCode --
    the build archives its own copy there, so the newest file is usually the
    bundle under inspection under another name.

.PARAMETER NoBaseline
    Skips the fingerprint comparison (first build, or no baseline available).

.PARAMETER Abi
    Which ABI's libapp.so to read. Defaults to arm64-v8a.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\check-aab-contents.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\check-aab-contents.ps1 -Path artifacts/android/adfoot-production-20260902T031403Z.aab -NoBaseline
#>

param(
    [string]$Path = "build/app/outputs/bundle/productionRelease/app-production-release.aab",
    [string]$ExpectationsPath = "scripts/aab-content-expectations.json",
    [string]$Baseline,
    [switch]$NoBaseline,
    [string]$Abi = "arm64-v8a"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Resolve-RepoPath {
    param([string]$Candidate)

    if ([System.IO.Path]::IsPathRooted($Candidate)) { return $Candidate }
    if (Test-Path -LiteralPath $Candidate) { return (Resolve-Path -LiteralPath $Candidate).Path }
    return (Join-Path $repoRoot $Candidate)
}

function Get-ManifestAttribute {
    <#
      The bundle manifest is protobuf-encoded XML, but attribute names and
      their string values survive as plain ASCII, separated by a couple of
      protobuf framing bytes -- enough to read versionCode and versionName
      without a protobuf runtime. Same reading as
      scripts/check-aab-native-alignment.ps1.
    #>
    param([byte[]]$Bytes, [string]$Name)

    $text = [System.Text.Encoding]::GetEncoding(28591).GetString($Bytes)
    $pattern = [regex]::Escape($Name) + '[\x00-\x1f]{1,3}([0-9A-Za-z._+-]{1,24})'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

function Read-EntryBytes {
    param([System.IO.Compression.ZipArchiveEntry]$Entry)

    $stream = $Entry.Open()
    try {
        $memory = New-Object System.IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            return $memory.ToArray()
        } finally {
            $memory.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-SnapshotEntry {
    <#
      base/lib/<abi>/libapp.so, falling back to another ABI when the requested
      one is absent.
    #>
    param([System.IO.Compression.ZipArchive]$Archive, [string]$PreferredAbi)

    $candidates = @($Archive.Entries | Where-Object { $_.FullName -match '(^|/)lib/[^/]+/libapp\.so$' })
    if ($candidates.Count -eq 0) { return $null }

    $preferred = $candidates | Where-Object { $_.FullName -like "*/$PreferredAbi/*" } | Select-Object -First 1
    if ($null -ne $preferred) { return $preferred }
    return ($candidates | Sort-Object FullName | Select-Object -First 1)
}

function Get-SearchHaystack {
    <#
      One byte, one character: Latin-1 loses nothing and reinterprets nothing,
      so any byte sequence can be searched with an ordinal IndexOf -- native,
      hence instant over 10 MB, where a PowerShell loop over the bytes would
      take minutes.
    #>
    param([byte[]]$Bytes)

    return [System.Text.Encoding]::GetEncoding(28591).GetString($Bytes)
}

function Find-TextEncoding {
    <#
      Returns the name of the encoding the text was found under, or $null.
    #>
    param([string]$Haystack, [string]$Text)

    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $encodings = [ordered]@{
        "Latin-1"  = $latin1.GetBytes($Text)
        "UTF-8"    = [System.Text.Encoding]::UTF8.GetBytes($Text)
        "UTF-16LE" = [System.Text.Encoding]::Unicode.GetBytes($Text)
    }

    foreach ($name in $encodings.Keys) {
        $needle = $latin1.GetString($encodings[$name])
        if ($Haystack.IndexOf($needle, [System.StringComparison]::Ordinal) -ge 0) {
            return $name
        }
    }
    return $null
}

function Get-Sha256 {
    param([byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

# ── The artifact ──────────────────────────────────────────────────────────
$resolved = Resolve-RepoPath -Candidate $Path
if (-not (Test-Path -LiteralPath $resolved)) {
    Write-Host "Bundle introuvable : $resolved" -ForegroundColor Red
    Write-Host "Construisez d'abord un bundle, ou passez -Path."
    exit 1
}
$resolved = (Resolve-Path -LiteralPath $resolved).Path
$bundleInfo = Get-Item -LiteralPath $resolved

Write-Host ""
Write-Host "Bundle  : $resolved"
Write-Host "Taille  : $($bundleInfo.Length) octets"
Write-Host "Modifie : $($bundleInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "SHA-256 : $(Get-Sha256 -Bytes ([System.IO.File]::ReadAllBytes($resolved)))"
Write-Host ""

# ── 1. Declared version, read from the bundle's own manifest ──────────────
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$expectedName = $null
$expectedCode = $null
if (Test-Path -LiteralPath $pubspecPath) {
    $versionMatch = [regex]::Match((Get-Content -LiteralPath $pubspecPath -Raw), '(?m)^version:\s*([0-9.]+)\+([0-9]+)\s*$')
    if ($versionMatch.Success) {
        $expectedName = $versionMatch.Groups[1].Value
        $expectedCode = $versionMatch.Groups[2].Value
    } else {
        $warnings.Add("Version illisible dans pubspec.yaml : comparaison de version ignoree.")
    }
} else {
    $warnings.Add("pubspec.yaml introuvable : comparaison de version ignoree.")
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($resolved)
$snapshotBytes = $null
$snapshotName = $null
$actualCode = $null
$actualName = $null

try {
    $manifestEntry = $archive.Entries |
        Where-Object { $_.FullName -eq "base/manifest/AndroidManifest.xml" } |
        Select-Object -First 1

    if ($null -eq $manifestEntry) {
        $errors.Add("base/manifest/AndroidManifest.xml absent : ce fichier n'est pas un bundle.")
    } else {
        $manifestBytes = Read-EntryBytes -Entry $manifestEntry
        $actualCode = Get-ManifestAttribute -Bytes $manifestBytes -Name "versionCode"
        $actualName = Get-ManifestAttribute -Bytes $manifestBytes -Name "versionName"

        Write-Host "1. Version declaree par le bundle"
        Write-Host "   versionCode : $actualCode"
        Write-Host "   versionName : $actualName"

        if ($null -ne $expectedCode) {
            if ("$actualCode" -ne "$expectedCode") {
                $errors.Add("versionCode $actualCode dans le bundle, $expectedCode dans pubspec.yaml.")
                Write-Host "   ECHEC : pubspec.yaml annonce $expectedName+$expectedCode." -ForegroundColor Red
            } elseif ("$actualName" -ne "$expectedName") {
                $errors.Add("versionName $actualName dans le bundle, $expectedName dans pubspec.yaml.")
                Write-Host "   ECHEC : pubspec.yaml annonce $expectedName+$expectedCode." -ForegroundColor Red
            } else {
                Write-Host "   OK : conforme a pubspec.yaml ($expectedName+$expectedCode)." -ForegroundColor Green
            }
        }
        Write-Host ""
    }

    # ── 2. Witness strings, inside the Dart snapshot ──────────────────────
    $snapshotEntry = Get-SnapshotEntry -Archive $archive -PreferredAbi $Abi
    if ($null -eq $snapshotEntry) {
        $errors.Add("Aucun libapp.so dans le bundle : contenu Dart non verifiable.")
    } else {
        $snapshotName = $snapshotEntry.FullName
        $snapshotBytes = Read-EntryBytes -Entry $snapshotEntry
    }
} finally {
    $archive.Dispose()
}

if ($null -ne $snapshotBytes) {
    $snapshotHash = Get-Sha256 -Bytes $snapshotBytes
    $haystack = Get-SearchHaystack -Bytes $snapshotBytes

    Write-Host "2. Contenu Dart ($snapshotName, $($snapshotBytes.Length) octets)"
    Write-Host "   SHA-256 : $snapshotHash"

    $expectationsResolved = Resolve-RepoPath -Candidate $ExpectationsPath
    if (-not (Test-Path -LiteralPath $expectationsResolved)) {
        $warnings.Add("Attentes introuvables ($expectationsResolved) : chaines temoins non verifiees.")
        Write-Host "   Attentes introuvables : $expectationsResolved" -ForegroundColor Yellow
    } else {
        # -Encoding UTF8 is not optional: without it Windows PowerShell reads
        # the file as ANSI, and an accented witness then searches for bytes the
        # snapshot cannot contain.
        $expectations = Get-Content -LiteralPath $expectationsResolved -Raw -Encoding UTF8 | ConvertFrom-Json

        $declaredFor = if ($expectations.PSObject.Properties.Name -contains "forVersionCode") {
            [string]$expectations.forVersionCode
        } else {
            $null
        }

        if ($declaredFor -and $expectedCode -and $declaredFor -ne "$expectedCode") {
            # Deliberately a warning: witnesses from a past release usually
            # still hold. But they were chosen for another release and nobody
            # has said they still discriminate -- that has to be visible.
            $warnings.Add("Temoins ecrits pour le versionCode $declaredFor, ce build est le $expectedCode. Relisez $ExpectationsPath.")
        }

        $mustContain = @()
        if ($expectations.PSObject.Properties.Name -contains "mustContain") {
            $mustContain = @($expectations.mustContain)
        }
        $mustNotContain = @()
        if ($expectations.PSObject.Properties.Name -contains "mustNotContain") {
            $mustNotContain = @($expectations.mustNotContain)
        }

        Write-Host ""
        foreach ($item in $mustContain) {
            $quoted = '"' + $item.text + '"'
            $found = Find-TextEncoding -Haystack $haystack -Text $item.text
            if ($null -eq $found) {
                $errors.Add("Absente du bundle alors qu'elle devrait y etre : $quoted ($($item.why))")
                Write-Host ("   ABSENTE  {0,-48} {1}" -f $quoted, $item.why) -ForegroundColor Red
            } else {
                Write-Host ("   presente {0,-48} {1}" -f $quoted, $found) -ForegroundColor Green
            }
        }
        foreach ($item in $mustNotContain) {
            $quoted = '"' + $item.text + '"'
            $found = Find-TextEncoding -Haystack $haystack -Text $item.text
            if ($null -ne $found) {
                $errors.Add("Presente dans le bundle alors qu'elle a ete supprimee : $quoted ($($item.why))")
                Write-Host ("   PRESENTE {0,-48} {1}" -f $quoted, $item.why) -ForegroundColor Red
            } else {
                Write-Host ("   absente  {0,-48} {1}" -f $quoted, "supprimee, comme attendu") -ForegroundColor Green
            }
        }
    }
    Write-Host ""

    # ── 3. Fingerprint against the previous release ───────────────────────
    Write-Host "3. Comparaison avec le bundle precedent"
    if ($NoBaseline) {
        Write-Host "   ignoree (-NoBaseline)."
    } else {
        $baselinePath = $null
        if ($Baseline) {
            $baselinePath = Resolve-RepoPath -Candidate $Baseline
            if (-not (Test-Path -LiteralPath $baselinePath)) {
                $errors.Add("Baseline introuvable : $baselinePath")
                $baselinePath = $null
            }
        } else {
            # The baseline is the previous *release*, not the previous file: the
            # build archives its own copy into artifacts/android, so the newest
            # candidate is usually this very bundle under another name. Walk
            # back until the versionCode differs.
            $artifactsDir = Join-Path $repoRoot "artifacts/android"
            if (Test-Path -LiteralPath $artifactsDir) {
                $candidates = Get-ChildItem -LiteralPath $artifactsDir -Filter "*.aab" |
                    Where-Object { $_.FullName -ne $resolved } |
                    Sort-Object LastWriteTime -Descending
                foreach ($candidate in $candidates) {
                    $candidateCode = $null
                    $candidateArchive = [System.IO.Compression.ZipFile]::OpenRead($candidate.FullName)
                    try {
                        $candidateManifest = $candidateArchive.Entries |
                            Where-Object { $_.FullName -eq "base/manifest/AndroidManifest.xml" } |
                            Select-Object -First 1
                        if ($null -eq $candidateManifest) { continue }
                        $candidateCode = Get-ManifestAttribute -Bytes (Read-EntryBytes -Entry $candidateManifest) -Name "versionCode"
                    } finally {
                        $candidateArchive.Dispose()
                    }
                    if ("$candidateCode" -ne "$actualCode") {
                        $baselinePath = $candidate.FullName
                        break
                    }
                }
            }
        }

        if ($null -eq $baselinePath) {
            $warnings.Add("Aucun bundle precedent trouve : comparaison d'empreinte impossible.")
            Write-Host "   Aucun bundle precedent dans artifacts/android." -ForegroundColor Yellow
        } else {
            $baselineArchive = [System.IO.Compression.ZipFile]::OpenRead($baselinePath)
            try {
                $baselineEntry = Get-SnapshotEntry -Archive $baselineArchive -PreferredAbi $Abi
                if ($null -eq $baselineEntry) {
                    $warnings.Add("Pas de libapp.so dans la baseline : comparaison ignoree.")
                } else {
                    $baselineHash = Get-Sha256 -Bytes (Read-EntryBytes -Entry $baselineEntry)
                    Write-Host "   Precedent : $(Split-Path -Leaf $baselinePath)"
                    Write-Host "   SHA-256   : $baselineHash"
                    if ($baselineHash -eq $snapshotHash) {
                        $errors.Add("libapp.so identique au bundle precedent : ce build a servi un cache, il ne contient aucun changement Dart.")
                        Write-Host "   ECHEC : instantane Dart identique au precedent." -ForegroundColor Red
                        Write-Host "           C'est la signature d'un build cache." -ForegroundColor Red
                    } else {
                        Write-Host "   OK : instantane Dart different du precedent." -ForegroundColor Green
                    }
                }
            } finally {
                $baselineArchive.Dispose()
            }
        }
    }
    Write-Host ""
}

# ── 4. Is the bundle newer than the code? ─────────────────────────────────
Write-Host "4. Fraicheur"
$libDir = Join-Path $repoRoot "lib"
if (Test-Path -LiteralPath $libDir) {
    $newestDart = Get-ChildItem -LiteralPath $libDir -Filter "*.dart" -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $newestDart) {
        Write-Host "   Dart le plus recent : $($newestDart.Name) $($newestDart.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
        if ($newestDart.LastWriteTime -gt $bundleInfo.LastWriteTime) {
            $errors.Add("Du code Dart a ete modifie apres la construction du bundle ($($newestDart.FullName)).")
            Write-Host "   ECHEC : le bundle est anterieur au code." -ForegroundColor Red
        } else {
            Write-Host "   OK : le bundle est posterieur au dernier code Dart." -ForegroundColor Green
        }
    }
}

Write-Host ""
if ($warnings.Count -gt 0) {
    foreach ($item in $warnings) { Write-Host "AVERTISSEMENT : $item" -ForegroundColor Yellow }
    Write-Host ""
}

if ($errors.Count -gt 0) {
    Write-Host "ECHEC : ne pas televerser ce bundle." -ForegroundColor Red
    foreach ($item in $errors) { Write-Host "  - $item" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Pour un build cache : android\gradlew --stop, puis flutter clean," -ForegroundColor Red
    Write-Host "flutter pub get, et reconstruire. Si le nettoyage echoue sur un" -ForegroundColor Red
    Write-Host "verrou de fichier, fermez ce qui tient build\ (IDE, emulateur)." -ForegroundColor Red
    exit 1
}

Write-Host "OK : ce bundle contient le code de ce checkout." -ForegroundColor Green
exit 0
