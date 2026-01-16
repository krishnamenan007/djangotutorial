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

echo ✅ New image deployed: %ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:%IMAGE_TAG%
echo.

echo 🔧 Updating task definition with new image...
set NEW_IMAGE=%ACCOUNT_ID%.dkr.ecr.%AWS_REGION%.amazonaws.com/%ECR_REPO%:latest

REM Update the image in task-definition.json
echo Updating task-definition.json with image: %NEW_IMAGE%
powershell -Command "$content = Get-Content 'task-definition.json' -Raw; $content = $content -replace '(?s)\"image\":\s*\"[^\"]*\"', '\"image\": \"%NEW_IMAGE%\"'; Set-Content 'task-definition.json' $content"

REM Verify the update worked
echo Verifying task definition update...
type task-definition.json | findstr /c:"image"
echo ✅ Task definition updated
echo.

echo 🚀 Registering new task definition...
aws ecs register-task-definition --cli-input-json file://task-definition.json --region %AWS_REGION% --no-cli-pager

REM Get the latest task definition revision that was just created
for /f "tokens=*" %%i in ('aws ecs describe-task-definition --task-definition %TASK_FAMILY% --region %AWS_REGION% --query "taskDefinition.revision" --output text') do set LATEST_REVISION=%%i

echo ✅ Registered task definition: %TASK_FAMILY%:%LATEST_REVISION%

echo 🚀 Updating service to use new task definition %TASK_FAMILY%:%LATEST_REVISION%...
aws ecs update-service --cluster %CLUSTER_NAME% --service %SERVICE_NAME% --task-definition %TASK_FAMILY%:%LATEST_REVISION% --force-new-deployment --region %AWS_REGION% --no-cli-pager

echo ✅ Service updated with new task definition %TASK_FAMILY%:%LATEST_REVISION%
echo ✅ Using image version: %IMAGE_TAG%
echo Deployment in progress...
echo.

echo 📊 Check status with: status.bat
echo View logs with: aws logs tail /ecs/django-polls-app --region ap-south-1 --follow
echo.

pause