@echo off
REM Quick Deployment Status Check

set AWS_REGION=ap-south-1
set CLUSTER_NAME=django-cluster
set SERVICE_NAME=django-service
set ALB_NAME=django-alb

echo.
echo 📊 Django Deployment Status
echo ===========================
echo.

REM Check ECS service
echo 🚀 ECS Service Status:
aws ecs describe-services --cluster %CLUSTER_NAME% --services %SERVICE_NAME% --region %AWS_REGION% --query 'services[0].[serviceName,status,desiredCount,runningCount,pendingCount]' --output table 2>nul
if %ERRORLEVEL% neq 0 (
    echo ❌ Service not found
    goto end
)
echo.

REM Get ALB DNS
echo 🌐 Application URL:
for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --names %ALB_NAME% --region %AWS_REGION% --query LoadBalancers[0].DNSName --output text 2^>nul') do set ALB_DNS=%%i
if defined ALB_DNS (
    echo http://%ALB_DNS%/
    echo.
    echo 🔍 Health Check:
    echo http://%ALB_DNS%/health/
    echo.
) else (
    echo ❌ ALB not found
    goto end
)

REM Check target health
echo 🎯 Target Health:
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:%AWS_REGION%:859666865623:targetgroup/django-target-group/d78c26ba75327a70 --region %AWS_REGION% --query 'TargetHealthDescriptions[*].TargetHealth.State' --output text 2>nul
if %ERRORLEVEL% neq 0 (
    echo ℹ️ Checking health...
) else (
    echo ✅ Healthy
)
echo.

echo 📝 View logs:
echo aws logs tail /ecs/django-polls-app --region %AWS_REGION% --follow
echo.

echo 🔄 Deployment History:
aws ecs describe-services --cluster django-cluster --services django-service --region %AWS_REGION% --query 'services[0].taskDefinition' --output text 2>nul
if %ERRORLEVEL% equ 0 (
    echo Current Task Definition:
    aws ecs describe-services --cluster django-cluster --services django-service --region %AWS_REGION% --query 'services[0].taskDefinition' --output text
) else (
    echo ℹ️ Service not found
)
echo.

:end
echo.
echo 💡 Tip: Run 'deploy.bat' to redeploy or update your application.