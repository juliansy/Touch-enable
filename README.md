# Windows-Fingerprint-PowerFix

> 解决 Windows 10/11 开机后指纹设备"允许计算机关闭此设备以节省电源"被自动重新勾选，导致休眠后无法用指纹唤醒的问题。

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-blue.svg)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](https://docs.microsoft.com/powershell/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🐛 问题描述

手动取消勾选指纹设备的 **"允许计算机关闭此设备以节省电源"** 后，关机重启该选项**自动恢复勾选**，导致系统休眠时指纹传感器被断电，无法指纹唤醒。

**已验证环境**：Windows 10 21H2 LTSC + EgisTec Touch Fingerprint Sensor 。

**核心思路**：通过 WMI 直接修改设备电源策略，并用**开机延迟计划任务**在驱动加载完成后自动执行，绕过系统的自动重置。

---

## 📋 解决步骤

### 第 1 步：获取设备 InstanceId

以**管理员身份**打开 PowerShell，运行：

```powershell
Get-PnpDevice -Class Biometric -Status OK | Select-Object FriendlyName, InstanceId
```

记下你的指纹设备对应的 `InstanceId`，例如：

```
USB\VID_1C7A&PID_0570\5&1A2B3C4D&0&1
```

---

### 第 2 步：保存脚本

将以下内容保存为 `Disable-FingerprintPowerSaving.ps1`（放在合适文件夹下，复制脚本文件的位置备用）：

或者下载已发布的文件 `Disable-FingerprintPowerSaving.ps1`

```powershell
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
```

---

### 第 3 步：手动运行验证

双击脚本，或在 PowerShell 中执行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Scripts\Disable-FingerprintPowerSaving.ps1"
```

首次运行会弹出 **UAC 确认框**，点击"是"。看到绿色 `[已禁用节能]` 输出即表示成功。回到设备管理器 → 指纹设备 → 电源管理，确认选项状态。

---

### 第 4 步：配置开机自动执行

打开 **任务计划程序**（`Win + R` → `taskschd.msc`），点击右侧 **"创建任务..."**。

**① 常规**
- 名称：`开机自动禁用指纹节能`
- 勾选 ✅ **"使用最高权限运行"**
- 配置为：`Windows 10`

**② 触发器 → 新建**
- 开始任务：**启动时**
- 勾选 ✅ **"延迟任务"** → `1 分钟` **（可选）**

**③ 操作 → 新建**
- 程序或脚本：`powershell.exe`
- 添加参数：
  ```
  -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Disable-FingerprintPowerSaving.ps1"
  ```

**④ 条件**
- 取消勾选 ❌ **"只有在计算机使用交流电源时才启动此任务"**
- 取消其他所有节能相关限制

**⑤ 设置**
- 勾选 ✅ **"如果任务失败，按以下频率重新启动"**：间隔 `1 分钟`，尝试 `3` 次

保存后右键任务 → **"运行"** 测试一次，然后重启电脑验证。

---

## ✅ 验收

重启后：

1. 设备管理器 → 指纹设备 → 电源管理 → **"允许计算机关闭此设备以节省电源"** 应保持**未勾选**。
2. **"允许此设备唤醒计算机"** 应保持**已勾选**。
3. 系统休眠后可用指纹正常唤醒。

---

## 🩺 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `无法从客户端中访问 CIM 资源` | 未提权 | 检查脚本开头的提权代码是否完整，或用管理员 PowerShell 手动运行 |
| `未找到目标设备` | `InstanceId` 不匹配 | 重新执行第 1 步，检查 `$deviceId` 是否完全一致 |
| 手动运行成功、重启后仍失效 | 任务执行过早 | 触发器延迟改为 `2 分钟` |
| 任务报 `0x80070005` | 权限不足 | 确认勾选"使用最高权限运行" |

**查看执行记录**：任务计划程序 → 选中任务 → 下方 **"历史记录"** 选项卡。

---

## 💻 兼容性

- ✅ 验证于 Windows 10 21H2 LTSC + EgisTec 
- ✅ 适用于所有通过 WMI 暴露 `MSPower_DeviceEnable` 的 PnP 生物识别设备
- ⚠️ 需 PowerShell 5.1+（Windows 10 自带）
- ⚠️ 脚本中的 `$deviceId` **必须替换为你自己的 InstanceId**

---

## 📜 许可证

[MIT License](LICENSE)

> **建议**：操作前创建系统还原点。如出现异常，可在设备管理器中右键指纹设备 → 卸载 → 重启自动重装驱动即可恢复。
