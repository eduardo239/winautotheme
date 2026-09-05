#Requires -Version 5.1
<#
.SYNOPSIS
    Alterna o tema do Windows 11 automaticamente: claro de dia, escuro a noite.

.DESCRIPTION
    Define AppsUseLightTheme e SystemUsesLightTheme no registro do usuario
    e notifica o Explorer para aplicar o modo sem reiniciar.

    Padrao: claro as 07:00, escuro as 19:00.
    Opcional: nascer/por do sol com latitude e longitude.

.EXAMPLE
    .\WinAutoTheme.ps1
    Aplica o tema correspondente ao horario atual.

.EXAMPLE
    .\WinAutoTheme.ps1 -Install
    Copia o script para %LOCALAPPDATA%\WinAutoTheme e cria a tarefa agendada.

.EXAMPLE
    .\WinAutoTheme.ps1 -Uninstall
    Remove a tarefa agendada e os arquivos instalados.

.EXAMPLE
    .\WinAutoTheme.ps1 -Status
    Mostra o tema atual, o horario de troca e o modo configurado.
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Apply,

    [Parameter(ParameterSetName = 'Light')]
    [switch]$Light,

    [Parameter(ParameterSetName = 'Dark')]
    [switch]$Dark,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Install,

    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    Write-Error 'Este script precisa ser executado no PowerShell do Windows, nao no WSL.'
    exit 1
}

$Script:AppName = 'WinAutoTheme'
$Script:InstallDir = Join-Path $env:LOCALAPPDATA $Script:AppName
$Script:TaskName = $Script:AppName
$Script:ThemeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$Script:DefaultConfig = [ordered]@{
    mode           = 'fixed'
    lightAt        = '07:00'
    darkAt         = '19:00'
    latitude       = -23.5505
    longitude      = -46.6333
    applyToApps    = $true
    applyToSystem  = $true
    wallpaperLight = ''
    wallpaperDark  = ''
}

function Get-ScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Get-ConfigPath {
    $installed = Join-Path $Script:InstallDir 'config.json'
    if (Test-Path -LiteralPath $installed) { return $installed }

    $besideScript = Join-Path (Get-ScriptRoot) 'config.json'
    if (Test-Path -LiteralPath $besideScript) { return $besideScript }

    return $installed
}

function ConvertTo-Hashtable {
    param([Parameter(Mandatory)]$Object)

    if ($Object -is [hashtable]) { return $Object }

    $table = @{}
    foreach ($property in $Object.PSObject.Properties) {
        $table[$property.Name] = $property.Value
    }
    return $table
}

function Get-ThemeConfig {
    $path = Get-ConfigPath
    $config = @{}
    foreach ($key in $Script:DefaultConfig.Keys) {
        $config[$key] = $Script:DefaultConfig[$key]
    }

    if (Test-Path -LiteralPath $path) {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $loaded = ConvertTo-Hashtable $raw
        foreach ($key in $loaded.Keys) {
            $config[$key] = $loaded[$key]
        }
    }

    return $config
}

