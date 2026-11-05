@echo off
setlocal
cd /d "%~dp0"
py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" >nul 2>&1
if errorlevel 1 (
  echo Python 3.10 or newer was not found. Install it from https://www.python.org/downloads/windows/
  echo During installation, enable "Add Python to PATH" and install the Python Launcher.
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
