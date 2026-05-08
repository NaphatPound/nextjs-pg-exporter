#!/bin/bash

echo "Creating deployment package..."

# Create deploy folder
rm -rf deploy-package
mkdir deploy-package

echo "Copying built files..."
cp -r .next deploy-package/
cp -r node_modules deploy-package/
if [ -d "public" ]; then
    cp -r public deploy-package/
fi

echo "Copying configuration files..."
cp package.json deploy-package/
cp next.config.js deploy-package/
cp run-windows.bat deploy-package/
cp run-mac.sh deploy-package/
if [ -f ".env.local" ]; then
    cp .env.local deploy-package/
fi

echo ""
echo "✅ Deployment package created in 'deploy-package' folder"
echo ""
echo "Next steps:"
echo "1. Zip the 'deploy-package' folder"
echo "2. Send to users"
echo "3. Users just need to run 'run-windows.bat' or 'run-mac.sh'"
echo ""
