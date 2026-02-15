# This is a sample PowerShell script
# Powershell scripts are meant to run on windows and may crash on unixes.

Write-Output "Stdout logs will be displayed in the task runner"
Write-Error "Stderr logs will also be displayed"

# You can also output structured json messages.
# These messages can be caught and handled in a parent task.
Write-Output 'TRTASK_MESSAGE_PREFIX {"build_status": "PASSED"}'

# Tasks run in the background. Long sleeps are handled gracefully.
Write-Output "Sleeping for 5 seconds"
Start-Sleep -Seconds 5
Write-Output "Sleep finished"

# Exit codes are captured and displayed.
exit 15
