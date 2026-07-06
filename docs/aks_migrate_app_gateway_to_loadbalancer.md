# Despliegue en AKS: de Application Gateway a LoadBalancer

Este documento registra el proceso completo de optimización de costos de la infraestructura de Azure de este proyecto: el diagnóstico, la decisión, la implementación, y el troubleshooting real que surgió en el camino. Sirve como referencia para futuras sesiones y como registro de por qué la arquitectura actual es la que es.

---

## 1. Contexto: origen de la arquitectura

Este proyecto nació del taller `ml-deploy-workshop`, cuyo diseño original está pensado para correr 100% local con **minikube** — costo $0, sin ningún componente de Azure. Los requisitos previos del taller son Python, Docker Desktop, minikube y kubectl; nada de Terraform ni cloud.

La infraestructura en `aks-terraform` (AKS real, Application Gateway + AGIC, Cilium como dataplane eBPF, Azure CNI Overlay, node pools separados de sistema/usuario, Workload Identity) es una **extensión propia**, no parte del taller — construida deliberadamente para practicar patrones de nivel empresarial en un cloud real. Es una decisión de aprendizaje legítima, pero tiene un costo asociado que no era consciente hasta que se revisó Cost Management.

---

## 2. El problema: diagnóstico de costos

Revisando Azure Cost Management + Billing, el proyecto generó **~$91 en 7 días** (proyección ~$104), con este desglose:

| Servicio | Costo (7 días) | Causa |
|---|---|---|
| Application Gateway | $53.65 | SKU `Standard_v2`, costo fijo por hora independiente del tráfico |
| Virtual Machines | $28.81 | Node pools del AKS (`Standard_D2s_v3`, 1 nodo por pool) |
| Storage | $7.27 | Discos administrados de esos nodos |
| Virtual Network / Load Balancer | $1.53 | Marginal |

**Causa raíz**: el SKU `Standard_v2` de Application Gateway cobra un costo fijo (~$0.246/hora ≈ $180/mes) **incluso con cero tráfico** — es una tarifa por tener el recurso provisionado y disponible, no por uso. Para un proyecto personal con tráfico de pruebas ocasional, es el equivalente a alquilar infraestructura dimensionada para producción real.

Los node pools, en cambio, ya estaban correctamente ajustados (`Standard_D2s_v3`, 1 nodo cada uno) — no se tocaron en esta optimización.

---

## 3. Decisión: plan de 3 niveles

- **Nivel 1** (implementado): reemplazar Application Gateway + AGIC por un `Service` de Kubernetes tipo `LoadBalancer` — mismo dominio público, sin el costo fijo del gateway.
- **Nivel 2** (implementado): adoptar `terraform destroy` / `terraform apply` como modelo operativo entre sesiones de trabajo, en vez de dejar la infraestructura corriendo 24/7.
- **Nivel 3** (pendiente, no implementado): migrar a una plataforma con escalado a cero (Azure Container Apps, Cloud Run) para tener el servicio disponible permanentemente sin gestionar el ciclo destroy/apply — relevante de cara a un portafolio, pero fuera de alcance por ahora.

---

## 4. Implementación — Nivel 1

### 4.1 Cambios en Kubernetes (`ml-deploy-workshop`)

**`k8s/service.yaml`** — de `ClusterIP` a `LoadBalancer`, con la misma anotación de DNS label que usaba el Application Gateway para no perder el dominio:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ml-api-svc
  labels:
    app: ml-api
  annotations:
    service.beta.kubernetes.io/azure-dns-label-name: "ntorresv-prod-ingress"
spec:
  selector:
    app: ml-api
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8000
  type: LoadBalancer
