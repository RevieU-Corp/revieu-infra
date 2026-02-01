# Logging Stack Migration: ELK to Loki + Grafana

**Date:** 2026-01-31
**Status:** Approved
**Author:** Claude Code

## Problem Statement

Current logging stack (Elasticsearch + Kibana + Fluent-bit) consumes 1.6-3.3GB memory on a 6GB VPS, making deployment impossible. Need a lightweight alternative that:
- Uses <1GB memory total
- Provides web UI for log search and viewing
- Handles 4-10 microservices
- Retains logs for 1-3 days (debugging use case)

## Solution: Grafana Loki + Grafana

Replace ELK stack with Grafana Loki for log aggregation and Grafana for visualization.

### Architecture

**Components:**
- **Grafana Loki** (~300-500MB) - Log aggregation and storage
- **Grafana** (~200-300MB) - Web UI for viewing/searching logs
- **Promtail or Fluent-bit** (~128-256MB) - Log collection (keep existing fluent-bit)

**Total memory: ~600-1000MB** (saves 1-2GB compared to ELK)

### Why Loki?

- **Designed for cloud-native**: Built specifically for Kubernetes environments
- **Minimal indexing**: Only indexes metadata (labels), not full-text like Elasticsearch
- **Compressed storage**: Stores logs as compressed chunks, reducing storage by 5-10x
- **Low resource usage**: With 3-day retention, uses minimal memory and storage
- **Excellent search**: Grafana provides powerful log search, filtering, and visualization
- **Production-ready**: Mature, well-supported, widely adopted

## Implementation Details

### Loki Configuration (Minimal Resources)

**Deployment mode:** Single-binary (not microservices)

**Resource limits:**
```yaml
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
```

**Key configuration settings:**
```yaml
limits_config:
  retention_period: 72h              # 3 days retention
  max_query_lookback: 72h
  ingestion_rate_mb: 4               # Limit ingestion to prevent spikes
  ingestion_burst_size_mb: 6

chunk_store_config:
  max_look_back_period: 72h

table_manager:
  retention_deletes_enabled: true    # Auto-delete old logs
  retention_period: 72h

storage_config:
  filesystem:
    directory: /loki/chunks           # Local filesystem storage

compactor:
  working_directory: /loki/compactor
  shared_store: filesystem
  retention_enabled: true
  retention_delete_delay: 2h
```

### Grafana Configuration

**Resource limits:**
```yaml
resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 256Mi
    cpu: 500m
```

**Data source:** Configure Loki as data source in Grafana

### Fluent-bit Configuration

**Keep existing fluent-bit DaemonSet** with updated output configuration:

```yaml
[OUTPUT]
    Name loki
    Match *
    Host loki.revieu-prod.svc.cluster.local
    Port 3100
    Labels job=fluent-bit
    Auto_kubernetes_labels on
```

## Migration Plan

### Phase 1: Deploy Loki + Grafana (Parallel)
1. Deploy Loki StatefulSet with minimal config
2. Deploy Grafana Deployment
3. Configure Grafana with Loki data source
4. Update fluent-bit to send logs to BOTH Elasticsearch and Loki
5. Verify logs appear in both systems

**Duration:** Deploy and validate in parallel with existing stack

### Phase 2: Validation (1-2 days)
1. Use both systems in parallel
2. Test typical debugging workflows in Grafana
3. Verify all services' logs are captured
4. Confirm search performance is acceptable
5. Monitor Loki memory usage

### Phase 3: Cutover
1. Update fluent-bit config to send logs ONLY to Loki
2. Remove Elasticsearch StatefulSet
3. Remove Kibana Deployment
4. Delete Elasticsearch PVCs to reclaim storage
5. Monitor memory usage (should drop by 1-2GB)

### Rollback Plan
- Keep ELK configs in git for 2 weeks
- If issues arise, redeploy ELK stack
- Fluent-bit config change is the only switch needed

## Alternative Approaches Considered

### Option 2: Vector + File-based Logs
- **Memory:** ~100-200MB
- **Pros:** Minimal footprint; Vector is very efficient
- **Cons:** Less sophisticated search; requires more manual work
- **Rejected:** Need centralized aggregation for 4-10 services

### Option 3: Dozzle (Docker-only)
- **Memory:** ~50-100MB
- **Pros:** Ultra-lightweight; zero config
- **Cons:** No aggregation; limited search; Docker-only
- **Rejected:** Not suitable for 4-10 services; need centralized solution

## Expected Outcomes

### Memory Savings
- **Before:** 1.6-3.3GB (ELK stack)
- **After:** 0.6-1.0GB (Loki + Grafana)
- **Savings:** 1.0-2.3GB (30-70% reduction)

### Storage Savings
- Loki's compression reduces storage by 5-10x vs Elasticsearch
- With 3-day retention, minimal storage needed (~1-2GB)

### Operational Benefits
- Faster log queries (less indexing overhead)
- Simpler architecture (fewer moving parts)
- Better Kubernetes integration
- Lower resource contention on VPS

## Success Criteria

1. ✅ Total logging stack memory usage <1GB
2. ✅ All service logs captured and searchable
3. ✅ Log search response time <2 seconds for typical queries
4. ✅ 3-day log retention working correctly
5. ✅ Web UI accessible and functional
6. ✅ VPS has sufficient free memory for applications

## References

- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Loki Configuration Reference](https://grafana.com/docs/loki/latest/configuration/)
- [Fluent-bit Loki Output Plugin](https://docs.fluentbit.io/manual/pipeline/outputs/loki)
