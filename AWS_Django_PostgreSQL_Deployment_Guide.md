# AWS Django + PostgreSQL Deployment Guide

## Architecture Overview

```
Internet → ALB (Public Subnet) → ECS Fargate (Public Subnet)
                                      ↓
                            RDS PostgreSQL (Private Subnet)
```

**Key Components:**
- **Django App**: ECS Fargate service in public subnet
- **PostgreSQL DB**: RDS instance in private subnet
- **Load Balancer**: Application Load Balancer for traffic distribution
- **Security**: Database only accessible from application

---

## Prerequisites

- AWS Account with appropriate permissions
- Django application code ready for deployment
- Basic understanding of AWS services

---

## Step 1: Create VPC and Networking

### 1.1 Create VPC
1. Go to **AWS Console → VPC → Your VPCs**
2. Click **Create VPC**
3. Configure:
   - **Name**: `django-vpc`
   - **IPv4 CIDR**: `10.0.0.0/16`
   - **Tenancy**: Default
4. Click **Create VPC**

### 1.2 Create Subnets

#### Public Subnets (for Django app and ALB)
1. Go to **VPC → Subnets**
2. Click **Create subnet**
3. Configure first public subnet:
   - **VPC**: django-vpc
   - **Subnet name**: `django-public-1a`
   - **Availability Zone**: `ap-south-1a`
   - **IPv4 CIDR**: `10.0.0.0/22`
4. Click **Create subnet**

5. Create second public subnet:
   - **Subnet name**: `django-public-1b`
   - **Availability Zone**: `ap-south-1b`
   - **IPv4 CIDR**: `10.0.8.0/22`

#### Private Subnets (for PostgreSQL)
6. Create first private subnet:
   - **Subnet name**: `django-private-1a`
   - **Availability Zone**: `ap-south-1a`
   - **IPv4 CIDR**: `10.0.4.0/22`

7. Create second private subnet:
   - **Subnet name**: `django-private-1b`
   - **Availability Zone**: `ap-south-1b`
   - **IPv4 CIDR**: `10.0.12.0/22`

### 1.3 Create Internet Gateway
1. Go to **VPC → Internet Gateways**
2. Click **Create internet gateway**
3. **Name**: `django-igw`
4. Click **Create internet gateway**
5. Select the IGW and click **Attach to VPC**
6. Select `django-vpc`

### 1.4 Create NAT Gateway
1. Go to **VPC → NAT Gateways**
2. Click **Create NAT gateway**
3. Configure:
   - **Name**: `django-nat-1a`
   - **Subnet**: `django-public-1a`
   - **Elastic IP**: Click **Allocate Elastic IP**
4. Click **Create NAT gateway**

5. Create second NAT Gateway:
   - **Name**: `django-nat-1b`
   - **Subnet**: `django-public-1b`
   - **Elastic IP**: Allocate new Elastic IP

### 1.5 Configure Route Tables

#### Public Route Table
1. Go to **VPC → Route Tables**
2. Find the route table associated with public subnets
3. Click on it and go to **Routes** tab
4. Click **Edit routes**
5. Add route:
   - **Destination**: `0.0.0.0/0`
   - **Target**: `django-igw` (Internet Gateway)
6. Click **Save routes**

#### Private Route Table
1. Go to **VPC → Route Tables**
2. Click **Create route table**
3. Configure:
   - **Name**: `django-private-rt`
   - **VPC**: `django-vpc`
4. Click **Create route table**

5. Go to **Routes** tab
6. Click **Edit routes**
7. Add route:
   - **Destination**: `0.0.0.0/0`
   - **Target**: `django-nat-1a` (NAT Gateway)
8. Click **Save routes**

9. Go to **Subnet associations** tab
10. Click **Edit subnet associations**
11. Select both private subnets: `django-private-1a` and `django-private-1b`
12. Click **Save associations**

---

## Step 2: Create Security Groups

