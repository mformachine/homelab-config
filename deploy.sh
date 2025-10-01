#!/bin/bash

echo "Starting n8n Kubernetes Deployment ..."

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect if we need sudo for kubectl
KUBECTL="kubectl"
if ! kubectl get nodes &>/dev/null; then
    if sudo kubectl get nodes &>/dev/null; then
        KUBECTL="sudo kubectl"
        echo -e "${YELLOW}Using sudo for kubectl commands${NC}"
    else
        echo -e "${RED}Cannot access kubectl. Please ensure kubectl is configured properly.${NC}"
        exit 1
    fi
fi

# Function to check command success
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1 failed${NC}"
        exit 1
    fi
}

# Step 1: Delete existing problematic resources
echo -e "${YELLOW}Step 1: Cleaning up existing resources...${NC}"
$KUBECTL delete deployment n8n postgres redis -n n8n-prod --ignore-not-found=true
check_status "Deleted existing deployments"

$KUBECTL delete configmap redis-config -n n8n-prod --ignore-not-found=true
check_status "Deleted existing configmap"

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
$KUBECTL wait --for=delete pod -l app=n8n -n n8n-prod --timeout=60s 2>/dev/null || true
$KUBECTL wait --for=delete pod -l app=postgres -n n8n-prod --timeout=60s 2>/dev/null || true
$KUBECTL wait --for=delete pod -l app=redis -n n8n-prod --timeout=60s 2>/dev/null || true

# Step 2: Apply the fixed configurations
echo -e "${YELLOW}Step 2: Applying fixed configurations...${NC}"

# Apply secrets
$KUBECTL apply -f n8n-secrets.yaml
check_status "Applied secrets"

# Apply storage
$KUBECTL apply -f storage.yaml
check_status "Applied storage configurations"

# Apply backend services
$KUBECTL apply -f backend.yaml
check_status "Applied backend services"

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Step 3: Waiting for PostgreSQL to be ready...${NC}"
$KUBECTL wait --for=condition=ready pod -l app=postgres -n n8n-prod --timeout=120s
check_status "PostgreSQL is ready"

# Wait for Redis to be ready
echo -e "${YELLOW}Step 4: Waiting for Redis to be ready...${NC}"
$KUBECTL wait --for=condition=ready pod -l app=redis -n n8n-prod --timeout=120s
check_status "Redis is ready"

# Apply n8n application
echo -e "${YELLOW}Step 5: Deploying n8n application...${NC}"
$KUBECTL apply -f n8n-app.yaml
check_status "Applied n8n application"

# Apply NodePort service
$KUBECTL apply -f n8n-nodeport.yaml
check_status "Applied NodePort service"

# Wait for n8n to be ready
echo -e "${YELLOW}Step 6: Waiting for n8n to be ready...${NC}"
$KUBECTL wait --for=condition=ready pod -l app=n8n -n n8n-prod --timeout=180s
check_status "n8n is ready"

# Step 7: Display status
echo -e "${YELLOW}Step 7: Checking deployment status...${NC}"
echo ""
echo "=== Pod Status ==="
$KUBECTL get pods -n n8n-prod

echo ""
echo "=== Service Status ==="
$KUBECTL get svc -n n8n-prod

echo ""
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "You can access n8n at: http://<your-node-ip>:30000"
echo ""
echo "To check logs:"
echo "  $KUBECTL logs -f deployment/n8n -n n8n-prod"
echo "  $KUBECTL logs -f deployment/postgres -n n8n-prod"
echo "  $KUBECTL logs -f deployment/redis -n n8n-prod"
