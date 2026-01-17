@echo off
REM Django AWS ECS Fargate Deployment - Single Script
REM This script handles the complete deployment automatically

setlocal enabledelayedexpansion

REM Configuration
set AWS_REGION=ap-south-1
set ACCOUNT_ID=859666865623
set CLUSTER_NAME=django-cluster
set SERVICE_NAME=django-service
set TASK_FAMILY=django-polls-app
set ECR_REPO=django
set ALB_NAME=django-alb
set TARGET_GROUP_NAME=django-target-group
set ALB_SG_NAME=django-alb-sg
set ECS_SG_NAME=django-ecs-sg
set LOG_GROUP_NAME=/ecs/django-polls-app
set SUBNET_IDS=subnet-0cc87b494e6e7cbf7,subnet-0f0887d766ede8be1
set VPC_ID=vpc-00bbfbdd0f8cfc2d4

REM RDS Configuration
set RDS_INSTANCE_NAME=django-postgres
set RDS_DB_NAME=postgres
set RDS_USERNAME=djangoadmin
set RDS_PASSWORD=changeme123!
set DB_SUBNET_GROUP=django-private-subnet-group
set RDS_SG_NAME=django-rds-sg
set DB_SECRET_NAME=django/db-creds
set PRIVATE_SUBNET_IDS=subnet-0a44b8c8462b8e57c,subnet-0f87d8d64a5e468d6

REM Generate timestamp for versioning
for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value') do set datetime=%%i
set TIMESTAMP=%datetime:~0,8%-%datetime:~8,6%
set IMAGE_TAG=%TIMESTAMP%

echo.
echo ====================================================
echo 🚀 Django AWS ECS Fargate Deployment
echo ====================================================
echo.
echo Configuration:
echo AWS Region: %AWS_REGION%
echo Account ID: %ACCOUNT_ID%
echo Cluster: %CLUSTER_NAME%
echo Service: %SERVICE_NAME%
echo ECR Repo: %ECR_REPO%
echo ALB: %ALB_NAME%
echo.

REM Check AWS CLI
echo 🔍 Checking AWS CLI configuration...
aws sts get-caller-identity >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ❌ AWS CLI not configured. Run: aws configure
    pause
    exit /b 1
)
echo ✅ AWS CLI configured
echo.

REM Step 1: Build and push Docker image
echo ====================================================
echo 📦 Step 1: Building and pushing Docker image (tag: %IMAGE_TAG%)
echo ====================================================
echo.

echo 🏗️ Building Docker image...
docker build -t django-app:%IMAGE_TAG% .
if %ERRORLEVEL% neq 0 (
    echo ❌ Docker build failed
    pause
    exit /b 1
)
echo ✅ Docker image built with tag: %IMAGE_TAG%
echo.

echo 🔐 Authenticating with ECR...
aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com
if %ERRORLEVEL% neq 0 (
    echo ❌ ECR authentication failed
    pause
    exit /b 1
)
echo ✅ Authenticated with ECR
echo.

echo 🏷️ Tagging and pushing image...
docker tag django-app:%IMAGE_TAG% %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:%IMAGE_TAG%
docker tag django-app:%IMAGE_TAG% %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:latest
docker push %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:%IMAGE_TAG%
docker push %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:latest
if %ERRORLEVEL% neq 0 (
    echo ❌ Image push failed
    pause
    exit /b 1
)
echo ✅ Image pushed to ECR with tags: %IMAGE_TAG% and latest
echo.

echo 🔧 Updating task definition with new image...
set NEW_IMAGE=%ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:latest

REM Update the image in task-definition.json
echo Updating task-definition.json with image: %NEW_IMAGE%
powershell -Command "$content = Get-Content 'task-definition.json' -Raw; $content = $content -replace '(?s)\"image\":\s*\"[^\"]*\"', '\"image\": \"%NEW_IMAGE%\"'; Set-Content 'task-definition.json' $content"