### 2.1 ALB Security Group
1. Go to **EC2 → Security Groups**
2. Click **Create security group**
3. Configure:
   - **Security group name**: `django-alb-sg`
   - **Description**: `Security group for Django ALB`
   - **VPC**: `django-vpc`
4. Click **Create security group**

5. Add inbound rules:
   - **Type**: HTTP, **Source**: `0.0.0.0/0`
   - **Type**: HTTPS, **Source**: `0.0.0.0/0`

### 2.2 ECS Security Group
1. Click **Create security group**
2. Configure:
   - **Security group name**: `django-ecs-sg`
   - **Description**: `Security group for Django ECS tasks`
   - **VPC**: `django-vpc`
3. Click **Create security group**

4. Add inbound rule:
   - **Type**: Custom TCP, **Port**: `8000`, **Source**: `django-alb-sg`

### 2.3 RDS Security Group
1. Click **Create security group**
2. Configure:
   - **Security group name**: `django-rds-sg`
   - **Description**: `Security group for Django PostgreSQL RDS`
   - **VPC**: `django-vpc`
3. Click **Create security group**

4. Add inbound rule:
   - **Type**: PostgreSQL, **Source**: `django-ecs-sg`

---

## Step 3: Create RDS PostgreSQL Database

1. Go to **RDS → Databases**
2. Click **Create database**
3. Choose **Standard create**
4. Engine options:
   - **Engine type**: PostgreSQL
   - **Version**: Latest available
5. Templates: **Free tier**
6. Settings:
   - **DB instance identifier**: `django-postgres`
   - **Master username**: `djangoadmin`
   - **Master password**: `changeme123!` (use a strong password)
   - **Confirm password**: `changeme123!`
7. Instance configuration:
   - **DB instance class**: `db.t3.micro`
   - **Storage**: 20 GB
8. Connectivity:
   - **VPC**: `django-vpc`
   - **DB subnet group**: Create new
     - **Name**: `django-private-subnet-group`
     - **Description**: `Private subnets for Django PostgreSQL RDS`
     - **Availability Zones**: Select both AZs
     - **Subnets**: Select both private subnets
   - **Publicly accessible**: No
   - **VPC security group**: `django-rds-sg`
   - **Database port**: `5432`
9. Additional configuration:
   - **Initial database name**: `postgres`
   - **Backup retention period**: `0` (for free tier)
10. Click **Create database**

---

## Step 4: Set Up Secrets Manager

1. Go to **Secrets Manager**
2. Click **Store a new secret**
3. Choose **Other type of secret**
4. Key/value pairs:
   ```
   username: djangoadmin
   password: changeme123!
   engine: postgres
   host: [RDS endpoint from previous step]
   port: 5432
   dbname: postgres
   ```
5. Click **Next**
6. Configure:
   - **Secret name**: `django/db-creds`
   - **Description**: `Database credentials for Django PostgreSQL RDS`
7. Click **Next**
8. Configure rotation: **Disable automatic rotation**
9. Click **Store**

---

## Step 5: Create IAM Roles

### 5.1 ECS Task Execution Role
1. Go to **IAM → Roles**
2. Click **Create role**
3. Select **AWS service** → **Elastic Container Service**
4. Use case: **Elastic Container Service Task**
5. Click **Next**
6. Attach permissions:
   - `AmazonECSTaskExecutionRolePolicy`
7. Click **Next**
8. Role name: `ecsTaskExecutionRole`
9. Click **Create role**

### 5.2 Add Secrets Manager Permission
1. Find the `ecsTaskExecutionRole` role
2. Click on it to open details
3. Click **Add permissions** → **Create inline policy**
4. JSON policy:
   ```json
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": "secretsmanager:GetSecretValue",
               "Resource": "arn:aws:secretsmanager:ap-south-1:[ACCOUNT-ID]:secret:django/db-creds*"
           }
       ]
   }
   ```
5. Click **Review policy**
6. **Name**: `DjangoSecretsManagerPolicy`
7. Click **Create policy**

---

## Step 6: Set Up ECR Repository

1. Go to **ECR → Repositories**
2. Click **Create repository**
3. Configure:
   - **Repository name**: `django`
   - **Tag immutability**: Disabled
