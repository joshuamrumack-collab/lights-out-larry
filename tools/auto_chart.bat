@echo off
rem Lights Out, Larry! - auto-beatmap draft tool.
rem Drag a song folder (songs\<song>) or an audio file onto this file.
rem It writes draft charts for every difficulty into the song's song.json,
rem plus preview_<difficulty>.wav files so you can hear the drafts with clicks.
rem First time only: it installs librosa (needs Python from python.org).

cd /d "%~dp0"
if "%~1"=="" (
  echo Drag a song folder or an audio file onto auto_chart.bat
  pause
  exit /b 1
)
set PY=py
where py >nul 2>nul || set PY=python
%PY% -c "import librosa, soundfile" >nul 2>nul || (
  echo Installing librosa (first time only) ...
  %PY% -m pip install -r requirements.txt
)
%PY% auto_chart.py "%~1" --preview %2 %3 %4 %5
pause
