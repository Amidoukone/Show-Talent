param(
  [string]$ProjectId = "show-talent-5987d",
  [string]$Region = "europe-west1",
  [string]$ApiKey = "firebase-api-key-placeholder",
  [string]$FfmpegPath = "..\functions\node_modules\@ffmpeg-installer\win32-x64\ffmpeg.exe",
  [int]$OptimizeTimeoutSec = 90,
  [switch]$SkipOptimizeLogCheck,
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
}

$idToken = $null
$tmpVideo = $null

try {
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
