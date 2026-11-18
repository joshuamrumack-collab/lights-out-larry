@echo off
rem Lights Out, Larry! - build the web version and publish it to itch.io.
rem Exports the HTML5 build, then uploads it with butler to
rem https://dorkteach.itch.io/lights-out-larry (channel "html5").
rem Everything it does is also written to publish_log.txt.
rem Every release: raise the number in VERSION, then double-click this file.

set ITCH_USER=dorkteach
set ITCH_GAME=lights-out-larry
set CHANNEL=html5

cd /d "%~dp0"
echo Publish started %DATE% %TIME% > publish_log.txt

rem Find the butler that ships with the itch app.
set BUTLER=
for /d %%V in ("%APPDATA%\itch\broth\butler\versions\*") do if exist "%%~V\butler.exe" set "BUTLER=%%~V\butler.exe"
if not defined BUTLER (
  where butler >nul 2>nul && set BUTLER=butler
)
if not defined BUTLER (
  echo Could not find butler. Open the itch app once, or install butler from https://itch.io/docs/butler/
  echo Could not find butler >> publish_log.txt
  pause
  exit /b 1
)
echo Using butler: %BUTLER%
echo Using butler: %BUTLER% >> publish_log.txt

echo Building the web version (this takes a minute) ...
call build_web.bat nopause >> publish_log.txt 2>&1
if errorlevel 1 (
  type publish_log.txt
  echo.
  echo The build failed. See the messages above, or send publish_log.txt to Claude.
  pause
  exit /b 1
)
echo Build done.

rem Log in (does nothing if already logged in; opens your browser the first time).
"%BUTLER%" login

echo Uploading to %ITCH_USER%/%ITCH_GAME%:%CHANNEL% ...
"%BUTLER%" push export\web %ITCH_USER%/%ITCH_GAME%:%CHANNEL% --userversion-file VERSION >> publish_log.txt 2>&1
set PUSHERR=%ERRORLEVEL%
type publish_log.txt
if not "%PUSHERR%"=="0" (
  echo.
  echo Upload failed. See the messages above, or send publish_log.txt to Claude.
  pause
  exit /b 1
)
echo.
echo Published! https://%ITCH_USER%.itch.io/%ITCH_GAME%
echo (The very first time: on itch, Edit game ^> Uploads, tick "This file will be
echo  played in the browser" on the html5 upload and delete the old zip upload.)
pause
