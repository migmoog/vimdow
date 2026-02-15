# This is a sample bash script
# Bash scripts are meant to run on unixes and may crash on windows.

echo "Stdout logs will be displayed in the task runner"
echo "Stderr logs will also be displayed" 1>&2

# You can also output structured json messages.
# These messages can be caught and handled in a parent task.
echo 'TRTASK_MESSAGE_PREFIX {"build_status": "PASSED"}'

# Tasks run in the background. Long sleeps are handled gracefully.
echo "Sleeping for 5 seconds"
sleep 5
echo "Sleep finished"

# Exit codes are captured and displayed.
exit 15
