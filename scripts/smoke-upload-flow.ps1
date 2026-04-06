param(
  [string]$ProjectId = "show-talent-5987d",
  [string]$Region = "europe-west1",
  [string]$ApiKey = $env:FIREBASE_WEB_API_KEY,
  [string]$FfmpegPath = "..\functions\node_modules\@ffmpeg-installer\win32-x64\ffmpeg.exe",
  [int]$OptimizeTimeoutSec = 90,
  [int]$ReadyTimeoutSec = 240,
  [int]$ReadyPollSec = 5,
  [switch]$SkipOptimizeLogCheck,
  [switch]$SkipReadyCheck,
  [switch]$SkipPlaybackProbe,
  [switch]$SkipDelete,
  [switch]$KeepAuthUser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-JsonPost {
  param(
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][hashtable]$Body,
    [hashtable]$Headers = @{}
  )

  $jsonBody = $Body | ConvertTo-Json -Depth 30 -Compress

  try {
    return Invoke-RestMethod -Method POST -Uri $Uri -ContentType "application/json" -Headers $Headers -Body $jsonBody -TimeoutSec 90
  } catch {
    if ($_.Exception.Response) {
      $resp = $_.Exception.Response
      $status = [int]$resp.StatusCode
      $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $content = $reader.ReadToEnd()
      $reader.Close()
      throw "POST $Uri failed [$status]: $content"
    }

    throw
  }
}

function New-TinyMp4 {
  param(
    [Parameter(Mandatory = $true)][string]$FfmpegExe,
    [Parameter(Mandatory = $true)][string]$OutputPath
  )

  $cmd = '"' + $FfmpegExe + '" -y -f lavfi -i color=c=black:s=160x120:d=1 -c:v libx264 -pix_fmt yuv420p "' + $OutputPath + '" >nul 2>nul'
  cmd.exe /c $cmd | Out-Null

  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutputPath)) {
    throw "Unable to generate MP4 with ffmpeg at: $FfmpegExe"
  }
}

function Wait-OptimizeLogBySession {
  param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$SessionId,
    [Parameter(Mandatory = $true)][int]$TimeoutSec
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $needle = "videos/$SessionId.mp4"

  while ((Get-Date) -lt $deadline) {
    $logOutput = (& firebase.cmd functions:log --only optimizeMp4Video --lines 200 --project $Project 2>&1 | Out-String)

    if ($LASTEXITCODE -eq 0 -and $logOutput -match [regex]::Escape($needle)) {
      return $true
    }

    Start-Sleep -Seconds 5
  }

  return $false
}

function Convert-FromFirestoreValue {
  param(
    [Parameter(Mandatory = $true)]$Value
  )

  if ($null -eq $Value) {
    return $null
  }

  $propNames = @($Value.PSObject.Properties.Name)

  if ($propNames -contains "nullValue") {
    return $null
  }
  if ($propNames -contains "stringValue") {
    return [string]$Value.stringValue
  }
  if ($propNames -contains "booleanValue") {
    return [bool]$Value.booleanValue
  }
  if ($propNames -contains "integerValue") {
    return [long]$Value.integerValue
  }
  if ($propNames -contains "doubleValue") {
    return [double]$Value.doubleValue
  }
  if ($propNames -contains "timestampValue") {
    return [string]$Value.timestampValue
  }
  if ($propNames -contains "mapValue") {
    return Convert-FromFirestoreFields -Fields $Value.mapValue.fields
  }
  if ($propNames -contains "arrayValue") {
    $items = @()
    $values = $Value.arrayValue.values
    if ($null -eq $values) {
      return $items
    }
    foreach ($item in $values) {
      $items += ,(Convert-FromFirestoreValue -Value $item)
    }
    return $items
  }

  return $Value
}

function Convert-FromFirestoreFields {
  param(
    $Fields
  )

  $parsed = [ordered]@{}
  if ($null -eq $Fields) {
    return $parsed
  }

  foreach ($prop in $Fields.PSObject.Properties) {
    $parsed[$prop.Name] = Convert-FromFirestoreValue -Value $prop.Value
  }

  return $parsed
}

