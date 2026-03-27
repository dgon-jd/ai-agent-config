#!/bin/bash

# Sound: rising 3-tone chime
#powershell.exe -c "
#    [System.Console]::Beep(600, 300);
#    [System.Console]::Beep(800, 300);
#    [System.Console]::Beep(1000, 200)
#" 2>/dev/null &

# Windows Toast notification (requires BurntToast or raw PowerShell 5+)
powershell.exe -c "
    Add-Type -AssemblyName System.Windows.Forms;
    \$notify = New-Object System.Windows.Forms.NotifyIcon;
    \$notify.Icon = [System.Drawing.SystemIcons]::Information;
    \$notify.BalloonTipTitle = 'Claude Code';
    \$notify.BalloonTipText = 'Task completed!';
    \$notify.Visible = \$true;
    \$notify.ShowBalloonTip(5000);
    Start-Sleep -Seconds 6;
    \$notify.Dispose()
" 2>/dev/null &

echo -e "\a"
echo '{"continue": true}'
