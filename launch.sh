#!/bin/bash
# Source-License Bash Launcher

echo "Starting Source-License Application..."
echo "Application will be available at: http://localhost:4567"
echo "Admin panel will be available at: http://localhost:4567/admin"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

cd "$(dirname "$0")"

if bundle exec puma -C puma.rb config.ru; then
    echo "Application stopped normally"
else
    echo "Error starting application"
    echo "Please check your configuration and try again."
    read -p "Press Enter to exit"
    exit 1
fi