4. Click **Create repository**

---

## Step 7: Create ECS Cluster

1. Go to **ECS → Clusters**
2. Click **Create cluster**
3. Choose **Networking only**
4. Configure:
   - **Cluster name**: `django-cluster`
5. Click **Create**

---

## Step 8: Create Application Load Balancer

1. Go to **EC2 → Load Balancers**
2. Click **Create load balancer**
3. Choose **Application Load Balancer**
4. Configure:
   - **Name**: `django-alb`
   - **Scheme**: Internet-facing
   - **IP address type**: IPv4
5. Network mapping:
   - **VPC**: `django-vpc`
   - **Mappings**: Select both public subnets
6. Security groups: `django-alb-sg`
7. Listeners and routing:
   - **Protocol**: HTTP, **Port**: 80
   - **Default action**: Create target group
     - **Name**: `django-target-group`
     - **Protocol**: HTTP, **Port**: 8000
     - **Target type**: IP
     - **VPC**: `django-vpc`
8. Click **Create load balancer**

---

## Step 9: Create ECS Service

### 9.1 Create Task Definition
1. Go to **ECS → Task definitions**
2. Click **Create new task definition**
3. Choose **Fargate**
4. Configure:
   - **Task definition name**: `django-polls-app`
   - **Task role**: `ecsTaskExecutionRole`
   - **Task execution role**: `ecsTaskExecutionRole`
5. Network mode: `awsvpc`
6. Task size: 0.25 vCPU, 512 MB
7. Container definition:
   - **Container name**: `django-app`
   - **Image URI**: `[ACCOUNT-ID].dkr.ecr.ap-south-1.amazonaws.com/django:latest`
   - **Essential**: Yes
8. Port mappings:
   - **Container port**: 8000, **Protocol**: TCP
9. Environment variables:
   ```
   ENVIRONMENT: production
   DB_SECRET_NAME: django/db-creds
   AWS_REGION: ap-south-1
   SECRET_KEY: django-insecure-production-key-change-this-in-production
   DEBUG: False
   ALLOWED_HOSTS: *
   ```
10. Health check:
    - **Command**: `curl -f http://localhost:8000/health/ || exit 1`
    - **Interval**: 30 seconds
    - **Timeout**: 10 seconds
    - **Retries**: 3
    - **Start period**: 60 seconds
11. Click **Create**

### 9.2 Create Service
1. Go to **ECS → Clusters → django-cluster**
2. Click **Create service**
3. Configure:
   - **Launch type**: Fargate
   - **Task definition**: `django-polls-app`
   - **Service name**: `django-service`
   - **Desired tasks**: 1
4. Networking:
   - **VPC**: `django-vpc`
   - **Subnets**: Select both public subnets
   - **Security groups**: `django-ecs-sg`
   - **Public IP**: Turned on
5. Load balancing:
   - **Load balancer type**: Application Load Balancer
   - **Load balancer**: `django-alb`
   - **Container name**: `django-app`
   - **Container port**: 8000
6. Click **Create service**

---

## Step 10: Prepare Django Application

### 10.1 Update settings.py
Add AWS Secrets Manager integration to your `settings.py`:

