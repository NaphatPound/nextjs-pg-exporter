@echo off
setlocal

where node >nul 2>nul
if %errorlevel% neq 0 (
    echo Node.js is not installed. Please install it from https://nodejs.org/
    pause
    exit /b
)

echo 🚀 Starting CSV Merge Tool...

cd /d "%~dp0"

if not exist "node_modules" (
    echo 📦 Installing dependencies - first time only...
    call npm install
)

if not exist ".next\BUILD_ID" (
    echo 🏗️ Building application...
    call npm run build
)

echo ✅ App is ready! Opening in your browser...
start http://localhost:3000

call npm run start
pause
