# Logging Stack Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Loki + Grafana in the `logging` namespace, dual-write from Fluent Bit, then cut over and remove Elasticsearch/Kibana while keeping 3-day retention and <1 GB memory.

**Architecture:** Add Loki single-binary StatefulSet with filesystem storage and compactor retention; Grafana Deployment with a provisioned Loki datasource and Traefik ingress; Fluent Bit outputs to both ES and Loki during validation, then Loki-only at cutover.

**Tech Stack:** Kubernetes + Kustomize, Grafana Loki, Grafana, Fluent Bit, Traefik ingress, cert-manager.

**Assumptions/Decisions:**
- Grafana hostname is `grafana.weijun.online` (match Kibana pattern). Update if different.
- Loki and Grafana run in the existing `logging` namespace.
- Images pinned to `grafana/loki:2.9.6` and `grafana/grafana:10.4.2` (update if you prefer).

### Task 1: Create Loki base manifests

**Files:**
- Create: `apps/base/middleware/loki/kustomization.yaml`
- Create: `apps/base/middleware/loki/configmap.yaml`
- Create: `apps/base/middleware/loki/service.yaml`
- Create: `apps/base/middleware/loki/statefulset.yaml`

**Step 1: Write the failing test (kustomize references missing files)**

```yaml
# apps/base/middleware/loki/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: logging
resources:
  - configmap.yaml
  - service.yaml
  - statefulset.yaml
```

**Step 2: Run test to verify it fails**

Run: `kustomize build apps/base/middleware/loki`
Expected: FAIL with "no such file" for the missing manifests.

**Step 3: Write minimal implementation (Loki config)**

```yaml
# apps/base/middleware/loki/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  labels:
    app.kubernetes.io/name: loki
    app.kubernetes.io/component: logging
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
    common:
      path_prefix: /loki
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
    schema_config:
      configs:
        - from: 2024-01-01
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/index
        cache_location: /loki/index_cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
    limits_config:
      retention_period: 72h
      max_query_lookback: 72h
      ingestion_rate_mb: 4
      ingestion_burst_size_mb: 6
    chunk_store_config:
      max_look_back_period: 72h
    table_manager:
      retention_deletes_enabled: true
      retention_period: 72h
    compactor:
      working_directory: /loki/compactor
      shared_store: filesystem
      retention_enabled: true
      retention_delete_delay: 2h
```

**Step 4: Write minimal implementation (Service)**

```yaml
# apps/base/middleware/loki/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: loki
  labels:
    app.kubernetes.io/name: loki
    app.kubernetes.io/component: logging
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 3100
      targetPort: http
    - name: grpc
      port: 9096
      targetPort: grpc
  selector:
    app.kubernetes.io/name: loki
```

**Step 5: Write minimal implementation (StatefulSet)**

```yaml
# apps/base/middleware/loki/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  labels:
    app.kubernetes.io/name: loki
    app.kubernetes.io/component: logging
spec:
  serviceName: loki
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: loki
  template:
    metadata:
      labels:
        app.kubernetes.io/name: loki
        app.kubernetes.io/component: logging
    spec:
      containers:
        - name: loki
          image: grafana/loki:2.9.6
          args:
            - -config.file=/etc/loki/loki.yaml
          ports:
            - name: http
              containerPort: 3100
            - name: grpc
              containerPort: 9096
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          volumeMounts:
            - name: config
              mountPath: /etc/loki
            - name: data
              mountPath: /loki
      volumes:
        - name: config
          configMap:
            name: loki-config
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

**Step 6: Run test to verify it passes**

Run: `kustomize build apps/base/middleware/loki`
Expected: PASS and output includes ConfigMap/Service/StatefulSet for Loki.

**Step 7: Commit**

```bash
git add apps/base/middleware/loki
git commit -m "feat: add loki base manifests"
```

### Task 2: Create Grafana base manifests

**Files:**
- Create: `apps/base/middleware/grafana/kustomization.yaml`
- Create: `apps/base/middleware/grafana/configmap-datasources.yaml`
- Create: `apps/base/middleware/grafana/pvc.yaml`
- Create: `apps/base/middleware/grafana/deployment.yaml`
- Create: `apps/base/middleware/grafana/service.yaml`
- Create: `apps/base/middleware/grafana/ingress.yaml`
- Create: `apps/base/middleware/grafana/certificate.yaml`

**Step 1: Write the failing test (kustomize references missing files)**

```yaml
# apps/base/middleware/grafana/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: logging
resources:
  - configmap-datasources.yaml
  - pvc.yaml
  - deployment.yaml
  - service.yaml
  - ingress.yaml
  - certificate.yaml
