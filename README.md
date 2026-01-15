# Django Tutorial Application

A Django polls application with PostgreSQL database.

## Prerequisites

- Python 3.8+
- Docker and Docker Compose
- pip

## Setup Instructions

### 1. Clone the repository

```bash
git clone <repository-url>
cd djangotutorial
```

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure environment variables

Copy the example environment file and update as needed:

```bash
cp .env.example .env
```

### 4. Start PostgreSQL with Docker

```bash
docker-compose up -d
```

This will start a PostgreSQL container with the following configuration:
- Database: `djangotutorial`
- User: `django_user`
- Password: `django_password`
- Port: `5432`

### 5. Run migrations

```bash
python manage.py migrate
```

### 6. Create a superuser (optional)

```bash
python manage.py createsuperuser
```

### 7. Run the development server

```bash
python manage.py runserver
```

Visit http://localhost:8000 to see your application.

## Database Management

### Check PostgreSQL status

```bash
docker-compose ps
```

### View PostgreSQL logs

```bash
docker-compose logs postgres
```

### Stop PostgreSQL

```bash
docker-compose down
```

### Stop and remove data

```bash
docker-compose down -v
```

### Connect to PostgreSQL directly

```bash
docker-compose exec postgres psql -U django_user -d djangotutorial
```

## Switching Between SQLite and PostgreSQL

The application is configured to use environment variables. To switch databases:

1. **PostgreSQL**: Use the configuration in `.env`
2. **SQLite**: Remove or comment out the database variables in `.env`

## Project Structure

```
djangotutorial/
├── myfirstsite/        # Main Django project
├── polls/              # Polls application
├── docker-compose.yml  # PostgreSQL Docker configuration
├── requirements.txt    # Python dependencies
├── .env               # Environment variables (not in git)
├── .env.example       # Environment template
└── manage.py          # Django management script
```

## Environment Variables

- `DB_ENGINE`: Database engine (default: `django.db.backends.postgresql`)
- `DB_NAME`: Database name
- `DB_USER`: Database user
- `DB_PASSWORD`: Database password
- `DB_HOST`: Database host (default: `localhost`)
- `DB_PORT`: Database port (default: `5432`)
- `SECRET_KEY`: Django secret key
- `DEBUG`: Debug mode (True/False)