function Get-FirestoreVideoDoc {
  param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$VideoId,
    [Parameter(Mandatory = $true)][string]$IdToken,
    [switch]$AllowNotFound
  )

  $uri = "https://firestore.googleapis.com/v1/projects/$Project/databases/(default)/documents/videos/$VideoId"

  try {
    $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers @{
      Authorization = "Bearer $IdToken"
    } -TimeoutSec 45
  } catch {
    if ($_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode
      if ($AllowNotFound.IsPresent -and $status -eq 404) {
        return $null
      }
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $content = $reader.ReadToEnd()
      $reader.Close()
      throw "GET $uri failed [$status]: $content"
    }
    throw
  }

  return Convert-FromFirestoreFields -Fields $resp.fields
}

function Wait-VideoReady {
  param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$VideoId,
    [Parameter(Mandatory = $true)][string]$IdToken,
    [Parameter(Mandatory = $true)][int]$TimeoutSec,
    [Parameter(Mandatory = $true)][int]$PollSec,
    [hashtable]$StateTracker
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $failureStatuses = @("error", "failed", "failure")
  $attempts = 0

  while ((Get-Date) -lt $deadline) {
    $attempts += 1
    $doc = Get-FirestoreVideoDoc -Project $Project -VideoId $VideoId -IdToken $IdToken

    $status = ""
    if ($doc.ContainsKey("status") -and $doc.status -is [string]) {
      $status = [string]$doc.status
    }
    $optimized = ($doc.ContainsKey("optimized") -and $doc.optimized -eq $true)

    if ($null -ne $StateTracker) {
      $StateTracker["attempts"] = $attempts
      $StateTracker["status"] = $status
      $StateTracker["optimized"] = $optimized
    }

    if ($failureStatuses -contains $status.ToLowerInvariant()) {
      throw "Video entered a failure status while waiting for ready: $status"
    }

    if ($status -eq "ready" -and $optimized) {
      return $doc
    }

    Start-Sleep -Seconds $PollSec
  }

  return $null
}

function Get-PlayableUrls {
  param(
    [Parameter(Mandatory = $true)][hashtable]$VideoDoc
  )

  $urls = New-Object System.Collections.Generic.List[string]
  $seen = New-Object System.Collections.Generic.HashSet[string]

  function Add-Url {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
      return
    }
    $trimmed = $Candidate.Trim()
    if ($seen.Add($trimmed)) {
      $urls.Add($trimmed) | Out-Null
    }
  }

  if ($VideoDoc.ContainsKey("videoUrl") -and $VideoDoc.videoUrl -is [string]) {
    Add-Url -Candidate ([string]$VideoDoc.videoUrl)
  }

  if ($VideoDoc.ContainsKey("playback") -and $VideoDoc.playback -is [hashtable]) {
    $playback = [hashtable]$VideoDoc.playback

    if ($playback.ContainsKey("fallback") -and $playback.fallback -is [hashtable]) {
      $fallback = [hashtable]$playback.fallback
      if ($fallback.ContainsKey("url") -and $fallback.url -is [string]) {
        Add-Url -Candidate ([string]$fallback.url)
      }
    }

    if ($playback.ContainsKey("sourceAsset") -and $playback.sourceAsset -is [hashtable]) {
      $sourceAsset = [hashtable]$playback.sourceAsset
      if ($sourceAsset.ContainsKey("url") -and $sourceAsset.url -is [string]) {
        Add-Url -Candidate ([string]$sourceAsset.url)
      }
    }

    if ($playback.ContainsKey("mp4Sources") -and $playback.mp4Sources -is [object[]]) {
      foreach ($entry in $playback.mp4Sources) {
        if ($entry -is [hashtable] -and $entry.ContainsKey("url") -and $entry.url -is [string]) {
          Add-Url -Candidate ([string]$entry.url)
        }
      }
    }
  }

  if ($VideoDoc.ContainsKey("sources") -and $VideoDoc.sources -is [object[]]) {
    foreach ($entry in $VideoDoc.sources) {
      if ($entry -is [hashtable] -and $entry.ContainsKey("url") -and $entry.url -is [string]) {
        Add-Url -Candidate ([string]$entry.url)
      }
    }
  }

  return @($urls.ToArray())
}