function Save-ThemeConfig {
    param([Parameter(Mandatory)][hashtable]$Config, [Parameter(Mandatory)][string]$Path)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $ordered = [ordered]@{}
    foreach ($key in $Script:DefaultConfig.Keys) {
        if ($Config.ContainsKey($key)) {
            $ordered[$key] = $Config[$key]
        } else {
            $ordered[$key] = $Script:DefaultConfig[$key]
        }
    }

    $json = $ordered | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-TodayTime {
    param([Parameter(Mandatory)][string]$Value)

    $parsed = [datetime]::ParseExact($Value, 'HH:mm', [cultureinfo]::InvariantCulture)
    return (Get-Date).Date.Add($parsed.TimeOfDay)
}

function Get-SunTimes {
    param(
        [Parameter(Mandatory)][double]$Latitude,
        [Parameter(Mandatory)][double]$Longitude,
        [datetime]$Date = (Get-Date)
    )

    $day = $Date.DayOfYear
    $offsetHours = [TimeZoneInfo]::Local.GetUtcOffset($Date).TotalHours
    $lngHour = $Longitude / 15.0
    $zenith = 90.833

    function Get-EventTime {
        param([double]$ApproxHour, [bool]$Rising)

        $t = $day + (($ApproxHour - $lngHour) / 24.0)
        $M = (0.9856 * $t) - 3.289
        $L = $M + (1.916 * [math]::Sin(($M * [math]::PI) / 180.0)) + (0.020 * [math]::Sin((2.0 * $M * [math]::PI) / 180.0)) + 282.634
        $L = (($L % 360) + 360) % 360

        $RA = [math]::Atan(0.91764 * [math]::Tan(($L * [math]::PI) / 180.0)) * 180.0 / [math]::PI
        $RA = (($RA % 360) + 360) % 360
        $LQuad = [math]::Floor($L / 90.0) * 90.0
        $RaQuad = [math]::Floor($RA / 90.0) * 90.0
        $RA = ($RA + ($LQuad - $RaQuad)) / 15.0

        $sinDec = 0.39782 * [math]::Sin(($L * [math]::PI) / 180.0)
        $cosDec = [math]::Cos([math]::Asin($sinDec))
        $cosH = ([math]::Cos(($zenith * [math]::PI) / 180.0) - ($sinDec * [math]::Sin(($Latitude * [math]::PI) / 180.0))) /
                ($cosDec * [math]::Cos(($Latitude * [math]::PI) / 180.0))

        if ($cosH -gt 1 -or $cosH -lt -1) { return $null }

        if ($Rising) {
            $H = (360.0 - ([math]::Acos($cosH) * 180.0 / [math]::PI)) / 15.0
        } else {
            $H = ([math]::Acos($cosH) * 180.0 / [math]::PI) / 15.0
        }

        $T = $H + $RA - (0.06571 * $t) - 6.622
        $UT = ((($T - $lngHour) % 24) + 24) % 24
        $localHours = ($UT + $offsetHours + 24) % 24
        return $Date.Date.AddHours($localHours)
    }

    $sunrise = Get-EventTime -ApproxHour 6 -Rising $true
    $sunset = Get-EventTime -ApproxHour 18 -Rising $false

    if (-not $sunrise -or -not $sunset) {
        throw 'Nao foi possivel calcular nascer/por do sol para essas coordenadas (dia ou noite polar). Use mode=fixed.'
    }

    return [pscustomobject]@{
        Sunrise = $sunrise
        Sunset  = $sunset
    }
}

function Get-ScheduleWindow {
    param([Parameter(Mandatory)][hashtable]$Config)

    $mode = [string]$Config.mode
    if ($mode -eq 'sunrise') {
        $sun = Get-SunTimes -Latitude ([double]$Config.latitude) -Longitude ([double]$Config.longitude)
        return [pscustomobject]@{
            Mode    = 'sunrise'
            LightAt = $sun.Sunrise
            DarkAt  = $sun.Sunset
        }
    }

    return [pscustomobject]@{
        Mode    = 'fixed'
        LightAt = ConvertTo-TodayTime -Value ([string]$Config.lightAt)
        DarkAt  = ConvertTo-TodayTime -Value ([string]$Config.darkAt)
    }
}

function Test-ShouldUseLightTheme {
    param(
        [Parameter(Mandatory)][datetime]$LightAt,
        [Parameter(Mandatory)][datetime]$DarkAt,
        [datetime]$Now = (Get-Date)
    )

    if ($LightAt -lt $DarkAt) {
        return ($Now -ge $LightAt -and $Now -lt $DarkAt)
    }

    return ($Now -ge $LightAt -or $Now -lt $DarkAt)
}

function Initialize-NativeMethods {
    if ('WinAutoTheme.NativeMethods' -as [type]) { return }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WinAutoTheme {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out UIntPtr lpdwResult);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern bool SystemParametersInfo(
            uint uiAction,
            uint uiParam,
            string pvParam,
            uint fWinIni);
    }
}
"@
}

function Send-ThemeChangeBroadcast {
    Initialize-NativeMethods

    $hwndBroadcast = [IntPtr]0xffff
    $wmSettingChange = [uint32]0x001A
    $smtoAbortIfHung = [uint32]0x0002
    $result = [UIntPtr]::Zero

    foreach ($payload in @('ImmersiveColorSet', 'WindowsThemeElement')) {
        [void][WinAutoTheme.NativeMethods]::SendMessageTimeout(
            $hwndBroadcast,
            $wmSettingChange,
            [UIntPtr]::Zero,
            $payload,
            $smtoAbortIfHung,
            1000,
            [ref]$result
        )
    }
}

