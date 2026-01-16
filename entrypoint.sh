#!/bin/bash
set -e

# Run database migrations
echo "Running database migrations..."
python manage.py migrate --noinput

echo "Starting application server..."
# Execute the main command
exec "$@"