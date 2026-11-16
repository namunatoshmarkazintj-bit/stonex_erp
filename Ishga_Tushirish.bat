@echo off
title Stonex ERP Launcher
cd /d "%~dp0"

:: 5500 portini tekshirish
netstat -ano | findstr ":5500" >nul
if %errorlevel% neq 0 (
    start "" /b "C:\Users\USER\AppData\Local\Programs\Python\Python315\python.exe" -m http.server 5500 --directory "app\build\web"
    timeout /t 2 /nobreak >nul
)

:: Dasturni to'liq mustaqil Windows ilovasi (Desktop App) darchasida ochish
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" (
    start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" --app=http://localhost:5500 --window-size=1366,850
) else (
    start "" "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --app=http://localhost:5500 --window-size=1366,850
)
exit
