param(
    [switch]$RequireReleaseReady
)

$androidGradlePath = "android/app/build.gradle"
$iosProjectPath = "ios/Runner.xcodeproj/project.pbxproj"

if (-not (Test-Path $androidGradlePath)) {
    Write-Error "Missing $androidGradlePath"
    exit 1
}

if (-not (Test-Path $iosProjectPath)) {
    Write-Error "Missing $iosProjectPath"
    exit 1
}

$androidGradle = Get-Content $androidGradlePath -Raw
$iosProject = Get-Content $iosProjectPath -Raw

$androidApplicationIdMatch = [regex]::Match(
    $androidGradle,
    'applicationId\s*=\s*"([^"]+)"'
)
$androidNamespaceMatch = [regex]::Match(
    $androidGradle,
    'namespace\s*=\s*"([^"]+)"'
)

$iosBundleIds = [regex]::Matches(
    $iosProject,
    'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'
) | ForEach-Object {
    $_.Groups[1].Value.Trim()
} | Where-Object {
    $_ -notlike "*.RunnerTests"
} | Sort-Object -Unique

$androidApplicationId = if ($androidApplicationIdMatch.Success) {
    $androidApplicationIdMatch.Groups[1].Value
} else {
    "<missing>"
}

$androidNamespace = if ($androidNamespaceMatch.Success) {
    $androidNamespaceMatch.Groups[1].Value
} else {
    "<missing>"
}

$plannedIds = [ordered]@{
    local = "org.adfoot.app.local"
    staging = "org.adfoot.app.staging"
    production = "org.adfoot.app"
}

Write-Host "Current Android namespace: $androidNamespace"
Write-Host "Current Android applicationId: $androidApplicationId"
Write-Host "Current iOS bundle IDs: $($iosBundleIds -join ', ')"
Write-Host "Planned publication IDs:"
$plannedIds.GetEnumerator() | ForEach-Object {
    Write-Host "  $($_.Key): $($_.Value)"
}

$hasPlaceholderIds = $androidApplicationId -like "com.example.*" -or
    $androidNamespace -like "com.example.*" -or
    ($iosBundleIds | Where-Object { $_ -like "com.example.*" }).Count -gt 0

if ($hasPlaceholderIds) {
    Write-Warning "Placeholder package or bundle IDs are still active. Keep them until the new Firebase apps are created, then replace them before Play Store/App Store publication."
}

if ($RequireReleaseReady -and $hasPlaceholderIds) {
    Write-Error "Release-ready check failed because placeholder IDs are still active."
    exit 1
}

exit 0
