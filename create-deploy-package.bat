@echo off
echo Creating deployment package...

REM Create deploy folder
if exist "deploy-package" rmdir /s /q deploy-package
mkdir deploy-package

echo Copying built files...
xcopy /E /I .next deploy-package\.next
xcopy /E /I node_modules deploy-package\node_modules
if exist "public" xcopy /E /I public deploy-package\public

echo Copying configuration files...
copy package.json deploy-package\
copy next.config.js deploy-package\
copy run-windows.bat deploy-package\
copy run-mac.sh deploy-package\
if exist ".env.local" copy .env.local deploy-package\

echo.
echo ✅ Deployment package created in 'deploy-package' folder
echo.
echo Next steps:
echo 1. Zip the 'deploy-package' folder
echo 2. Send to users
echo 3. Users just need to run 'run-windows.bat' or 'run-mac.sh'
echo.
pause