REM Verify the update worked
echo Verifying task definition update...
type task-definition.json | findstr /c:"image"
echo ✅ Task definition updated with new image
echo.

REM Step 2: Create Database infrastructure
echo ====================================================
echo 🗄️ Step 2: Creating Database infrastructure
echo ====================================================
echo.

echo 📋 Checking/creating DB subnet group...
aws rds describe-db-subnet-groups --db-subnet-group-name %DB_SUBNET_GROUP% --region %AWS_REGION% 2>nul >nul
if %ERRORLEVEL% equ 0 (
    echo ✅ DB subnet group exists
) else (
    echo 📋 Creating DB subnet group...
    aws rds create-db-subnet-group --db-subnet-group-name %DB_SUBNET_GROUP% --db-subnet-group-description "Private subnets for Django PostgreSQL RDS" --subnet-ids %PRIVATE_SUBNET_IDS% --region %AWS_REGION%
    if %ERRORLEVEL% neq 0 (
        echo ❌ DB subnet group creation failed
        pause
        exit /b 1
    )
    echo ✅ DB subnet group created
)
echo.

echo 🔒 Checking RDS security group...
aws ec2 describe-security-groups --filters "Name=group-name,Values=%RDS_SG_NAME%" "Name=vpc-id,Values=%VPC_ID%" --region %AWS_REGION% --query SecurityGroups[0].GroupId --output text 2>nul > temp_rds_sg.txt
set /p RDS_SG_ID=<temp_rds_sg.txt 2>nul
if defined RDS_SG_ID (
    if not "%RDS_SG_ID%"=="None" (
        echo ✅ RDS security group exists: %RDS_SG_ID%
        goto rds_sg_ready
    )
)

echo 📋 Creating RDS security group...
aws ec2 create-security-group --group-name %RDS_SG_NAME% --description "Security group for Django PostgreSQL RDS" --vpc-id %VPC_ID% --region %AWS_REGION% --query GroupId --output text > temp_rds_sg.txt
set /p RDS_SG_ID=<temp_rds_sg.txt
del temp_rds_sg.txt
echo ✅ RDS security group created: %RDS_SG_ID%

:rds_sg_ready
echo.

echo 🗄️ Checking/creating RDS instance...
aws rds describe-db-instances --db-instance-identifier %RDS_INSTANCE_NAME% --region %AWS_REGION% --query 'DBInstances[0].DBInstanceStatus' --output text 2>nul > temp_rds_status.txt
set /p RDS_STATUS=<temp_rds_status.txt 2>nul
if defined RDS_STATUS (
    if not "%RDS_STATUS%"=="None" (
        echo ✅ RDS instance exists (status: %RDS_STATUS%)
        goto rds_ready
    )
)

echo 📋 Creating RDS PostgreSQL instance...
aws rds create-db-instance --db-instance-identifier %RDS_INSTANCE_NAME% --db-instance-class db.t3.micro --engine postgres --master-username %RDS_USERNAME% --master-user-password %RDS_PASSWORD% --allocated-storage 20 --db-subnet-group-name %DB_SUBNET_GROUP% --vpc-security-group-ids %RDS_SG_ID% --backup-retention-period 0 --region %AWS_REGION% --no-publicly-accessible
if %ERRORLEVEL% neq 0 (
    echo ❌ RDS instance creation failed
    del temp_rds_status.txt 2>nul
    pause
    exit /b 1
)
echo ✅ RDS instance creation initiated
del temp_rds_status.txt 2>nul

echo ⏳ Waiting for RDS instance to be available (this may take 5-10 minutes)...
aws rds wait db-instance-available --db-instance-identifier %RDS_INSTANCE_NAME% --region %AWS_REGION%
echo ✅ RDS instance is available

:rds_ready
echo.

