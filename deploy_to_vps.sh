#!/bin/bash
# Deploy storage_manager update to VPS

VPS_HOST="storage.noahcohn.com"
VPS_USER="root"  # Change if needed
REMOTE_DIR="/opt/storage_manager"  # Change to actual path

echo "=== Deploying Storage Manager Update ==="
echo "Host: $VPS_HOST"
echo "Remote dir: $REMOTE_DIR"
echo ""

# Copy updated app.py to VPS
echo "Copying updated app.py..."
scp storage_manager/app.py $VPS_USER@$VPS_HOST:$REMOTE_DIR/

# SSH to restart service
echo "Restarting service..."
ssh $VPS_USER@$VPS_HOST << EOF
    cd $REMOTE_DIR
    
    # Backup current
    cp app.py app.py.backup.$(date +%Y%m%d_%H%M%S)
    
    # Restart (adjust for your setup)
    if systemctl is-active --quiet storage_manager; then
        systemctl restart storage_manager
        echo "Restarted via systemctl"
    elif command -v supervisorctl &> /dev/null; then
        supervisorctl restart storage_manager
        echo "Restarted via supervisor"
    else
        # Kill and restart manually
        pkill -f "uvicorn.*app:app" || true
        sleep 2
        nohup python3 -m uvicorn app:app --host 0.0.0.0 --port 8000 > /var/log/storage_manager.log 2>&1 &
        echo "Restarted manually"
    fi
    
    sleep 3
    
    # Check if running
    if pgrep -f "uvicorn.*app:app" > /dev/null; then
        echo "✅ Service is running"
    else
        echo "❌ Service failed to start"
        exit 1
    fi
EOF

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Test the updated endpoint:"
echo "curl -X PUT https://$VPS_HOST/api/shaders/liquid \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"params\": [{\"name\":\"param1\",\"label\":\"Viscosity\",\"default\":0.5,\"min\":0,\"max\":1}]}'"
