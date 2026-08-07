param(
    [string]$KeystorePath = "android/upload-keystore.jks",
    [string]$KeyAlias = "upload",
    [string]$StorePassword,
    [string]$KeyPassword,
    [switch]$GenerateKeystore,
    [string]$DName = "CN=Adfoot, OU=Mobile, O=Adfoot, L=Bamako, ST=Bamako, C=ML",
    [int]$ValidityDays = 10000,
    [switch]$RegenerateKeystore,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-SecretAsPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    $secureValue = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repoRoot "android"

$resolvedKeystorePath = if ([System.IO.Path]::IsPathRooted($KeystorePath)) {
    $KeystorePath
} else {
    Join-Path $repoRoot $KeystorePath
}

$keyPropertiesPath = Join-Path $androidDir "key.properties"
$keystoreAlreadyExists = Test-Path -LiteralPath $resolvedKeystorePath

if ($RegenerateKeystore -and -not $GenerateKeystore) {
    Write-Error "-RegenerateKeystore requires -GenerateKeystore."
    exit 1
}

if ($RegenerateKeystore -and -not $Force) {
    Write-Error "-RegenerateKeystore replaces the existing upload key. Re-run with -Force only if this key has not been uploaded to Play Console."
    exit 1
}

function Resolve-KeytoolPath {
    $candidateKeytool = if ($env:JAVA_HOME) {
        Join-Path $env:JAVA_HOME "bin/keytool.exe"
    } else {
        ""
    }

    if ($candidateKeytool -and (Test-Path -LiteralPath $candidateKeytool)) {
        return $candidateKeytool
    }

    return "keytool"
}

function Get-RelativePathCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFullPath = $baseFullPath + [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFullPath)
    $targetUri = New-Object System.Uri($targetFullPath)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)

    return [System.Uri]::UnescapeDataString($relativeUri.ToString()) -replace '/', [System.IO.Path]::DirectorySeparatorChar
}

function Test-KeystoreCredentials {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedKeystorePath,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedStorePassword,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedKeyAlias
    )

    $keytool = Resolve-KeytoolPath
    $verifyArgs = @(
        "-list",
        "-keystore", $ResolvedKeystorePath,
        "-storepass", $ResolvedStorePassword,
        "-alias", $ResolvedKeyAlias
    )

    $verifyOutput = & $keytool @verifyArgs 2>&1
    if ($LASTEXITCODE -gt 0) {
        Write-Error "Keystore verification failed. Check the password and alias '$ResolvedKeyAlias'."
        Write-Host $verifyOutput
        exit $LASTEXITCODE
    }
}

function Write-Utf8NoBomLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

$shouldCreateNewKeystore = $GenerateKeystore -and ($RegenerateKeystore -or -not $keystoreAlreadyExists)

if ([string]::IsNullOrWhiteSpace($StorePassword)) {
    if ($shouldCreateNewKeystore) {
        if ($RegenerateKeystore) {
            Write-Host "Create a replacement Android upload keystore password."
            Write-Host "Only continue if the existing key has not been uploaded to Play Console."
        } else {
            Write-Host "Create a new Android upload keystore password."
        }
        Write-Host "Keep it outside git. It is required to sign future Play Store updates."
        $StorePassword = Read-SecretAsPlainText -Prompt "New StorePassword"
        $StorePasswordConfirmation = Read-SecretAsPlainText -Prompt "Confirm StorePassword"

        if ($StorePassword -ne $StorePasswordConfirmation) {
            Write-Error "StorePassword confirmation does not match."
            exit 1
        }
    } elseif ($keystoreAlreadyExists) {
        Write-Host "Existing Android upload keystore found."
        Write-Host "Enter the password used when this keystore was created."
        $StorePassword = Read-SecretAsPlainText -Prompt "StorePassword"
    } else {
        Write-Error "Keystore file not found. Re-run with -GenerateKeystore to create it."
        exit 1
    }
}

if ($StorePassword.Length -lt 12) {
    Write-Error "StorePassword must contain at least 12 characters."
    exit 1
}

if ([string]::IsNullOrWhiteSpace($KeyPassword)) {
    $KeyPassword = $StorePassword
}

if ([string]::IsNullOrWhiteSpace($KeyAlias)) {
    Write-Error "KeyAlias is required."
    exit 1
}

if ($GenerateKeystore) {
    $keystoreParent = Split-Path -Parent $resolvedKeystorePath
    if (-not (Test-Path -LiteralPath $keystoreParent)) {
        New-Item -ItemType Directory -Path $keystoreParent -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $resolvedKeystorePath) -and $RegenerateKeystore) {
        Remove-Item -LiteralPath $resolvedKeystorePath -Force
        $keystoreAlreadyExists = $false
        Write-Host "Existing keystore replaced: $resolvedKeystorePath"
    }

    if (Test-Path -LiteralPath $resolvedKeystorePath) {
        Write-Host "Keystore already exists, reusing it: $resolvedKeystorePath"
    } else {
        $keytool = Resolve-KeytoolPath
        $keytoolArgs = @(
            "-genkeypair",
            "-v",
            "-keystore", $resolvedKeystorePath,
            "-storepass", $StorePassword,
            "-alias", $KeyAlias,
            "-keypass", $KeyPassword,
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", "$ValidityDays",
            "-dname", $DName
        )

        Write-Host "Certificate subject: $DName"
        & $keytool @keytoolArgs
        if ($LASTEXITCODE -gt 0) {
            Write-Error "keytool generation failed (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
    }
}

if (-not (Test-Path -LiteralPath $resolvedKeystorePath)) {
    Write-Error "Keystore file not found: $resolvedKeystorePath"
    exit 1
}

Test-KeystoreCredentials `
    -ResolvedKeystorePath $resolvedKeystorePath `
    -ResolvedStorePassword $StorePassword `
    -ResolvedKeyAlias $KeyAlias

$relativeStoreFile = Get-RelativePathCompat -BasePath $androidDir -TargetPath $resolvedKeystorePath
$relativeStoreFile = $relativeStoreFile -replace '\\', '/'

if (Test-Path -LiteralPath $keyPropertiesPath) {
    if ($Force) {
        Write-Host "android/key.properties already exists, overwriting it."
    } else {
        Write-Host "android/key.properties already exists, refreshing it."
    }
}

$content = @(
    "storePassword=$StorePassword",
    "keyPassword=$KeyPassword",
    "keyAlias=$KeyAlias",
    "storeFile=$relativeStoreFile"
)

Write-Utf8NoBomLines -Path $keyPropertiesPath -Lines $content

Write-Host "Android signing configured."
Write-Host "Keystore path    : $resolvedKeystorePath"
Write-Host "Key alias        : $KeyAlias"
Write-Host "key.properties   : $keyPropertiesPath"
Write-Host "storeFile (rel.) : $relativeStoreFile"
Write-Host ""
Write-Host "Important: back up android/upload-keystore.jks and the password securely outside the repository."

exit 0
