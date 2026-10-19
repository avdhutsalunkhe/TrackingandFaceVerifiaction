# setup_iis_flutter_web.ps1
# Automates setting up Flutter Web for FieldStaff Attendance on IIS Port 8094

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " FieldStaff Attendance - Flutter Web Setup on IIS Port 8094 " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

Import-Module WebAdministration

$Port = 8094
$AppPoolName = "FieldStaff_FlutterWeb_Pool"
$SiteName = "FieldStaff-FlutterWeb"
$WebDir = "C:\Users\Administrator\Desktop\Tracking\repo\mobile\mobile\build\web"
$BackendProxyUrl = "http://127.0.0.1:8084"

# 1. Ensure directory exists
if (-not (Test-Path $WebDir)) {
    Write-Host "`n[1/5] Creating Flutter Web build directory: $WebDir..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $WebDir -Force | Out-Null
} else {
    Write-Host "`n[1/5] Flutter Web directory verified: $WebDir" -ForegroundColor Green
}

# 2. Release port 8094 from any previous site (e.g. usi-frontend)
Write-Host "`n[2/5] Checking existing IIS sites bound to port $Port..." -ForegroundColor Yellow
$allSites = Get-WebSite
foreach ($s in $allSites) {
    $has8094 = $false
    foreach ($b in $s.bindings.Collection) {
        if ($b.bindingInformation -like "*:${Port}:*") {
            $has8094 = $true
            break
        }
    }
    if ($has8094 -and $s.name -ne $SiteName) {
        Write-Host "  Found port $Port bound to site '$($s.name)'. Removing binding / stopping..." -ForegroundColor DarkYellow
        Stop-WebSite -Name $s.name -ErrorAction SilentlyContinue
        # Remove the binding from the old site
        Get-WebBinding -Name $s.name -Port $Port | Remove-WebBinding -ErrorAction SilentlyContinue
    }
}

# 3. Create web.config in build\web with SPA Rewrites, MIME types, and /api Reverse Proxy
Write-Host "`n[3/5] Generating web.config for Flutter Web SPA & API reverse proxy..." -ForegroundColor Yellow
$webConfigContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <staticContent>
      <remove fileExtension=".json" />
      <mimeMap fileExtension=".json" mimeType="application/json" />
      <remove fileExtension=".wasm" />
      <mimeMap fileExtension=".wasm" mimeType="application/wasm" />
      <remove fileExtension=".js" />
      <mimeMap fileExtension=".js" mimeType="application/javascript" />
      <remove fileExtension=".mjs" />
      <mimeMap fileExtension=".mjs" mimeType="application/javascript" />
      <remove fileExtension=".ttf" />
      <mimeMap fileExtension=".ttf" mimeType="font/ttf" />
      <remove fileExtension=".woff" />
      <mimeMap fileExtension=".woff" mimeType="font/woff" />
      <remove fileExtension=".woff2" />
      <mimeMap fileExtension=".woff2" mimeType="font/woff2" />
      <remove fileExtension=".map" />
      <mimeMap fileExtension=".map" mimeType="application/json" />
      <remove fileExtension=".png" />
      <mimeMap fileExtension=".png" mimeType="image/png" />
      <remove fileExtension=".svg" />
      <mimeMap fileExtension=".svg" mimeType="image/svg+xml" />
    </staticContent>

    <httpProtocol>
      <customHeaders>
        <add name="Access-Control-Allow-Origin" value="*" />
        <add name="Access-Control-Allow-Headers" value="Content-Type, Authorization, X-Client-Type" />
        <add name="Access-Control-Allow-Methods" value="GET, POST, PUT, DELETE, OPTIONS" />
      </customHeaders>
    </httpProtocol>

    <rewrite>
      <rules>
        <!-- Reverse Proxy API calls directly to Backend at 8084 -->
        <rule name="ReverseProxyToBackend" stopProcessing="true">
          <match url="^api/(.*)" />
          <action type="Rewrite" url="$BackendProxyUrl/api/{R:1}" />
        </rule>

        <!-- SPA Routing: redirect all non-file/non-directory requests to index.html -->
        <rule name="FlutterSPARoutes" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
            <add input="{REQUEST_URI}" pattern="^/api" negate="true" />
          </conditions>
          <action type="Rewrite" url="/index.html" />
        </rule>
      </rules>
    </rewrite>

    <defaultDocument>
      <files>
        <clear />
        <add value="index.html" />
      </files>
    </defaultDocument>
  </system.webServer>
</configuration>
"@

$webConfigFile = Join-Path $WebDir "web.config"
[System.IO.File]::WriteAllText($webConfigFile, $webConfigContent, [System.Text.Encoding]::UTF8)
Write-Host "  web.config created successfully at $webConfigFile" -ForegroundColor Green

# 4. Configure IIS Application Pool & Website
Write-Host "`n[4/5] Configuring IIS AppPool '$AppPoolName' and Site '$SiteName'..." -ForegroundColor Yellow

# Ensure AppPool exists
if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    Write-Host "  Creating IIS AppPool '$AppPoolName'..." -ForegroundColor Gray
    New-Item -Path "IIS:\AppPools\$AppPoolName" | Out-Null
}
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "enable32BitAppOnWin64" -Value $false
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "startMode" -Value "AlwaysRunning"
Set-ItemProperty -Path "IIS:\AppPools\$AppPoolName" -Name "processModel.idleTimeout" -Value ([TimeSpan]::FromMinutes(0))

# Ensure Website exists
$existingSite = Get-WebSite -Name $SiteName -ErrorAction SilentlyContinue
if ($existingSite) {
    Write-Host "  Stopping and removing previous '$SiteName'..." -ForegroundColor DarkYellow
    Stop-WebSite -Name $SiteName -ErrorAction SilentlyContinue
    Remove-WebSite -Name $SiteName
    Start-Sleep -Seconds 1
}

Write-Host "  Creating IIS Website '$SiteName' on port $Port bound to $WebDir..." -ForegroundColor Green
New-WebSite -Name $SiteName -Port $Port -PhysicalPath $WebDir -ApplicationPool $AppPoolName | Out-Null
Start-Sleep -Seconds 2
Start-WebSite -Name $SiteName -ErrorAction SilentlyContinue

# 5. Verification
Write-Host "`n[5/5] Verifying IIS Flutter Web site on port $Port..." -ForegroundColor Yellow
try {
    $res = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  [SUCCESS] Flutter Web HTTP Status: $($res.StatusCode)" -ForegroundColor Green
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " FLUTTER WEB IS SUCCESSFULLY HOSTED ON IIS PORT $Port! " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host " - Local URL:   http://127.0.0.1:$Port" -ForegroundColor Cyan
    Write-Host " - LAN URL:     http://192.168.1.91:$Port" -ForegroundColor Cyan
    Write-Host " - Public URL:  http://115.244.240.22:$Port" -ForegroundColor Cyan
    Write-Host " - IIS Site:    $SiteName" -ForegroundColor Cyan
    Write-Host " - AppPool:     $AppPoolName" -ForegroundColor Cyan
    Write-Host " - Path:        $WebDir" -ForegroundColor Cyan
} catch {
    Write-Host "  Note: Site configured on port $Port. Index may respond once build completes: $($_.Exception.Message)" -ForegroundColor Yellow
}