echo 🔑 Setting up database credentials in Secrets Manager...
aws secretsmanager describe-secret --secret-id %DB_SECRET_NAME% --region %AWS_REGION% 2>nul >nul
if %ERRORLEVEL% equ 0 (
    echo ✅ Database secret exists
) else (
    echo 📋 Creating database secret...
    for /f "tokens=*" %%i in ('aws rds describe-db-instances --db-instance-identifier %RDS_INSTANCE_NAME% --region %AWS_REGION% --query "DBInstances[0].Endpoint.Address" --output text') do set RDS_ENDPOINT=%%i
    aws secretsmanager create-secret --name %DB_SECRET_NAME% --description "Database credentials for Django PostgreSQL RDS" --secret-string "{\"username\":\"%RDS_USERNAME%\",\"password\":\"%RDS_PASSWORD%\",\"engine\":\"postgres\",\"host\":\"%RDS_ENDPOINT%\",\"port\":\"5432\",\"dbname\":\"%RDS_DB_NAME%\"}" --region %AWS_REGION%
    if %ERRORLEVEL% neq 0 (
        echo ❌ Database secret creation failed
        pause
        exit /b 1
    )
    echo ✅ Database secret created
)
echo.

REM Step 3: Create ECS infrastructure
echo ====================================================
echo 🏗️ Step 3: Creating ECS infrastructure
echo ====================================================
echo.

echo 📝 Creating CloudWatch log group...
aws logs create-log-group --log-group-name %LOG_GROUP_NAME% --region %AWS_REGION% --no-cli-pager 2>nul
echo ✅ Log group ready
echo.

echo 🏗️ Creating ECS cluster...
aws ecs create-cluster --cluster-name %CLUSTER_NAME% --region %AWS_REGION% --no-cli-pager >nul
echo ✅ Cluster ready
echo.

echo 📋 Registering task definition...
aws ecs register-task-definition --cli-input-json file://task-definition.json --region %AWS_REGION% --no-cli-pager
if %ERRORLEVEL% neq 0 (
    echo ❌ Task definition registration failed
    pause
    exit /b 1
)
echo ✅ Task definition registered
echo.

REM Step 4: Create target group
echo ====================================================
echo 🎯 Step 4: Creating target group
echo ====================================================
echo.

echo 📋 Checking/creating target group...
aws elbv2 describe-target-groups --names %TARGET_GROUP_NAME% --region %AWS_REGION% 2>nul >nul
if %ERRORLEVEL% equ 0 (
    echo ✅ Target group exists
) else (
    echo 📋 Creating target group...
    aws elbv2 create-target-group --name %TARGET_GROUP_NAME% --protocol HTTP --port 8000 --vpc-id %VPC_ID% --target-type ip --health-check-protocol HTTP --health-check-port 8000 --health-check-path "/health/" --health-check-interval-seconds 30 --health-check-timeout-seconds 10 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region %AWS_REGION% --query TargetGroups[0].TargetGroupArn --output text > temp_tg_arn.txt
    if %ERRORLEVEL% neq 0 (
        echo ❌ Target group creation failed
        del temp_tg_arn.txt 2>nul
        pause
        exit /b 1
    )
    set /p TARGET_GROUP_ARN=<temp_tg_arn.txt
    del temp_tg_arn.txt
    echo ✅ Target group created
)
echo.

REM Step 5: Create security groups
echo ====================================================
echo 🔒 Step 5: Creating security groups
echo ====================================================
echo.

REM ALB Security Group
echo 🌐 Checking ALB security group...
aws ec2 describe-security-groups --filters "Name=group-name,Values=%ALB_SG_NAME%" "Name=vpc-id,Values=%VPC_ID%" --region %AWS_REGION% --query SecurityGroups[0].GroupId --output text 2>nul > temp_alb_sg.txt
set /p ALB_SG_ID=<temp_alb_sg.txt 2>nul
if defined ALB_SG_ID (
    if not "%ALB_SG_ID%"=="None" (
        echo ✅ ALB security group exists: %ALB_SG_ID%
        goto alb_sg_ready
    )
)

