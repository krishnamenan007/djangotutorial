@echo off
REM Quick Cleanup - Remove all deployment resources

set AWS_REGION=ap-south-1
set CLUSTER_NAME=django-cluster
set SERVICE_NAME=django-service
set ALB_NAME=django-alb
set TARGET_GROUP_NAME=django-target-group
set ALB_SG_NAME=django-alb-sg
set ECS_SG_NAME=django-ecs-sg
set LOG_GROUP_NAME=/ecs/django-polls-app

echo.
echo 🧹 Cleaning up Django deployment resources...
echo =============================================
echo.
echo ⚠️ This will delete:
echo   - ECS service and cluster
echo   - ALB and target group
echo   - Security groups
echo   - CloudWatch logs
echo.

set /p confirm="Continue? (y/N): "
if /i not "%confirm%"=="y" goto cancel

echo.
echo 🛑 Deleting ECS service...
aws ecs delete-service --cluster %CLUSTER_NAME% --service %SERVICE_NAME% --force --region %AWS_REGION% 2>nul
echo ✅ Service deleted

echo 🛑 Deleting ECS cluster...
aws ecs delete-cluster --cluster %CLUSTER_NAME% --region %AWS_REGION% 2>nul
echo ✅ Cluster deleted

echo 🛑 Deleting ALB...
for /f "tokens=*" %%i in ('aws elbv2 describe-load-balancers --names %ALB_NAME% --region %AWS_REGION% --query LoadBalancers[0].LoadBalancerArn --output text 2^>nul') do set ALB_ARN=%%i
if defined ALB_ARN (
    REM Delete listeners first
    for /f "tokens=*" %%i in ('aws elbv2 describe-listeners --load-balancer-arn %ALB_ARN% --region %AWS_REGION% --query Listeners[*].ListenerArn --output text 2^>nul') do aws elbv2 delete-listener --listener-arn %%i --region %AWS_REGION% 2>nul
    aws elbv2 delete-load-balancer --load-balancer-arn %ALB_ARN% --region %AWS_REGION% 2>nul
    echo ✅ ALB deleted
)

echo 🛑 Deleting target group...
aws elbv2 delete-target-group --target-group-arn arn:aws:elasticloadbalancing:%AWS_REGION%:859666865623:targetgroup/%TARGET_GROUP_NAME% --region %AWS_REGION% 2>nul
echo ✅ Target group deleted

echo 🛑 Deleting security groups...
for /f "tokens=*" %%i in ('aws ec2 describe-security-groups --filters "Name=group-name,Values=%ALB_SG_NAME%" "Name=vpc-id,Values=vpc-00bbfbdd0f8cfc2d4" --region %AWS_REGION% --query SecurityGroups[0].GroupId --output text 2^>nul') do aws ec2 delete-security-group --group-id %%i --region %AWS_REGION% 2>nul
for /f "tokens=*" %%i in ('aws ec2 describe-security-groups --filters "Name=group-name,Values=%ECS_SG_NAME%" "Name=vpc-id,Values=vpc-00bbfbdd0f8cfc2d4" --region %AWS_REGION% --query SecurityGroups[0].GroupId --output text 2^>nul') do aws ec2 delete-security-group --group-id %%i --region %AWS_REGION% 2>nul
echo ✅ Security groups deleted

echo 🛑 Deleting CloudWatch log group...
aws logs delete-log-group --log-group-name %LOG_GROUP_NAME% --region %AWS_REGION% 2>nul
echo ✅ Log group deleted

echo.
echo 🎉 Cleanup complete!
echo.
echo 💡 Run 'deploy.bat' to redeploy from scratch.

goto end

:cancel
echo.
echo ❌ Cleanup cancelled.

:end
pause