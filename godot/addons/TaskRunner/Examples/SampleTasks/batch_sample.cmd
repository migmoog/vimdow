@echo off
REM This is a sample batch script
REM Batch scripts are meant to run on windows and may crash on unixes.

echo Stdout logs will be displayed in the task runner
echo Stderr logs will also be displayed 1>&2

REM You can also output structured json messages.
REM These messages can be caught and handled in a parent task.
echo TRTASK_MESSAGE_PREFIX {"build_status": "PASSED"}

REM Exit codes are captured and displayed.
exit /b 15