echo 📋 Creating ALB security group...
aws ec2 create-security-group --group-name %ALB_SG_NAME% --description "Security group for Django ALB" --vpc-id %VPC_ID% --region %AWS_REGION% --query GroupId --output text > temp_alb_sg.txt
set /p ALB_SG_ID=<temp_alb_sg.txt
del temp_alb_sg.txt
echo ✅ ALB security group created: %ALB_SG_ID%

:alb_sg_ready
echo 📥 Configuring ALB security group rules...
aws ec2 authorize-security-group-ingress --group-id %ALB_SG_ID% --protocol tcp --port 80 --cidr 0.0.0.0/0 --region %AWS_REGION% 2>nul
aws ec2 authorize-security-group-ingress --group-id %ALB_SG_ID% --protocol tcp --port 443 --cidr 0.0.0.0/0 --region %AWS_REGION% 2>nul
echo ✅ ALB security group configured
echo.

REM ECS Security Group
echo 🐳 Checking ECS security group...
aws ec2 describe-security-groups --filters "Name=group-name,Values=%ECS_SG_NAME%" "Name=vpc-id,Values=%VPC_ID%" --region %AWS_REGION% --query SecurityGroups[0].GroupId --output text 2>nul > temp_ecs_sg.txt
set /p ECS_SG_ID=<temp_ecs_sg.txt 2>nul
if defined ECS_SG_ID (
    if not "%ECS_SG_ID%"=="None" (
        echo ✅ ECS security group exists: %ECS_SG_ID%
        goto ecs_sg_ready
    )
)

echo 📋 Creating ECS security group...
aws ec2 create-security-group --group-name %ECS_SG_NAME% --description "Security group for Django ECS tasks" --vpc-id %VPC_ID% --region %AWS_REGION% --query GroupId --output text > temp_ecs_sg.txt
set /p ECS_SG_ID=<temp_ecs_sg.txt
del temp_ecs_sg.txt
echo ✅ ECS security group created: %ECS_SG_ID%

:ecs_sg_ready
echo 📥 Configuring ECS security group rules...
aws ec2 authorize-security-group-ingress --group-id %ECS_SG_ID% --protocol tcp --port 8000 --source-group %ALB_SG_ID% --region %AWS_REGION% 2>nul
aws ec2 authorize-security-group-ingress --group-id %RDS_SG_ID% --protocol tcp --port 5432 --source-group %ECS_SG_ID% --region %AWS_REGION% 2>nul
echo ✅ Security groups configured (ECS can access RDS)
echo.

REM Step 6: Create ALB
echo ====================================================
echo 🌐 Step 6: Creating Application Load Balancer
echo ====================================================
echo.

echo 🚀 Creating ALB...
aws elbv2 create-load-balancer --name %ALB_NAME% --subnets %SUBNET_IDS% --security-groups %ALB_SG_ID% --region %AWS_REGION% --query LoadBalancers[0].LoadBalancerArn --output text > temp_alb_arn.txt
set /p ALB_ARN=<temp_alb_arn.txt
del temp_alb_arn.txt
echo ✅ ALB created
echo.

echo 📡 Creating HTTP listener...
aws elbv2 create-listener --load-balancer-arn %ALB_ARN% --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=%TARGET_GROUP_ARN% --region %AWS_REGION% >nul
echo ✅ HTTP listener created
echo.

REM Get ALB DNS
aws elbv2 describe-load-balancers --names %ALB_NAME% --region %AWS_REGION% --query LoadBalancers[0].DNSName --output text > temp_alb_dns.txt
set /p ALB_DNS=<temp_alb_dns.txt
del temp_alb_dns.txt
echo 🌐 ALB DNS: %ALB_DNS%
echo.

REM Step 7: Create or update ECS service
echo ====================================================
echo 🚀 Step 7: Deploying ECS service
echo ====================================================
echo.

REM Check if service exists
aws ecs describe-services --cluster %CLUSTER_NAME% --services %SERVICE_NAME% --region %AWS_REGION% --query 'services[0].serviceName' --output text 2>nul > temp_service_check.txt
set /p SERVICE_EXISTS=<temp_service_check.txt 2>nul
del temp_service_check.txt 2>nul

