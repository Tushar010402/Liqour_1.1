# Kubernetes Deployment

## Overview

Deploy LiquorPro on Kubernetes for production-grade scaling.

---

## 1. Prerequisites

- Kubernetes 1.25+
- kubectl configured
- Helm 3.0+

---

## 2. Namespace Setup

```bash
kubectl create namespace liquorpro
kubectl config set-context --current --namespace=liquorpro
```

---

## 3. Secrets

```bash
kubectl create secret generic liquorpro-secrets \
  --from-literal=database-password=your_password \
  --from-literal=redis-password=your_password \
  --from-literal=jwt-secret=your_secret
```

---

## 4. Deployment

```bash
# Apply all manifests
kubectl apply -f k8s/

# Or use Helm
helm install liquorpro ./helm/liquorpro
```

---

## 5. Scaling

```bash
# Manual scaling
kubectl scale deployment liquorpro-gateway --replicas=3

# Enable HPA
kubectl apply -f k8s/hpa.yaml
```

---

## 6. Monitoring

```bash
# Check pods
kubectl get pods

# Check services
kubectl get svc

# View logs
kubectl logs -f deployment/liquorpro-gateway
```

---

## 7. Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: liquorpro-ingress
spec:
  rules:
  - host: api.liquorpro.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: liquorpro-gateway
            port:
              number: 8090
```

---

## 8. Troubleshooting

```bash
# Describe pod
kubectl describe pod <pod-name>

# Shell into container
kubectl exec -it <pod-name> -- /bin/sh

# Port forward for debugging
kubectl port-forward svc/liquorpro-gateway 8090:8090
```
