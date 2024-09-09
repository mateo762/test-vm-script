#!/bin/bash

# Function to log commands and their output
log_command() {
    echo "$ $@" >> $logpath
    eval "$@" 2>&1 | tee -a $logpath
    echo "" >> $logpath
}

# Set up logging
sudo touch /var/log/aro_deployment_log
sudo chown $USER:$USER /var/log/aro_deployment_log
logpath=/var/log/aro_deployment_log

echo "Script started" >> $logpath
echo "" >> $logpath

# Check if both arguments are provided
if [ $# -ne 5 ]; then
    log_command echo "Usage: $0 <SPOKE_RG_NAME> <FRONT_DOOR_FQDN> <SP_APP_ID> <SP_PASSWORD> <TENANT_ID>"
    exit 1
fi

# Set variables from command-line arguments
SPOKE_RG_NAME=$1
FRONT_DOOR_FQDN=$2
SP_APP_ID=$3
SP_PASSWORD=$4
TENANT_ID=$5

log_command echo "Logging in using the service principal..."
log_command az login --service-principal -u $SP_APP_ID -p $SP_PASSWORD --tenant $TENANT_ID

log_command echo "Setting up environment..."
log_command AROCLUSTER=$(az aro list -g $SPOKE_RG_NAME --query "[0].name" -o tsv)
log_command LOCATION=$(az aro show -g $SPOKE_RG_NAME -n $AROCLUSTER --query location -o tsv)
log_command apiServer=$(az aro show -g $SPOKE_RG_NAME -n $AROCLUSTER --query apiserverProfile.url -o tsv)
log_command webConsole=$(az aro show -g $SPOKE_RG_NAME -n $AROCLUSTER --query consoleProfile.url -o tsv)

log_command echo "ARO Cluster: $AROCLUSTER"
log_command echo "Location: $LOCATION"

# Log in to ARO cluster
log_command echo "Logging in to ARO cluster..."
log_command kubeadmin_password=$(az aro list-credentials --name $AROCLUSTER --resource-group $SPOKE_RG_NAME --query kubeadminPassword --output tsv)
log_command oc login $apiServer -u kubeadmin -p $kubeadmin_password

log_command oc new-project contoso

log_command oc adm policy add-scc-to-user anyuid -z contoso

log_command echo "Creating Deployment..."
log_command cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: contoso-website
  namespace: contoso
spec:
  selector:
    matchLabels:
      app: contoso-website
  template:
    metadata:
      labels:
        app: contoso-website
    spec:
      containers:
      - name: contoso-website
        image: mcr.microsoft.com/mslearn/samples/contoso-website
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        ports:
        - containerPort: 80
          name: http
      securityContext:
        runAsUser: 0
        fsGroup: 0
EOF

log_command sleep 10

log_command echo "Creating Service..."
log_command cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: contoso-service
  namespace: contoso
spec:
  ports:
    - port: 80
      protocol: TCP
      targetPort: http
      name: http
  selector:
    app: contoso-website
  type: ClusterIP
EOF

log_command sleep 10

log_command echo "Creating Ingress..."
log_command cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: contoso-ingress
  namespace: contoso
spec:
  rules:
    - host: $FRONT_DOOR_FQDN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: contoso-service
                port:
                  number: 80
EOF

echo "Script completed" >> $logpath
