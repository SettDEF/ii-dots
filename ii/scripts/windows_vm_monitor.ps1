# Windows Guest VM Monitor Script
# Save this file inside your Windows VM (e.g. C:\Scripts\vm_monitor.ps1) and set it to run on boot via Task Scheduler.

$host_ip = "192.168.122.1" # Default gateway of QEMU NAT network
$port = "9999"
$url = "http://${host_ip}:${port}/notify"

# Helper function to send notification to the Linux host
function Send-HostNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Urgency = "normal"
    )
    $body = @{
        title = $Title
        message = $Message
        urgency = $Urgency
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 2 > $null
    } catch {
        # Silent ignore if host is unreachable (e.g. during host reboot)
    }
}

# Send a boot notification
Send-HostNotification -Title "Windows VM" -Message "Windows VM has booted and monitoring is active." -Urgency "low"

# Keep track of last checked event log time
$lastCheckTime = [DateTime]::Now

while ($true) {
    # 1. Check Event Log for Errors & Warnings (System and Application logs)
    try {
        $events = Get-WinEvent -LogName System, Application -FilterXPath "*[System[(Level=1 or Level=2) and TimeCreated[@SystemTime >= '$($lastCheckTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))']]]" -ErrorAction SilentlyContinue
        
        foreach ($event in $events) {
            $level = "Warning"
            $urgency = "normal"
            if ($event.Level -eq 1 -or $event.LevelDisplayName -eq "Error") {
                $level = "Error"
                $urgency = "critical"
            }
            
            Send-HostNotification -Title "VM $level ($($event.ProviderName))" -Message $event.Message -Urgency $urgency
        }
    } catch {
        # Event log query failed
    }
    
    $lastCheckTime = [DateTime]::Now

    # 2. Check Disk Space (Notify if below 10% free space)
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        foreach ($disk in $disks) {
            $pctFree = ($disk.FreeSpace / $disk.Size) * 100
            if ($pctFree -lt 10) {
                $freeGB = [Math]::Round($disk.FreeSpace / 1GB, 2)
                Send-HostNotification -Title "VM Low Disk Space" -Message "Drive $($disk.DeviceID) has only ${freeGB} GB ($([Math]::Round($pctFree, 1))%) free space left." -Urgency "critical"
            }
        }
    } catch {
        # Disk query failed
    }

    # Wait 30 seconds before next check
    Start-Sleep -Seconds 30
}
