@echo off
setlocal
cd /d "%~dp0"

echo [1/3] Checking Python...
py -3 --version
if errorlevel 1 (
  echo Python 3 was not found. Install Python 3 from https://www.python.org/downloads/windows/
  echo During installation, enable "Add Python to PATH".
  pause
  exit /b 1
)

echo [2/3] Installing build dependencies...
py -3 -m pip install --upgrade pip
py -3 -m pip install -r requirements.txt
py -3 -m pip install "pyinstaller>=6.0,<7.0"
if errorlevel 1 (
  echo Dependency installation failed.
  pause
  exit /b 1
)

echo [3/3] Building the Windows app...
py -3 -m PyInstaller --noconfirm --clean --onefile --windowed --name "NOVA Copilot" --hidden-import pystray._win32 app.py
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)

echo.
echo Build complete: dist\NOVA Copilot.exe
echo You can copy this EXE to your ThinkPad and run it.
pause
endlocal
