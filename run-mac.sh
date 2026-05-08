#!/bin/bash

# check if node is installed
if ! command -v node &> /dev/null
then
    echo "Node.js is not installed. Please install it from https://nodejs.org/"
    read -p "Press any key to exit..."
    exit
fi

echo "🚀 Starting CSV Merge Tool..."

# cd to the script directory
cd "$(dirname "$0")"

# install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies (first time only)..."
    npm install
fi

# build if .next/BUILD_ID doesn't exist (dev folder doesn't have it)
if [ ! -f ".next/BUILD_ID" ]; then
    echo "🏗️ Building application..."
    npm run build
fi

echo "✅ App is ready! Opening in your browser..."
# Open browser (macOS)
open http://localhost:3000 &

# start the app
npm run start
