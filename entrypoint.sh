#!/bin/bash
set -e

echo "🚀 Starting Django Application..."

# Run database migrations
echo "📊 Running database migrations..."
python manage.py migrate --noinput --verbosity=1

# Collect static files
echo "📁 Collecting static files..."
python manage.py collectstatic --noinput --clear --verbosity=0

# Create cache table if using database cache
echo "💾 Creating cache table..."
python manage.py createcachetable --verbosity=0 2>/dev/null || echo "Cache table creation skipped (not configured)"

# Run any pending management commands
echo "🔧 Running additional setup commands..."
# Add any other startup commands here if needed

echo "✅ Application setup complete!"
echo "🌐 Starting application server..."

# Execute the main command (typically gunicorn or runserver)
exec "$@"