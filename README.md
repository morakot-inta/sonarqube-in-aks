# SonarQube on Kubernetes with External Azure PostgreSQL

This repository contains the configuration for deploying SonarQube in an AKS environment with an external Azure PostgreSQL database.

## Prerequisites

- Azure CLI installed and configured
- kubectl installed and configured
- Helm installed
- An AKS cluster with at least one node
- An Azure PostgreSQL database server
- TLS certificates for HTTPS connections (optional)

## Installation Steps

### 1. Create the SonarQube Database in Azure PostgreSQL

Create a PostgreSQL client pod in the SonarQube namespace to perform database operations:

```sh
# Create namespace
kubectl create namespace sonarqube

# Create PostgreSQL client pod for database operations
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pg-client
  namespace: sonarqube
spec:
  containers:
  - name: pg-client
    image: postgres:16
    command: ["sleep", "3600"]
EOF

# Wait for the client pod to be ready
kubectl wait --for=condition=Ready pod/pg-client -n sonarqube --timeout=60s

# Create SonarQube database
kubectl exec -it pg-client -n sonarqube -- bash -c "PGPASSWORD='H@Sh1CoR3!' psql -h gaia-ec5fe91df091-pg.postgres.database.azure.com -U psqladmin -d postgres -c \"CREATE DATABASE sonarqube OWNER psqladmin ENCODING 'UTF8' TEMPLATE template0;\""
```

### 2. Configure SonarQube Values File

Create a `sonarqube-values.yaml` file with the following content to configure SonarQube to use the external PostgreSQL database:

```yaml
# SonarQube edition
edition: community 

# Setting up external PostgreSQL
postgresql:
  enabled: false # Disable the built-in PostgreSQL

jdbcOverwrite:
  enable: true
  jdbcUrl: "jdbc:postgresql://gaia-ec5fe91df091-pg.postgres.database.azure.com:5432/sonarqube"
  jdbcUsername: "psqladmin"
  jdbcPassword: "H@Sh1CoR3!"

# SonarQube properties
sonarProperties:
  sonar.jdbc.username: psqladmin
  sonar.jdbc.password: H@Sh1CoR3!
  sonar.jdbc.url: jdbc:postgresql://gaia-ec5fe91df091-pg.postgres.database.azure.com:5432/sonarqube

# Persistence configuration  
persistence:
  enabled: true
  storageClass: "default"
  size: 10Gi
  accessMode: ReadWriteOnce

# Service configuration
service:
  type: LoadBalancer

# Elasticsearch settings
elasticsearch:
  bootstrapChecks: false
  javaOpts: "-Xmx512m -Xms512m"
```

### 4. Deploy SonarQube using Helm

Add the SonarQube Helm repository and install SonarQube using the values file:

```sh
# Add the official SonarQube Helm repository
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update

# Set a monitoring passcode (for Developer Edition)
export MONITORING_PASSCODE=P@ssw0rd

# Install or upgrade SonarQube using values file
helm upgrade --install -n sonarqube sonarqube sonarqube/sonarqube -f sonarqube-values.yaml --set monitoringPasscode=$MONITORING_PASSCODE
```

### 5. Verify the Deployment

Check that the SonarQube pods are running:

```sh
kubectl get pods -n sonarqube
```

Check the SonarQube logs to ensure database connection is successful:

```sh
kubectl logs -f -l app=sonarqube -n sonarqube
```

Get the external IP to access SonarQube:

```sh
kubectl get svc -n sonarqube sonarqube-sonarqube -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Important Notes

1. **Persistence**: SonarQube data is persisted using Kubernetes persistent volumes with a size of 10Gi.

2. **HTTPS Configuration**: For production environments, it's recommended to configure HTTPS for secure connections. If you're using OAuth authentication, be aware that HTTP connections may cause OAuth warnings.


Remember to regularly backup your SonarQube database to prevent data loss.
