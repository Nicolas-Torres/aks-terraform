1. Instalar local
   1. azure cli, loguear con: az login
   2. terraform
   3. kubelogin
2. En Azure, crear grupo y guardar group_id
1. En Azure, guardar tenant_id
2. En Azure, guardar subscription_id
3. En repo "aks-terraform" ejecutar: terraform init
4. En repo "aks-terraform" ejecutar: terraform plan -var-file=terraform.tfvars -out=mi_plan.tfplan
5. En repo "aks-terraform" ejecutar: terraform apply "mi_plan.tfplan"
6. En Azure, "Conectar" el Servicio de Kubernetes
7. En repo "aks-terraform" ejecutar: az account set --subscription <subscription_id>
8. En repo "aks-terraform" ejecutar: az aks get-credentials --resource-group rg-ntorresv-prod-eus2 --name aks-ntorresv-prod-eus2 --overwrite-existing
9.  En repo "aks-terraform" ejecutar: kubelogin convert-kubeconfig -l azurecli
10. En repo "aks-terraform" ejecutar: kubectl get nodes
11. En repo "aks-terraform" ejecutar: kubectl get pod
12. En repo "aks-terraform" ejecutar: kubectl get deploy
13. En repo "aks-terraform" ejecutar: kubectl describe deploy ml-api
14. En repo "aks-terraform" ejecutar: kubectl logs -f ml-api-5cd6695466-pjnhb
15. Hacer pruebas GET, POST -> Respuesta OK
16. Agregar miembro al grupo creado
17. En repo "aks-terraform" ejecutar: kubectl get deployments --all-namespaces=true
18. En repo "ml-deploy-workshop", en el archivo deployment.yaml actualizar valor de imagen con el registrado en GHCR 
19. En repo "aks-terraform" ejecutar: kubectl apply -f k8s/deployment.yaml
20. En repo "aks-terraform" ejecutar: kubectl get deployments
21. En repo "aks-terraform" ejecutar: kubectl get pod
22. En repo "aks-terraform" ejecutar: kubectl apply -f k8s/service.yaml
23. En repo "aks-terraform" ejecutar: kubectl get svc
24. En Azure, entrando a Application Gateway, copiar el dominio (ntorresv-prod-ingress.eastus2.cloudapp.azure.com)
25. En repo "ml-deploy-workshop", actualizar ingress.yaml con el dominio copiado
26. En repo "aks-terraform" ejecutar: kubectl apply -f k8s/ingress.yaml
27. En repo "aks-terraform" ejecutar: kubectl get ing
28. Hacer pruebas GET, POST -> Respuesta OK
29. En Azure, registrar una aplicacion, guardar id de la aplicacion (cliente)
30. En Azure, en "Certificados y secretos" generar un secreto de cliente
31. En Azure, en Servicio de Kubernetes, agregar control de acceso (IAM) "Administrador de RBAC de Azure Kubernetes Service" al grupo creado en el paso N° 2
32. En GitHub, crear:
    1.  Secret
        1.  AZURE_CLIENT_SECRET
    2.  AKS_CLUSTER_NAME
        1.  AZURE_CLIENT_ID
        2.  AZURE_RESOURCE_GROUP
        3.  AZURE_SUBSCRIPTION_ID
        4.  AZURE_TENANT_ID
33. En GitHub, ejecutar el workflow manualmente: "CD - Deploy a AKS"