# ============================================================
#  Disable-FingerprintPowerSaving.ps1
#  禁用指纹设备节能 + 启用唤醒，自动提权
# ============================================================

# ---------- 自动提权 ----------
$isElevated = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isElevated) {
    Write-Host "正在请求管理员权限..." -ForegroundColor Yellow
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Definition }
    Start-Process powershell.exe -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    exit
}
# ---------- 提权结束 ----------

# ===== 替换为第 1 步获取的 InstanceId =====
$deviceId = '你的指纹设备的InstanceId'
# ==========================================

$changed = $false

# 关闭"允许计算机关闭此设备"
Get-CimInstance -Namespace root\WMI -ClassName MSPower_DeviceEnable `
    -ErrorAction SilentlyContinue |
Where-Object { $_.InstanceName -like "*$deviceId*" } |
ForEach-Object {
    if ($_.Enable -ne $false) {
        $_.Enable = $false
        Set-CimInstance -InputObject $_
        Write-Host "[已禁用节能] $($_.InstanceName)" -ForegroundColor Green
        $changed = $true
    }
}

# 开启"允许此设备唤醒计算机"
Get-CimInstance -Namespace root\WMI -ClassName MSPower_DeviceWakeEnable `
    -ErrorAction SilentlyContinue |
Where-Object { $_.InstanceName -like "*$deviceId*" } |
ForEach-Object {
    if ($_.Enable -ne $true) {
        $_.Enable = $true
        Set-CimInstance -InputObject $_
        Write-Host "[已允许唤醒] $($_.InstanceName)" -ForegroundColor Green
        $changed = $true
    }
}

if (-not $changed) {
    Write-Host "设备已是目标状态，或未匹配到设备，请核对 InstanceId。" -ForegroundColor Yellow
}