```python
import os
import json
import boto3
from botocore.exceptions import ClientError

# Production environment detection
IS_PRODUCTION = os.environ.get('ENVIRONMENT') == 'production'

def get_db_config():
    """Get database configuration from AWS Secrets Manager in production"""
    if IS_PRODUCTION:
        try:
            session = boto3.session.Session()
            client = session.client(
                service_name='secretsmanager',
                region_name=os.environ.get('AWS_REGION', 'ap-south-1')
            )

            secret_name = os.environ.get('DB_SECRET_NAME', 'django/db-creds')
            response = client.get_secret_value(SecretId=secret_name)

            if 'SecretString' in response:
                secret = json.loads(response['SecretString'])
                return {
                    'ENGINE': 'django.db.backends.postgresql',
                    'NAME': secret.get('dbname', 'postgres'),
                    'USER': secret.get('username'),
                    'PASSWORD': secret.get('password'),
                    'HOST': secret.get('host'),
                    'PORT': secret.get('port', '5432'),
                }
        except (ClientError, json.JSONDecodeError, KeyError) as e:
            print(f"Error retrieving database credentials: {e}")
            pass

    # Development fallback
    return {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('POSTGRES_DB', 'djangotutorial'),
        'USER': os.environ.get('POSTGRES_USER', 'postgres'),
        'PASSWORD': os.environ.get('POSTGRES_PASSWORD', 'password'),
        'HOST': os.environ.get('POSTGRES_HOST', 'localhost'),
        'PORT': os.environ.get('POSTGRES_PORT', '5432'),
    }

DATABASES = {
    'default': get_db_config()
}
```

### 10.2 Update requirements.txt
Add boto3 dependency:
```
Django==6.0.1
gunicorn==21.2.0
psycopg2-binary==2.9.9
boto3==1.34.0
```

### 10.3 Create entrypoint.sh
```bash
#!/bin/bash
set -e

echo "🚀 Starting Django Application..."

# Run database migrations
echo "📊 Running database migrations..."
python manage.py migrate --noinput --verbosity=1

# Collect static files
echo "📁 Collecting static files..."
python manage.py collectstatic --noinput --clear --verbosity=0

echo "✅ Application setup complete!"
echo "🌐 Starting application server..."

# Execute the main command
exec "$@"
```

### 10.4 Update Dockerfile
```dockerfile
# Use Python 3.12 slim image as base
FROM python:3.12-slim AS base

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Copy project files
COPY . .

# Copy entrypoint script and make it executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create non-root user
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health/ || exit 1

# Set entrypoint and default command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "2", "myfirstsite.wsgi:application"]
```

---

## Step 11: Deploy Application

### 11.1 Build and Push Docker Image
```bash
# Build image
docker build -t django-app .

# Authenticate with ECR
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin [ACCOUNT-ID].dkr.ecr.ap-south-1.amazonaws.com

# Tag and push
docker tag django-app:latest [ACCOUNT-ID].dkr.ecr.ap-south-1.amazonaws.com/django:latest
docker push [ACCOUNT-ID].dkr.ecr.ap-south-1.amazonaws.com/django:latest
```

### 11.2 Update Task Definition
1. Go to **ECS → Task definitions**
2. Select `django-polls-app`
3. Click **Create new revision**
4. Update the image URI to the new pushed image
5. Click **Create**

### 11.3 Update Service
1. Go to **ECS → Clusters → django-cluster → django-service**
2. Click **Update service**
3. Select the new task definition revision
4. Click **Update**

---

## Step 12: Verification

1. **Check service status**: Ensure 1 task is running
2. **Check ALB DNS**: Get the DNS name from Load Balancers
3. **Test health endpoint**: `curl http://[ALB-DNS]/health/`
4. **Test application**: `curl http://[ALB-DNS]/`
5. **Check logs**: Go to CloudWatch → Log groups → `/ecs/django-polls-app`

---

## Troubleshooting

### Database Connection Issues
- Check security group rules
- Verify Secrets Manager JSON format
- Check RDS endpoint in secrets

### Application Not Starting
- Check ECS task logs in CloudWatch
- Verify IAM permissions
- Check environment variables

### Load Balancer Issues
- Verify target group health
- Check security groups
- Verify subnet configurations

---

## Cost Optimization

- Use `db.t3.micro` for development/testing
- Enable auto-scaling for production
- Configure appropriate backup retention
- Monitor usage and adjust instance sizes

---

## Security Best Practices

- Change default database password
- Use strong SECRET_KEY
- Configure proper ALLOWED_HOSTS in production
- Enable RDS encryption at rest
- Use HTTPS in production (add SSL certificate to ALB)
- Implement proper IAM policies
- Regular security updates

This guide provides a production-ready Django deployment with PostgreSQL in a secure, scalable architecture following AWS best practices.