@echo off
REM Quick Redeploy - Build, push, and update service

set AWS_REGION=ap-south-1
set ACCOUNT_ID=859666865623
set CLUSTER_NAME=django-cluster
set SERVICE_NAME=django-service
set TASK_FAMILY=django-polls-app
set ECR_REPO=django

REM Generate timestamp for versioning
for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value') do set datetime=%%i
set TIMESTAMP=%datetime:~0,8%-%datetime:~8,6%
set IMAGE_TAG=%TIMESTAMP%

echo.
echo 🔄 Quick Redeploy - Version %IMAGE_TAG%
echo ========================================
echo.

echo 📦 Building and pushing new image...
docker build -t django-app:%IMAGE_TAG% .
docker tag django-app:%IMAGE_TAG% %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:%IMAGE_TAG%
docker tag django-app:%IMAGE_TAG% %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:latest

aws ecr get-login-password --region %AWS_REGION% | docker login --username AWS --password-stdin %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com
docker push %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:%IMAGE_TAG%
docker push %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:latest

echo ✅ New image deployed
echo.

echo 🚀 Updating ECS service...
aws ecs register-task-definition --cli-input-json file://task-definition.json --region %AWS_REGION% --no-cli-pager >nul
aws ecs update-service --cluster %CLUSTER_NAME% --service %SERVICE_NAME% --force-new-deployment --region %AWS_REGION% --no-cli-pager >nul

echo ✅ Service updated - deployment in progress
echo.

echo 📊 Check status with: status.bat
echo.

pause