function Set-WallpaperIfConfigured {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Papel de parede nao encontrado: $Path"
        return
    }

    Initialize-NativeMethods
    $spiSetDeskWallpaper = [uint32]20
    $spifUpdateIniFile = [uint32]0x01
    $spifSendChange = [uint32]0x02
    $ok = [WinAutoTheme.NativeMethods]::SystemParametersInfo(
        $spiSetDeskWallpaper,
        0,
        (Resolve-Path -LiteralPath $Path).Path,
        ($spifUpdateIniFile -bor $spifSendChange)
    )
    if (-not $ok) {
        Write-Warning 'Falha ao aplicar o papel de parede.'
    }
}

function Get-RegistryDword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [int]$Default = 1
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $Default }

    $item = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
    if (-not $item) { return $Default }
    if ($item.PSObject.Properties.Name -notcontains $Name) { return $Default }

    return [int]$item.$Name
}

function Get-CurrentThemeState {
    $apps = Get-RegistryDword -Path $Script:ThemeKey -Name 'AppsUseLightTheme'
    $system = Get-RegistryDword -Path $Script:ThemeKey -Name 'SystemUsesLightTheme'

    return [pscustomobject]@{
        AppsLight   = [bool]$apps
        SystemLight = [bool]$system
    }
}

function Set-WindowsTheme {
    param(
        [Parameter(Mandatory)][ValidateSet('Light', 'Dark')][string]$Theme,
        [Parameter(Mandatory)][hashtable]$Config
    )

    $useLight = [int]($Theme -eq 'Light')
    if (-not (Test-Path -LiteralPath $Script:ThemeKey)) {
        New-Item -Path $Script:ThemeKey -Force | Out-Null
    }

    if ([bool]$Config.applyToApps) {
        Set-ItemProperty -Path $Script:ThemeKey -Name 'AppsUseLightTheme' -Type DWord -Value $useLight
    }
    if ([bool]$Config.applyToSystem) {
        Set-ItemProperty -Path $Script:ThemeKey -Name 'SystemUsesLightTheme' -Type DWord -Value $useLight
    }

    if ($Theme -eq 'Light') {
        Set-WallpaperIfConfigured -Path ([string]$Config.wallpaperLight)
    } else {
        Set-WallpaperIfConfigured -Path ([string]$Config.wallpaperDark)
    }

    Send-ThemeChangeBroadcast
}

function Write-AppLog {
    param([Parameter(Mandatory)][string]$Message)

    try {
        $logDir = $Script:InstallDir
        if (-not (Test-Path -LiteralPath $logDir)) {
            $logDir = Get-ScriptRoot
        }
        $logPath = Join-Path $logDir 'winautotheme.log'
        $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    } catch {
        # logging is best-effort
    }
}

function Get-DesiredTheme {
    param([Parameter(Mandatory)][hashtable]$Config)

    $window = Get-ScheduleWindow -Config $Config
    if (Test-ShouldUseLightTheme -LightAt $window.LightAt -DarkAt $window.DarkAt) {
        return [pscustomobject]@{ Theme = 'Light'; Window = $window }
    }
    return [pscustomobject]@{ Theme = 'Dark'; Window = $window }
}