function Probe-PlaybackUrl {
  param(
    [Parameter(Mandatory = $true)][string]$Url
  )

  try {
    $head = Invoke-WebRequest -Method Head -Uri $Url -TimeoutSec 45
    return [ordered]@{
      ok = $true
      method = "HEAD"
      status = [int]$head.StatusCode
      url = $Url
    }
  } catch {
    $headStatus = $null
    if ($_.Exception.Response) {
      $headStatus = [int]$_.Exception.Response.StatusCode
    }

    try {
      $get = Invoke-WebRequest -Method Get -Uri $Url -Headers @{
        Range = "bytes=0-0"
      } -TimeoutSec 45

      return [ordered]@{
        ok = $true
        method = "GET"
        status = [int]$get.StatusCode
        url = $Url
        headStatus = $headStatus
      }
    } catch {
      $getStatus = $null
      if ($_.Exception.Response) {
        $getStatus = [int]$_.Exception.Response.StatusCode
      }

      return [ordered]@{
        ok = $false
        method = "GET"
        status = $getStatus
        url = $Url
        headStatus = $headStatus
        error = $_.Exception.Message
      }
    }
  }
}

$result = [ordered]@{
  success = $false
  startedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  projectId = $ProjectId
  region = $Region
  auth = [ordered]@{}
  createUploadSession = [ordered]@{}
  videoUpload = [ordered]@{}
  requestThumbnailUploadUrl = [ordered]@{}
  thumbnailUpload = [ordered]@{}
  finalizeUpload = [ordered]@{}
  optimizeMp4Video = [ordered]@{
    checked = (-not $SkipOptimizeLogCheck.IsPresent)
    seenInLogs = $null
  }
  waitReady = [ordered]@{
    checked = (-not $SkipReadyCheck.IsPresent)
    attempts = 0
    status = $null
    optimized = $null
    readyObserved = $null
  }
  playback = [ordered]@{
    checked = (-not $SkipPlaybackProbe.IsPresent)
    urlCount = 0
    probedUrl = $null
    probeMethod = $null
    probeStatus = $null
  }
  deleteVideo = [ordered]@{
    attempted = (-not $SkipDelete.IsPresent)
    success = $null
    code = $null
    message = $null
  }
  firestorePostDelete = [ordered]@{
    checked = (-not $SkipDelete.IsPresent)
    missing = $null
  }
}

$idToken = $null
$tmpVideo = $null
$sessionId = $null
$readyDoc = $null

