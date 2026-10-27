# ----- 目标设备 -----
$deviceId = '替换为你的设备的 InstanceId...'

# ----- 关闭节能 -----
Get-CimInstance -Namespace root\WMI -ClassName MSPower_DeviceEnable -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceName -like "*$deviceId*" } |
    ForEach-Object {
        if ($_.Enable -ne $false) {
            $_.Enable = $false
            Set-CimInstance -InputObject $_
        }
    }