```

**`k8s/ingress.yaml`** — eliminado del repo (ya no hay AGIC que lo interprete). El objeto correspondiente también se eliminó del cluster directamente:

```bash
kubectl delete ingress mi-app-route
```

### 4.2 Cambios en Terraform (`aks-terraform`)

En `modules/aks/main.tf` se eliminaron:

- `resource "azurerm_public_ip" "appgw"`
- `resource "azurerm_application_gateway" "main"`
- `resource "azurerm_role_assignment" "agic_appgw_contributor"`, `"agic_rg_reader"`, `"agic_appgw_subnet_join"`
- El bloque `ingress_application_gateway { gateway_id = ... }` dentro de `azurerm_kubernetes_cluster.main`

En `modules/aks/variables_outputs.tf` y `outputs.tf` (raíz), se eliminaron los outputs correspondientes: `appgw_public_ip`, `appgw_public_ip_fqdn`, `appgw_id`, `agic_identity_object_id`, `agic_identity_client_id`, `agic_appgw_contributor_role_assignment_id`, `agic_rg_reader_role_assignment_id`.

```bash
terraform plan -var-file=terraform.tfvars -out=quitar-appgw.tfplan
terraform apply "quitar-appgw.tfplan"
# Resultado: 0 added, 7 changed, 5 destroyed
```

### 4.3 Troubleshooting #1 — `DnsRecordInUse`

Al aplicar el `Service` tipo `LoadBalancer` **antes** de destruir el Application Gateway, el controlador de Azure dentro de AKS falló con:

```
ERROR CODE: DnsRecordInUse
"DNS record ntorresv-prod-ingress.eastus2.cloudapp.azure.com is already used by another public IP."
```

**Causa**: los DNS labels de Azure son únicos por región — la IP pública vieja del Application Gateway seguía reclamando el nombre. **Solución**: ninguna acción manual; al completar el `terraform apply` de la sección 4.2 (que destruye esa IP), el reintento automático del controlador de Kubernetes (cada ~5 min) tuvo éxito solo.

### 4.4 Troubleshooting #2 — Doble capa de NSG y `EnableFloatingIP`

Con la IP ya asignada, `curl` seguía sin responder (error 28, "Could not connect to server" — no rechazo activo, sino pérdida silenciosa de paquetes).

**Proceso de diagnóstico, en orden:**

1. `curl` a la IP directa también falló → se descartó DNS como causa.
2. `kubectl get endpoints ml-api-svc` mostró los 2 pods correctamente → el Service sí sabía enrutar.
3. `kubectl run curl-debug ... curl http://<IP-interna-del-nodo>:<NodePort>/health` respondió `200 OK` → Kubernetes, Cilium y la app estaban sanos. El problema estaba 100% en la capa de Azure.
4. El health probe del Load Balancer de Azure (`az network lb probe list`) estaba sano (`Succeeded`, apuntando al NodePort correcto).
5. La NSG propia (`nsg-aks-nodes-prod`, gestionada vía Terraform) tenía una regla agregada para el rango de NodePorts (30000-32767) — pero **no resolvió el problema**.
6. Se descubrió una **segunda NSG** (`aks-agentpool-*-nsg`), gestionada automáticamente por AKS a nivel de NIC de cada nodo — independiente de la NSG de subnet. Azure evalúa ambas; las dos deben permitir el tráfico.

**El hallazgo clave**: esa segunda NSG tenía una regla autogenerada por Kubernetes permitiendo `Internet` → **puerto 80** (no el NodePort). La razón: la regla del Load Balancer tiene `EnableFloatingIP: True`, un modo que hace que el paquete conserve la IP y puerto original del frontend (`80`) hasta dentro del propio nodo — la traducción real hacia el NodePort ocurre después, gestionada por Cilium, nunca visible para ninguna NSG.

**Fix real**: la NSG propia necesitaba una regla para el puerto **80**, no para el rango de NodePorts (que resultó irrelevante dado `EnableFloatingIP`):

```hcl
security_rule {
  name                       = "AllowInternetInboundHTTP"
  priority                   = 115
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "80"
  source_address_prefix      = "Internet"
  destination_address_prefix = "*"
}
```

Reglas finales de `nsg-aks-nodes-prod`, en orden de evaluación:

| Prioridad | Nombre | Permite |
|---|---|---|
| 100 | AllowVnetInbound | Tráfico interno del VNet |
| 110 | AllowAzureLoadBalancerInbound | Health probes de Azure |
| 115 | AllowInternetInboundHTTP | Internet → puerto 80 (el fix real) |
| 120 | AllowInternetInboundNodePorts | Internet → 30000-32767 (no resolvió esto, pero inofensivo, útil si algún día hay un Service sin Floating IP) |
| 4096 | DenyAllInbound | Todo lo demás |

Tras aplicar esta regla, `/health` y `/predict` respondieron correctamente tanto por IP directa como por el FQDN.

---

## 5. Implementación — Nivel 2: operar con destroy/apply

