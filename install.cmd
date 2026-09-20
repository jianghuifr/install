@echo off
rem ============================================================
rem  Windows 一键入口：绕过执行策略限制调用 install.ps1
rem  用法：双击本文件，或在 cmd 里执行 install.cmd all
rem ============================================================
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (echo [完成] devkit 执行结束) else (echo [错误] devkit 退出码 %RC%)
pause
exit /b %RC%
