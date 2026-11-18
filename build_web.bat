@echo off
rem Lights Out, Larry! - web (HTML5) build.
rem Exports the game to export\web\index.html.
rem Finds your Godot 4.7 editor by itself (and remembers it in godot_path.txt).
rem You can also put the full path after "set GODOT=" below.
rem Once: install the export templates in the Godot editor
rem (Editor > Manage Export Templates > Download).

set GODOT=

cd /d "%~dp0"
if not defined GODOT if exist godot_path.txt set /p GODOT=<godot_path.txt
if defined GODOT if not exist "%GODOT%" set GODOT=
if not defined GODOT if exist "..\AscendantReach\godot_path.txt" set /p GODOT=<"..\AscendantReach\godot_path.txt"
if defined GODOT if not exist "%GODOT%" set GODOT=
if not defined GODOT (
  echo Looking for the Godot editor...
  for %%D in ("%USERPROFILE%\Desktop" "%USERPROFILE%\Downloads" "%USERPROFILE%\Documents" "C:\Godot" "E:\Godot" "%LOCALAPPDATA%\Programs" "C:\Program Files" "C:\Program Files (x86)" "E:\SteamLibrary\steamapps\common\Godot Engine" "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine" "%USERPROFILE%\scoop\apps") do (
    if not defined GODOT if exist "%%~D" (
      for /f "delims=" %%F in ('where /r "%%~D" "Godot_v4.7*win64.exe" 2^>nul') do if not defined GODOT echo %%F | findstr /i /v "console" >nul && set "GODOT=%%F"
    )
  )
)
if not defined GODOT (
  echo Could not find the Godot editor.
  echo Open build_web.bat in Notepad and put the full path after "set GODOT=".
  if not "%1"=="nopause" pause
  exit /b 1
)
> godot_path.txt echo %GODOT%
echo Using Godot: %GODOT%

set /p VER=<VERSION
echo Building Lights Out, Larry! %VER% for the web ...
if exist export\web rmdir /s /q export\web
mkdir export\web
"%GODOT%" --headless --path . --export-release "Web" export\web\index.html
if errorlevel 1 goto failed
if not exist export\web\index.pck goto failed
echo.
echo Done: export\web
if not "%1"=="nopause" pause
exit /b 0

:failed
echo Export failed. If it mentions export templates, install them in the
echo Godot editor: Editor ^> Manage Export Templates ^> Download.
if not "%1"=="nopause" pause
exit /b 1
