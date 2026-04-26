#!/bin/bash

set -e

echo "=============================================="
echo "Deploying Ticketing System to Kubernetes"
echo "=============================================="

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Step 1: Creating namespace..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
echo "✓ Namespace created"

echo ""
echo "Step 2: Deploying PostgreSQL databases..."
kubectl apply -f "$SCRIPT_DIR/postgres.yaml"
echo "Waiting for PostgreSQL pods to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-auth -n ticketing-system --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres-user -n ticketing-system --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres-ticket -n ticketing-system --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres-solution -n ticketing-system --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres-knowledge -n ticketing-system --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres-reward -n ticketing-system --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres-notification -n ticketing-system --timeout=120s
echo "✓ All PostgreSQL pods are ready"

echo ""
echo "Step 3: Deploying Kafka..."
kubectl apply -f "$SCRIPT_DIR/kafka.yaml"
echo "Waiting for Kafka pod to be ready..."
kubectl wait --for=condition=ready pod -l app=kafka -n ticketing-system --timeout=180s
echo "✓ Kafka is ready"

echo ""
echo "Step 4: Deploying microservices..."
kubectl apply -f "$SCRIPT_DIR/services.yaml"
echo "Waiting for microservices to be ready..."
kubectl wait --for=condition=ready pod -l app=api-gateway -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=auth-service -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=user-service -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=ticket-service -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=solution-service -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=knowledge-service -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=reward-service -n ticketing-system --timeout=180s
kubectl wait --for=condition=ready pod -l app=notification-service -n ticketing-system --timeout=180s
echo "✓ All microservices are ready"

echo ""
echo "Step 5: Deploying frontend..."
kubectl apply -f "$SCRIPT_DIR/frontend.yaml"
kubectl wait --for=condition=ready pod -l app=frontend -n ticketing-system --timeout=120s
echo "✓ Frontend is ready"

echo ""
echo "Step 6: Deploying ingress..."
kubectl apply -f "$SCRIPT_DIR/ingress.yaml"
echo "✓ Ingress configured"

echo ""
echo "=============================================="
echo "Deployment Complete!"
echo "=============================================="
echo ""
echo "Make sure to add the following to your /etc/hosts file:"
echo "  127.0.0.1 ticketing.local"
echo ""
echo "Access the application at:"
echo "  http://ticketing.local"
echo ""
echo "To check the status of all pods:"
echo "  kubectl get pods -n ticketing-system"
echo ""
echo "To view logs for a service:"
echo "  kubectl logs -f deployment/<service-name> -n ticketing-system"
echo ""