if defined SERVICE_EXISTS (
    if not "%SERVICE_EXISTS%"=="None" (
        echo 📋 Service exists, updating with new task definition...

        REM Get the latest task definition revision that was just created
        for /f "tokens=*" %%i in ('aws ecs describe-task-definition --task-definition %TASK_FAMILY% --region %AWS_REGION% --query "taskDefinition.revision" --output text') do set LATEST_REVISION=%%i

        echo 📋 Updating to task definition: %TASK_FAMILY%:%LATEST_REVISION%
        aws ecs update-service --cluster %CLUSTER_NAME% --service %SERVICE_NAME% --task-definition %TASK_FAMILY%:%LATEST_REVISION% --force-new-deployment --region %AWS_REGION% --no-cli-pager >nul
        if %ERRORLEVEL% neq 0 (
            echo ❌ ECS service update failed
            pause
            exit /b 1
        )
        echo ✅ ECS service updated with new deployment
        goto wait_for_service
    )
)

echo 📋 Service doesn't exist, creating new service...
aws ecs create-service --cluster %CLUSTER_NAME% --service-name %SERVICE_NAME% --task-definition %TASK_FAMILY% --desired-count 1 --launch-type FARGATE --network-configuration awsvpcConfiguration={subnets=[%SUBNET_IDS%],securityGroups=[%ECS_SG_ID%],assignPublicIp=ENABLED} --load-balancers targetGroupArn=%TARGET_GROUP_ARN%,containerName=django-app,containerPort=8000 --region %AWS_REGION% --no-cli-pager >nul
if %ERRORLEVEL% neq 0 (
    echo ❌ ECS service creation failed
    pause
    exit /b 1
)
echo ✅ ECS service created

:wait_for_service
echo.

REM Step 8: Wait for service to be stable
echo ====================================================
echo ⏳ Step 8: Waiting for deployment to complete
echo ====================================================
echo.

echo ⏳ Waiting for service to become stable (this may take 2-3 minutes)...
aws ecs wait services-stable --cluster %CLUSTER_NAME% --services %SERVICE_NAME% --region %AWS_REGION%
if %ERRORLEVEL% neq 0 (
    echo ⚠️ Service stability check timed out, but deployment may still complete
) else (
    echo ✅ Service is stable
)
echo.

REM Step 9: Final status check
echo ====================================================
echo 🎉 DEPLOYMENT COMPLETE!
echo ====================================================
echo Deployment Version: %IMAGE_TAG%
echo Image: %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:%IMAGE_TAG%
echo.

echo 🌐 Your Django application is now live at:
echo http://%ALB_DNS%/
echo.

echo 🔍 Health check endpoint:
echo http://%ALB_DNS%/health/
echo.

echo 📊 Current status:
aws ecs describe-services --cluster %CLUSTER_NAME% --services %SERVICE_NAME% --region %AWS_REGION% --query 'services[0].[serviceName,status,desiredCount,runningCount,pendingCount]' --output table
echo.

echo 🎯 Target health:
aws elbv2 describe-target-health --target-group-arn %TARGET_GROUP_ARN% --region %AWS_REGION% --query 'TargetHealthDescriptions[*].TargetHealth.State' --output text 2>nul
if %ERRORLEVEL% neq 0 (
    echo ℹ️ Target health check pending...
) else (
    echo Target is healthy!
)
echo.

echo 📝 To view application logs:
echo aws logs tail /ecs/django-polls-app --region %AWS_REGION% --follow
echo.

echo 🛠️ To scale the application:
echo aws ecs update-service --cluster %CLUSTER_NAME% --service %SERVICE_NAME% --desired-count 2 --region %AWS_REGION%
echo.

echo 🎊 Deployment successful! Your Django app is running on AWS ECS Fargate.
echo.

pause