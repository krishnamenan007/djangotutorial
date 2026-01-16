# Django AWS ECS Fargate Deployment

## 🚀 One-Click Deployment

Deploy your Django application to AWS ECS Fargate with a single command!

## Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Docker** installed and running
3. **AWS Account** with ECS, ECR, ELB, and CloudWatch permissions

## Quick Start

```cmd
# Navigate to the project
cd djangotutorial

# Deploy to AWS ECS Fargate
deploy.bat
```

**That's it!** Your Django app will be live on AWS in minutes.

## What Gets Created

### AWS Resources
- **ECR Repository**: `django` (for Docker images)
- **ECS Cluster**: `django-cluster` (Fargate-enabled)
- **ECS Service**: `django-service` (running your app)
- **Application Load Balancer**: `django-alb` (internet-facing)
- **Target Group**: `django-target-group` (health checks)
- **Security Groups**: `django-alb-sg`, `django-ecs-sg`
- **CloudWatch Log Group**: `/ecs/django-polls-app`

### Application Features
- **Health Checks**: `/health/` endpoint for monitoring
- **Load Balancing**: Automatic traffic distribution
- **Auto Healing**: Unhealthy containers automatically replaced
- **CloudWatch Logging**: Centralized application logs

## Application URLs

After deployment, your app will be available at:
- **Main App**: `http://django-alb-[random].ap-south-1.elb.amazonaws.com/`
- **Health Check**: `http://django-alb-[random].ap-south-1.elb.amazonaws.com/health/`

## Monitoring & Management

```cmd
# Check deployment status (quick)
status.bat

# View application logs
aws logs tail /ecs/django-polls-app --region ap-south-1 --follow

# Check service status (detailed)
aws ecs describe-services --cluster django-cluster --services django-service --region ap-south-1

# Scale to 2 instances
aws ecs update-service --cluster django-cluster --service django-service --desired-count 2 --region ap-south-1

# Redeploy with new code
deploy.bat

# Quick redeploy (if infrastructure exists)
redeploy.bat

# Remove all resources
cleanup.bat
```

## 🗃️ Database Management

### Automatic Setup (Built-in)
✅ **Database migrations** run automatically during container startup
✅ **Static files** are collected automatically
✅ **Cache tables** are created automatically
✅ **Gunicorn server** runs in production mode

### Manual Commands (If Needed)
```cmd
# Run additional Django commands on running tasks
migrate.bat                    # Run migrations
run-command.bat "python manage.py createsuperuser"  # Create admin user
```

### Migration Strategy
- **Automatic**: All setup happens during container startup (`entrypoint.sh`)
- **Zero-touch**: No manual intervention required after deployment
- **Production-ready**: Uses Gunicorn WSGI server instead of development server

**Note**: Container startup handles all Django setup automatically!

## 🔄 Redeployment Process

When you make code changes and want to deploy the latest version:

### Automatic Process
```cmd
# Make your code changes
# Then simply run:
deploy.bat
```

**What happens automatically:**
1. ✅ Builds new Docker image with timestamp tag (e.g., `20260116-143052`)
2. ✅ Pushes image to ECR with both timestamp and `latest` tags
3. ✅ Registers new ECS task definition revision
4. ✅ Updates ECS service with `--force-new-deployment`
5. ✅ Waits for rolling update to complete
6. ✅ Provides new application URL

### Version Tracking
- **Timestamp Tags**: Each deployment gets a unique version (e.g., `20260116-143052`)
- **Latest Tag**: Always points to most recent deployment
- **Task Definition**: Automatically increments revision numbers
- **Zero Downtime**: Rolling deployment maintains service availability

### Checking Deployment Status
```cmd
# Quick status check
status.bat

# Detailed service info
aws ecs describe-services --cluster django-cluster --services django-service --region ap-south-1
```

### Rollback (if needed)
```cmd
# Rollback to previous task definition revision
aws ecs update-service --cluster django-cluster --service django-service --task-definition django-polls-app:8 --region ap-south-1
```
```

## Architecture

```
Internet → ALB (Load Balancer) → Target Group → ECS Service → Fargate Tasks
                                    ↓
                            Health Checks (/health/)
```

## Troubleshooting

If deployment fails:
1. Check AWS CLI configuration: `aws sts get-caller-identity`
2. Verify Docker is running: `docker ps`
3. Check AWS permissions for ECS, ECR, ELB services
4. Review CloudWatch logs for application errors

## Cost Optimization

- **ECS Fargate**: Pay only for actual compute time
- **ALB**: Pay per hour + request count
- **ECR**: Pay per GB stored
- **CloudWatch**: Free tier covers basic logging

## Security

- **Network Isolation**: ECS tasks only accessible through ALB
- **Security Groups**: Least-privilege access control
- **IAM Roles**: Minimal required permissions
- **Health Monitoring**: Automatic failure detection and recovery

---

**Happy Deploying!** 🎉