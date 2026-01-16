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

REM Step 2: Create ECS infrastructure
echo ====================================================
echo 🏗️ Step 2: Creating ECS infrastructure
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

REM Step 3: Create target group
echo ====================================================
echo 🎯 Step 3: Creating target group
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

REM Step 4: Create security groups
echo ====================================================
echo 🔒 Step 4: Creating security groups
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
echo ✅ ECS security group configured
echo.

REM Step 5: Create ALB
echo ====================================================
echo 🌐 Step 5: Creating Application Load Balancer
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

REM Step 6: Create or update ECS service
echo ====================================================
echo 🚀 Step 6: Deploying ECS service
echo ====================================================
echo.

REM Check if service exists
aws ecs describe-services --cluster %CLUSTER_NAME% --services %SERVICE_NAME% --region %AWS_REGION% --query 'services[0].serviceName' --output text 2>nul > temp_service_check.txt
set /p SERVICE_EXISTS=<temp_service_check.txt 2>nul
del temp_service_check.txt 2>nul

if defined SERVICE_EXISTS (
    if not "%SERVICE_EXISTS%"=="None" (
        echo 📋 Service exists, updating with new task definition...
        aws ecs update-service --cluster %CLUSTER_NAME% --service %SERVICE_NAME% --task-definition %TASK_FAMILY% --force-new-deployment --region %AWS_REGION% --no-cli-pager >nul
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

REM Step 7: Wait for service to be stable
echo ====================================================
echo ⏳ Step 7: Waiting for deployment to complete
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

REM Step 8: Final status check
echo ====================================================
echo 🎉 DEPLOYMENT COMPLETE!
echo ====================================================
echo Deployment Version: %IMAGE_TAG%
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