```

**Step 2: Run test to verify it fails**

Run: `kustomize build apps/base/middleware/grafana`
Expected: FAIL with "no such file" for the missing manifests.

**Step 3: Write minimal implementation (datasource + storage)**

```yaml
# apps/base/middleware/grafana/configmap-datasources.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/component: logging
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki.logging.svc.cluster.local:3100
        isDefault: true
        editable: false
```

```yaml
# apps/base/middleware/grafana/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana-storage
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/component: logging
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 5Gi
```

**Step 4: Write minimal implementation (Deployment + Service)**

```yaml
# apps/base/middleware/grafana/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/component: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: grafana
  template:
    metadata:
      labels:
        app.kubernetes.io/name: grafana
        app.kubernetes.io/component: logging
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:10.4.2
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: GF_SECURITY_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: grafana-admin
                  key: admin-user
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-admin
                  key: admin-password
            - name: GF_SERVER_ROOT_URL
              value: "https://grafana.weijun.online"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          volumeMounts:
            - name: datasources
              mountPath: /etc/grafana/provisioning/datasources
            - name: storage
              mountPath: /var/lib/grafana
      volumes:
        - name: datasources
          configMap:
            name: grafana-datasources
        - name: storage
          persistentVolumeClaim:
            claimName: grafana-storage
```

```yaml
# apps/base/middleware/grafana/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/component: logging
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: http
  selector:
    app.kubernetes.io/name: grafana
```

**Step 5: Write minimal implementation (Ingress + Certificate)**

```yaml
# apps/base/middleware/grafana/certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-cert
spec:
  secretName: grafana-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "grafana.weijun.online"
```

```yaml
# apps/base/middleware/grafana/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  tls:
    - hosts:
        - grafana.weijun.online
      secretName: grafana-tls-secret
  rules:
    - host: grafana.weijun.online
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
```

**Step 6: Run test to verify it passes**

Run: `kustomize build apps/base/middleware/grafana`
Expected: PASS and output includes Grafana Deployment/Service/Ingress/Certificate/PVC/ConfigMap.

**Step 7: Commit**

```bash
git add apps/base/middleware/grafana
git commit -m "feat: add grafana base manifests"
```

### Task 3: Add Grafana admin secret in prod overlay

**Files:**
- Create: `apps/overlays/prod/middleware/grafana/kustomization.yaml`
- Create: `apps/overlays/prod/middleware/grafana/secret.yaml`

**Step 1: Write the failing test (kustomize references missing secret)**

```yaml
# apps/overlays/prod/middleware/grafana/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../base/middleware/grafana
  - secret.yaml
```

**Step 2: Run test to verify it fails**

Run: `kustomize build apps/overlays/prod/middleware/grafana`
Expected: FAIL with "no such file" for `secret.yaml`.

**Step 3: Write minimal implementation (secret with initial credentials)**

```yaml
# apps/overlays/prod/middleware/grafana/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: logging
type: Opaque
stringData:
  admin-user: admin
  admin-password: change-me-please