function Invoke-ThemeApply {
    param(
        [string]$ForceTheme,
        [switch]$Quiet
    )

    $config = Get-ThemeConfig
    $desired = if ($ForceTheme) {
        [pscustomobject]@{
            Theme  = $ForceTheme
            Window = Get-ScheduleWindow -Config $config
        }
    } else {
        Get-DesiredTheme -Config $config
    }

    $before = Get-CurrentThemeState
    Set-WindowsTheme -Theme $desired.Theme -Config $config
    $label = if ($desired.Theme -eq 'Light') { 'claro' } else { 'escuro' }
    Write-AppLog "Tema $label aplicado (apps=$($config.applyToApps); system=$($config.applyToSystem))."

    if (-not $Quiet) {
        Write-Host "Tema $label aplicado."
        Write-Host ("Horario claro: {0:HH:mm}  |  Horario escuro: {1:HH:mm}  |  Modo: {2}" -f `
            $desired.Window.LightAt, $desired.Window.DarkAt, $desired.Window.Mode)
    }

    return [pscustomobject]@{
        Theme  = $desired.Theme
        Before = $before
        Window = $desired.Window
    }
}

function Show-ThemeStatus {
    $config = Get-ThemeConfig
    $current = Get-CurrentThemeState
    $desired = Get-DesiredTheme -Config $config
    $apps = if ($current.AppsLight) { 'claro' } else { 'escuro' }
    $system = if ($current.SystemLight) { 'claro' } else { 'escuro' }
    $target = if ($desired.Theme -eq 'Light') { 'claro' } else { 'escuro' }

    Write-Host "WinAutoTheme"
    Write-Host ("  Apps:            {0}" -f $apps)
    Write-Host ("  Sistema:         {0}" -f $system)
    Write-Host ("  Desejado agora:  {0}" -f $target)
    Write-Host ("  Modo:            {0}" -f $desired.Window.Mode)
    Write-Host ("  Claro a partir:  {0:HH:mm}" -f $desired.Window.LightAt)
    Write-Host ("  Escuro a partir: {0:HH:mm}" -f $desired.Window.DarkAt)
    Write-Host ("  Config:          {0}" -f (Get-ConfigPath))
    Write-Host ("  Tarefa:          {0}" -f $Script:TaskName)
}

function Install-WinAutoTheme {
    $sourceScript = $PSCommandPath
    if (-not $sourceScript) {
        $sourceScript = $MyInvocation.MyCommand.Path
    }
    if (-not $sourceScript -or -not (Test-Path -LiteralPath $sourceScript)) {
        throw 'Nao foi possivel localizar o script para instalar.'
    }

    if (-not (Test-Path -LiteralPath $Script:InstallDir)) {
        New-Item -ItemType Directory -Path $Script:InstallDir -Force | Out-Null
    }

    $targetScript = Join-Path $Script:InstallDir 'WinAutoTheme.ps1'
    Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

    $configPath = Join-Path $Script:InstallDir 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        $sourceConfig = Join-Path (Get-ScriptRoot) 'config.json'
        if (Test-Path -LiteralPath $sourceConfig) {
            Copy-Item -LiteralPath $sourceConfig -Destination $configPath -Force
        } else {
            Save-ThemeConfig -Config (Get-ThemeConfig) -Path $configPath
        }
    }

    Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false -ErrorAction SilentlyContinue

    $argument = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Apply' -f $targetScript
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument

    $now = Get-Date
    $start = $now.Date.AddMinutes(([math]::Floor($now.TimeOfDay.TotalMinutes / 5) * 5) + 5)
    $repeatTrigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
        -MultipleInstances IgnoreNew `
        -Hidden

    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $Script:TaskName `
        -Action $action `
        -Trigger @($logonTrigger, $repeatTrigger) `
        -Settings $settings `
        -Principal $principal `
        -Description 'Alterna o tema do Windows 11 (claro de dia, escuro a noite).' `
        -Force | Out-Null

    Invoke-ThemeApply | Out-Null
    Write-Host "Instalado em $Script:InstallDir"
    Write-Host "Tarefa agendada '$Script:TaskName' criada (logon + a cada 5 minutos)."
    Write-Host "Edite o arquivo de configuracao se quiser mudar os horarios:"
    Write-Host "  $configPath"
}

function Uninstall-WinAutoTheme {
    Unregister-ScheduledTask -TaskName $Script:TaskName -Confirm:$false -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $Script:InstallDir) {
        Remove-Item -LiteralPath $Script:InstallDir -Recurse -Force
    }

    Write-Host 'WinAutoTheme desinstalado.'
}

switch ($PSCmdlet.ParameterSetName) {
    'Light'     { Invoke-ThemeApply -ForceTheme 'Light' | Out-Null }
    'Dark'      { Invoke-ThemeApply -ForceTheme 'Dark' | Out-Null }
    'Install'   { Install-WinAutoTheme }
    'Uninstall' { Uninstall-WinAutoTheme }
    'Status'    { Show-ThemeStatus }
    default     { Invoke-ThemeApply | Out-Null }
}
