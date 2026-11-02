@echo off
setlocal
cd /d "%~dp0"
py -3 --version >nul 2>&1
if errorlevel 1 (
  echo Python 3 was not found. Install Python 3 from https://www.python.org/downloads/windows/
  echo During installation, enable "Add Python to PATH".
  pause
  exit /b 1
)
py -3 -m pip install -r requirements.txt
if errorlevel 1 (
  echo Could not install NOVA Copilot dependencies.
  pause
  exit /b 1
)
py -3 app.py
if errorlevel 1 (
  echo.
  echo NOVA Copilot could not start.
  pause
)
endlocal