```

**Step 4: Run test to verify it passes**

Run: `kustomize build apps/overlays/prod/middleware/grafana`
Expected: PASS and output includes Secret `grafana-admin`.

**Step 5: Commit**

```bash
git add apps/overlays/prod/middleware/grafana
git commit -m "feat: add grafana admin secret for prod"
```

### Task 4: Wire Loki + Grafana into middleware kustomizations

**Files:**
- Modify: `apps/base/middleware/kustomization.yaml`
- Modify: `apps/overlays/prod/middleware/kustomization.yaml`

**Step 1: Write the failing test (base kustomize missing new resources)**

Run: `kustomize build apps/base/middleware | rg -n "loki|grafana" -S`
Expected: FAIL with no Loki/Grafana resources in output.

**Step 2: Write minimal implementation (base middleware kustomization)**

```yaml
# apps/base/middleware/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cert-manager/
  - fluent-bit/
  - kibana/
  - loki/
  - grafana/
  - traefik/
  - sealed-secrets/
```

**Step 3: Run test to verify it passes**

Run: `kustomize build apps/base/middleware | rg -n "loki|grafana" -S`
Expected: PASS with Loki/Grafana resources present.

**Step 4: Write minimal implementation (prod middleware kustomization)**

```yaml
# apps/overlays/prod/middleware/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cert-manager/
  - fluent-bit/
  - kibana/
  - loki/
  - grafana/
  - traefik/
  - sealed-secrets/
```

**Step 5: Run test to verify it passes**

Run: `kustomize build apps/overlays/prod/middleware | rg -n "loki|grafana" -S`
Expected: PASS with Loki/Grafana resources present.

**Step 6: Commit**

```bash
git add apps/base/middleware/kustomization.yaml apps/overlays/prod/middleware/kustomization.yaml
git commit -m "feat: wire loki and grafana into middleware kustomize"
```

### Task 5: Update Fluent Bit for dual-write (ES + Loki)

**Files:**
- Modify: `apps/base/middleware/fluent-bit/configmap.yaml`

**Step 1: Write the failing test (current config missing Loki output)**

Run: `kustomize build apps/base/middleware/fluent-bit | rg -n "Name\\s+loki" -S`
Expected: FAIL with no Loki output in the ConfigMap.

**Step 2: Write minimal implementation (add Loki output block)**

```yaml
# apps/base/middleware/fluent-bit/configmap.yaml (append after ES output)
    [OUTPUT]
        Name            loki
        Match           *
        Host            loki.logging.svc.cluster.local
        Port            3100
        Labels          job=fluent-bit
        Auto_Kubernetes_Labels on
```

**Step 3: Run test to verify it passes**

Run: `kustomize build apps/base/middleware/fluent-bit | rg -n "Name\\s+loki" -S`
Expected: PASS with Loki output present.

**Step 4: Commit**

```bash
git add apps/base/middleware/fluent-bit/configmap.yaml
git commit -m "feat: send fluent-bit logs to loki in parallel"
```

### Task 6: Deploy Loki + Grafana in parallel and validate

**Files:**
- Modify: none (operational)

**Step 1: Apply middleware overlay**

Run: `kubectl apply -k apps/overlays/prod/middleware`
Expected: `configured`/`created` resources for Loki/Grafana.

**Step 2: Verify rollout**

Run: `kubectl -n logging rollout status statefulset/loki`
Expected: `statefulset "loki" successfully rolled out`

Run: `kubectl -n logging rollout status deployment/grafana`
Expected: `deployment "grafana" successfully rolled out`

**Step 3: Confirm Loki is ingesting logs**

Run: `kubectl -n logging port-forward svc/grafana 3000:80`
Expected: Grafana UI reachable at `http://localhost:3000`, Loki datasource present, logs visible in Explore.

**Step 4: Commit**

No commit (operational validation only).

### Task 7: Cutover to Loki-only and remove ELK

**Files:**
- Modify: `apps/base/middleware/fluent-bit/configmap.yaml`
- Modify: `apps/base/middleware/kustomization.yaml`
- Modify: `apps/overlays/prod/middleware/kustomization.yaml`
- Modify: `apps/base/apps/kustomization.yaml`
- Modify: `apps/overlays/prod/kustomization.yaml`

**Step 1: Write the failing test (ES output still present)**

Run: `kustomize build apps/base/middleware/fluent-bit | rg -n "Name\\s+es" -S`
Expected: PASS (ES output still present) — this is the "fail" signal.

