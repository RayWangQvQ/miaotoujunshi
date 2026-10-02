@echo off
setlocal
cd /d "%~dp0"

REM One-click local build. ASCII only: Chinese Windows cmd is GBK.
REM Output: dist\miaotoujunshi-windows\miaotoujunshi-windows.exe

if not exist ".venv\Scripts\python.exe" (
    echo Creating virtualenv .venv ...
    python -m venv .venv || goto :fail
)
call ".venv\Scripts\activate.bat" || goto :fail

echo Installing dependencies ...
python -m pip install -r requirements.txt pyinstaller || goto :fail

echo Building ...
pyinstaller --noconfirm --clean jev.spec || goto :fail
copy /Y README.md dist\miaotoujunshi-windows\README.md >nul || goto :fail
copy /Y LICENSE dist\miaotoujunshi-windows\LICENSE >nul || goto :fail
copy /Y NOTICE dist\miaotoujunshi-windows\NOTICE >nul || goto :fail
powershell -NoProfile -Command "Compress-Archive -Path 'dist\miaotoujunshi-windows' -DestinationPath 'dist\miaotoujunshi-windows-preview.zip' -Force" || goto :fail

echo.
echo Build OK.
echo   %cd%\dist\miaotoujunshi-windows\miaotoujunshi-windows.exe
echo   %cd%\dist\miaotoujunshi-windows-preview.zip
echo Ship the whole dist\miaotoujunshi-windows folder: the exe needs the files next to it.
pause
exit /b 0

:fail
echo.
echo Build FAILED. Scroll up for the error.
pause
exit /b 1