try {
  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "ApiKey missing. Use -ApiKey or set FIREBASE_WEB_API_KEY."
  }

  if ($ReadyTimeoutSec -lt 5) {
    throw "ReadyTimeoutSec must be >= 5."
  }
  if ($ReadyPollSec -lt 1) {
    throw "ReadyPollSec must be >= 1."
  }

  $base = "https://$Region-$ProjectId.cloudfunctions.net"

  if (-not [System.IO.Path]::IsPathRooted($FfmpegPath)) {
    $FfmpegPath = Join-Path $PSScriptRoot $FfmpegPath
  }
  $FfmpegPath = (Resolve-Path $FfmpegPath).Path

  $runTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 8)
  $email = "smoke.upload.$runTs.$suffix@example.com"
  $password = "Tmp!$runTs`Ab9"

  $signUp = Invoke-JsonPost -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$ApiKey" -Body @{
    email = $email
    password = $password
    returnSecureToken = $true
  }

  $idToken = [string]$signUp.idToken
  if (-not $idToken) {
    throw "Firebase Auth signUp did not return idToken."
  }

  $result.auth.email = $email
  $result.auth.localId = [string]$signUp.localId
  $result.auth.tokenObtained = $true

  $authHeaders = @{ Authorization = "Bearer $idToken" }

  $tmpVideo = Join-Path $env:TEMP ("smoke_upload_" + $runTs + ".mp4")
  New-TinyMp4 -FfmpegExe $FfmpegPath -OutputPath $tmpVideo
  $videoBytes = [System.IO.File]::ReadAllBytes($tmpVideo)
  $videoSize = $videoBytes.Length

  $createResp = Invoke-JsonPost -Uri "$base/createUploadSession" -Headers $authHeaders -Body @{
    data = @{
      contentType = "video/mp4"
    }
  }

  $createResult = $createResp.result
  $sessionId = [string]$createResult.sessionId
  if (-not $sessionId) {
    throw "createUploadSession returned no sessionId."
  }

  $videoUploadUrl = [string]$createResult.uploadUrl
  if (-not $videoUploadUrl) {
    throw "createUploadSession returned no uploadUrl for video."
  }

  $result.createUploadSession.sessionId = $sessionId
  $result.createUploadSession.videoPath = [string]$createResult.videoPath
  $result.createUploadSession.thumbnailPath = [string]$createResult.thumbnailPath

  $videoRange = "bytes 0-$($videoSize - 1)/$videoSize"
  $videoUploadResp = Invoke-WebRequest -Method PUT -Uri $videoUploadUrl -Headers @{
    "Content-Type" = "video/mp4"
    "Content-Range" = $videoRange
  } -Body $videoBytes -TimeoutSec 180

  $videoStatus = [int]$videoUploadResp.StatusCode
  $result.videoUpload.status = $videoStatus
  $result.videoUpload.size = $videoSize
  $result.videoUpload.contentRange = $videoRange

  if ($videoStatus -lt 200 -or $videoStatus -ge 300) {
    throw "Video upload failed with HTTP status $videoStatus"
  }

  $thumbB64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEBUQEBAVFhUVFRUVFRUVFRUVFRUVFRUWFhUVFRUYHSggGBolHRUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDg0OGhAQGi0mHyYtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIABQAFAMBIgACEQEDEQH/xAAXAAEBAQEAAAAAAAAAAAAAAAAAAQID/8QAFhEBAQEAAAAAAAAAAAAAAAAAABEh/9oADAMBAAIQAxAAAAHUN0c//8QAGRAAAgMBAAAAAAAAAAAAAAAAAQIAAxES/9oACAEBAAEFAh0Lq7dY8//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQMBAT8BP//EABQRAQAAAAAAAAAAAAAAAAAAABD/2gAIAQIBAT8BP//Z"
  $thumbBytes = [Convert]::FromBase64String($thumbB64)
  $thumbSize = $thumbBytes.Length

  $md5 = [System.Security.Cryptography.MD5]::Create()
  $hashBytes = $md5.ComputeHash($thumbBytes)
  $md5.Dispose()
  $thumbHash = ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()

  $thumbReqResp = Invoke-JsonPost -Uri "$base/requestThumbnailUploadUrl" -Headers $authHeaders -Body @{
    data = @{
      sessionId = $sessionId
      hash = $thumbHash
      size = $thumbSize
      contentType = "image/jpeg"
    }
  }

  $thumbReqResult = $thumbReqResp.result
  $thumbUploadUrl = [string]$thumbReqResult.uploadUrl
  if (-not $thumbUploadUrl) {
    throw "requestThumbnailUploadUrl returned no uploadUrl for thumbnail."
  }

  $result.requestThumbnailUploadUrl.thumbnailPath = [string]$thumbReqResult.thumbnailPath
  $result.requestThumbnailUploadUrl.md5 = $thumbHash
  $result.requestThumbnailUploadUrl.size = $thumbSize

  $thumbRange = "bytes 0-$($thumbSize - 1)/$thumbSize"
  $thumbUploadResp = Invoke-WebRequest -Method PUT -Uri $thumbUploadUrl -Headers @{
    "Content-Type" = "image/jpeg"
    "Content-Range" = $thumbRange
  } -Body $thumbBytes -TimeoutSec 120

  $thumbStatus = [int]$thumbUploadResp.StatusCode
  $result.thumbnailUpload.status = $thumbStatus
  $result.thumbnailUpload.contentRange = $thumbRange

  if ($thumbStatus -lt 200 -or $thumbStatus -ge 300) {
    throw "Thumbnail upload failed with HTTP status $thumbStatus"
  }

  $finalizeResp = Invoke-JsonPost -Uri "$base/finalizeUpload" -Headers $authHeaders -Body @{
    data = @{
      sessionId = $sessionId
      metadata = @{
        description = "SMOKE FLOW $runTs"
        caption = "smoke-flow-$runTs"
        width = 160
        height = 120
        duration = 1
        reportCount = 0
        shareCount = 0
        thumbnailHash = $thumbHash
        thumbnailSize = $thumbSize
        thumbnailContentType = "image/jpeg"
        likes = @()
        reports = @()
      }
    }
  }

  $finalizeOk = [bool]$finalizeResp.result.ok
  $result.finalizeUpload.ok = $finalizeOk

  if (-not $finalizeOk) {
    throw "finalizeUpload returned ok=false"
  }

  if (-not $SkipOptimizeLogCheck.IsPresent) {
    if (-not (Get-Command firebase.cmd -ErrorAction SilentlyContinue)) {
      throw "firebase.cmd not found. Use -SkipOptimizeLogCheck or install firebase-tools."
    }

    $seen = Wait-OptimizeLogBySession -Project $ProjectId -SessionId $sessionId -TimeoutSec $OptimizeTimeoutSec
    $result.optimizeMp4Video.seenInLogs = $seen

    if (-not $seen) {
      throw "optimizeMp4Video log did not include session $sessionId within ${OptimizeTimeoutSec}s"
    }
  }

  if (-not $SkipReadyCheck.IsPresent) {
    $readyDoc = Wait-VideoReady -Project $ProjectId -VideoId $sessionId -IdToken $idToken -TimeoutSec $ReadyTimeoutSec -PollSec $ReadyPollSec -StateTracker $result.waitReady
    $result.waitReady.readyObserved = ($null -ne $readyDoc)
    if ($null -eq $readyDoc) {
      throw "Video did not reach status=ready and optimized=true within ${ReadyTimeoutSec}s."
    }
  }

  if (-not $SkipPlaybackProbe.IsPresent) {
    if ($null -eq $readyDoc) {
      $readyDoc = Get-FirestoreVideoDoc -Project $ProjectId -VideoId $sessionId -IdToken $idToken
    }

    if ($null -eq $readyDoc) {
      throw "Unable to fetch Firestore video document for playback checks."
    }

    $playableUrls = @(Get-PlayableUrls -VideoDoc $readyDoc)
    $result.playback.urlCount = $playableUrls.Count

    if ($playableUrls.Count -eq 0) {
      throw "No playable URL found in Firestore contract (videoUrl/playback/sources)."
    }

    $probe = Probe-PlaybackUrl -Url $playableUrls[0]
    $result.playback.probedUrl = [string]$probe.url
    $result.playback.probeMethod = [string]$probe.method
    $result.playback.probeStatus = $probe.status

    if (-not $probe.ok) {
      throw "Playback probe failed for $($playableUrls[0]): $($probe.error)"
    }
  }

  if (-not $SkipDelete.IsPresent) {
    $deleteResp = Invoke-JsonPost -Uri "$base/deleteVideo" -Headers $authHeaders -Body @{
      data = @{
        videoId = $sessionId
      }
    }

    $deleteResult = $deleteResp.result
    $deleteSuccess = [bool]$deleteResult.success
    $result.deleteVideo.success = $deleteSuccess
    $result.deleteVideo.code = [string]$deleteResult.code
    $result.deleteVideo.message = [string]$deleteResult.message

    if (-not $deleteSuccess) {
      throw "deleteVideo returned success=false (code=$($result.deleteVideo.code))."
    }

    $postDeleteDoc = Get-FirestoreVideoDoc -Project $ProjectId -VideoId $sessionId -IdToken $idToken -AllowNotFound
    $missing = ($null -eq $postDeleteDoc)
    $result.firestorePostDelete.missing = $missing
    if (-not $missing) {
      throw "Video document still exists after deleteVideo."
    }
  }

  $result.success = $true
} catch {
  $result.success = $false
  $result.error = $_.Exception.Message
} finally {
  if ($tmpVideo -and (Test-Path $tmpVideo)) {
    Remove-Item -Force $tmpVideo
  }

  if ($idToken -and -not $KeepAuthUser.IsPresent) {
    try {
      $null = Invoke-JsonPost -Uri "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$ApiKey" -Body @{ idToken = $idToken }
      $result.auth.userCleanup = "deleted"
    } catch {
      $result.auth.userCleanup = "failed"
    }
  } elseif ($KeepAuthUser.IsPresent) {
    $result.auth.userCleanup = "kept"
  }

  $result.finishedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
}

$resultJson = $result | ConvertTo-Json -Depth 30
Write-Output $resultJson

if (-not $result.success) {
  exit 1
}