**Step 2: Write minimal implementation (remove ES output block)**

Remove this block from `apps/base/middleware/fluent-bit/configmap.yaml`:

```yaml
    [OUTPUT]
        Name            es
        Match           *
        Host            elasticsearch.revieu-prod.svc.cluster.local
        Port            9200
        Logstash_Format On
        Retry_Limit     False
        Replace_Dots    On
        Suppress_Type_Name On
```

**Step 3: Run test to verify it passes**

Run: `kustomize build apps/base/middleware/fluent-bit | rg -n "Name\\s+es" -S`
Expected: FAIL (no ES output found).

**Step 4: Write minimal implementation (stop deploying Kibana + Elasticsearch)**

```yaml
# apps/base/middleware/kustomization.yaml (remove kibana/)
resources:
  - cert-manager/
  - fluent-bit/
  - loki/
  - grafana/
  - traefik/
  - sealed-secrets/
```

```yaml
# apps/overlays/prod/middleware/kustomization.yaml (remove kibana/)
resources:
  - cert-manager/
  - fluent-bit/
  - loki/
  - grafana/
  - traefik/
  - sealed-secrets/
```

```yaml
# apps/base/apps/kustomization.yaml (remove elasticsearch/)
resources:
  - auth/
  - web/
```

```yaml
# apps/overlays/prod/kustomization.yaml (remove apps/elasticsearch)
resources:
  - ./common
  - ./apps/auth
  - ./apps/web
  - ./external/postgres
  - ./middleware
```

**Step 5: Run test to verify it passes**

Run: `kustomize build apps/overlays/prod | rg -n "elasticsearch|kibana" -S`
Expected: FAIL (no Elasticsearch/Kibana resources found).

**Step 6: Commit**

```bash
git add apps/base/middleware/fluent-bit/configmap.yaml \
  apps/base/middleware/kustomization.yaml \
  apps/overlays/prod/middleware/kustomization.yaml \
  apps/base/apps/kustomization.yaml \
  apps/overlays/prod/kustomization.yaml
git commit -m "feat: cut over logging to loki and remove elk from kustomize"
```

**Step 7: Apply cutover and clean up PVCs**

Run: `kubectl apply -k apps/overlays/prod/middleware`
Expected: Fluent Bit reloads config and continues shipping to Loki only.

Run: `kubectl apply -k apps/overlays/prod`
Expected: Elasticsearch + Kibana resources are removed.

Run: `kubectl get pvc -A | rg -n "elasticsearch" -S`
Expected: Identify the Elasticsearch PVC(s), then delete them explicitly:

```bash
kubectl delete pvc -n <namespace> <elasticsearch-pvc-name>
```

### Task 8: Post-cutover validation + rollback window

**Files:**
- Modify: none (operational)

**Step 1: Validate log search workflows**

Run: `kubectl -n logging port-forward svc/grafana 3000:80`
Expected: Grafana Explore returns recent logs for multiple services within 2 seconds.

**Step 2: Validate memory savings**

Run: `kubectl -n logging top pod | rg -n "loki|grafana|fluent-bit" -S`
Expected: Combined memory usage < 1 GiB.

**Step 3: Keep rollback-ready configs for 14 days**

Do not delete the `apps/base/middleware/kibana` or `apps/base/apps/elasticsearch` directories yet.
If rollback needed, re-add the resources in kustomizations and revert the Fluent Bit output.

**Step 4: Optional cleanup after 14 days**

If no rollback needed, delete:
- `apps/base/middleware/kibana`
- `apps/overlays/prod/middleware/kibana`
- `apps/base/apps/elasticsearch`
- `apps/overlays/prod/apps/elasticsearch`

Commit cleanup with:

```bash
git rm -r apps/base/middleware/kibana apps/overlays/prod/middleware/kibana \
  apps/base/apps/elasticsearch apps/overlays/prod/apps/elasticsearch
git commit -m "chore: remove deprecated elk manifests"
```