### 5.1 Verificación de permisos antes de adoptar el hábito

Antes de destruir con confianza, se verificó que el Service Principal usado por `cd.yml` tenga los permisos ARM necesarios en un scope que **sobreviva** un `terraform destroy` completo (que borra todo el resource group, incluido cualquier recurso al que un role assignment granular esté atado).

```bash
az role assignment list --assignee <AZURE_CLIENT_ID> --all -o table
```

**Resultado**: el SP tiene `Contributor` a nivel de **suscripción** (`/subscriptions/<id>`) — el scope más alto posible, no atado a ningún recurso. Esto cubre de sobra el permiso `Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action` que necesita `az aks get-credentials --admin` en `cd.yml`. **Conclusión: `cd.yml` sigue funcionando sin intervención manual después de cualquier ciclo destroy/apply.**

Nota aparte: existe una segunda asignación (`Azure Kubernetes Service RBAC Admin`, sobre el grupo `curso_mlops`) escopeada directamente al ID del cluster actual — esa sí se perdería en cada destroy. No importa: es un rol de Azure RBAC for Kubernetes Authorization, que `cd.yml` no usa porque `admin: true` lo bypassea por completo.

### 5.2 Limpieza adicional: tags no determinísticos

Se detectó que `locals.tf` usaba `timestamp()` en el tag `CreatedAt`, provocando que Terraform marcara ~7 recursos como "changed" en cada `plan`/`apply`, aunque nada real hubiera cambiado — ruido que dificulta verificar rápidamente si un diff es genuino. Se comentó esa línea.

### 5.3 El flujo operativo

```bash
# Al terminar una sesión de trabajo
terraform destroy -var-file=terraform.tfvars

# Al retomar
terraform apply -var-file=terraform.tfvars -out=plan.tfplan
terraform apply "plan.tfplan"

# Reconectar kubectl (el cluster es nuevo; el kubeconfig viejo no sirve)
az aks get-credentials --resource-group rg-ntorresv-prod-eus2 --name aks-ntorresv-prod-eus2 --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

# Redesplegar la app
# GitHub → Actions → "CD - Deploy a AKS" → Run workflow
```

Los secrets/vars de GitHub (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `AZURE_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`) **no cambian** entre ciclos — los nombres de recursos son determinísticos (derivados de `project`/`environment`/`location_short` en `terraform.tfvars`), y el Service Principal vive en Azure AD, independiente del ciclo de vida de la infraestructura.

---

## 6. Resultado

- **Antes**: Application Gateway corriendo 24/7 ≈ $180/mes fijos, sin importar el tráfico, sobre una arquitectura pensada para producción real.
- **Después**: sin Application Gateway; el Service `LoadBalancer` cuesta una fracción de eso, y con el modelo destroy/apply, el costo es **$0 real** mientras no hay una sesión de trabajo activa.

---

## 7. Lecciones aprendidas

1. **Azure RBAC y Kubernetes RBAC son sistemas de autorización completamente independientes.** Un rol asignado en Azure (ARM) no implica automáticamente permisos dentro del cluster, y viceversa. `admin: true` en `aks-set-context` bypassea el segundo sistema por completo, usando credenciales locales de administrador.
2. **Los role assignments de Azure están atados al ID interno del recurso, no a su nombre.** Destruir y recrear un recurso con el mismo nombre no preserva ningún permiso asignado directamente a él — solo sobreviven las asignaciones a nivel de suscripción (o de un resource group que no se destruya).
3. **`EnableFloatingIP` cambia por completo qué puerto ve una NSG.** Con este modo activo (el default de Kubernetes en Azure), el tráfico conserva el puerto del frontend del Load Balancer hasta dentro del nodo — cualquier regla de NSG pensada para el NodePort tradicional no aplica.
4. **AKS gestiona una NSG adicional a nivel de NIC, independiente de la NSG de subnet que uno controla vía Terraform.** Azure evalúa ambas; hay que revisar las dos al diagnosticar problemas de conectividad.
5. **Diagnosticar de adentro hacia afuera evita perder tiempo.** El orden que funcionó: DNS → endpoints del Service → NodePort interno (sin pasar por Azure) → health probe del LB → regla del LB → NSG de subnet → NSG de NIC. Cada paso descarta una capa completa antes de seguir.
