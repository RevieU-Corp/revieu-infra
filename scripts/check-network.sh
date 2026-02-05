#!/bin/bash
# Pre-bootstrap 检查脚本
# 用于验证 K3s 多节点集群的网络配置是否正确

set -e

echo "==> K3s Multi-Node Network Configuration Checker"
echo ""

# 检查是否为多节点集群
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

if [ "$NODE_COUNT" -le 1 ]; then
    echo "✓ Single-node cluster detected, no cross-node network configuration needed."
    exit 0
fi

echo "Multi-node cluster detected ($NODE_COUNT nodes)"
echo ""

# 获取所有节点
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
ERRORS=0

echo "==> Checking flannel configuration on each node..."
echo ""

for NODE in $NODES; do
    echo "Checking node: $NODE"

    # 获取节点的内部 IP
    INTERNAL_IP=$(kubectl get node "$NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    echo "  Internal IP: $INTERNAL_IP"

    # 通过 SSH 检查 flannel 接口（假设可以 SSH）
    # 注意：这需要 SSH 访问权限
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$NODE" "true" 2>/dev/null; then
        FLANNEL_INFO=$(ssh "root@$NODE" "ip -d link show flannel.1 2>/dev/null | grep vxlan" || echo "")

        if [ -z "$FLANNEL_INFO" ]; then
            echo "  ⚠ WARNING: flannel.1 interface not found"
            ((ERRORS++))
        else
            # 提取 local IP 和 device
            LOCAL_IP=$(echo "$FLANNEL_INFO" | grep -oP 'local \K[\d.]+' || echo "unknown")
            DEVICE=$(echo "$FLANNEL_INFO" | grep -oP 'dev \K\w+' || echo "unknown")

            echo "  Flannel local IP: $LOCAL_IP"
            echo "  Flannel device: $DEVICE"

            # 检查是否使用公网接口（通常是 eth0）
            if [ "$DEVICE" = "eth0" ] || [ "$DEVICE" = "ens3" ] || [ "$DEVICE" = "ens5" ]; then
                echo "  ❌ ERROR: Flannel is using public interface ($DEVICE)"
                echo "     This will prevent cross-node pod communication!"
                echo "     Expected: VPN interface (e.g., wg0, tailscale0)"
                ((ERRORS++))
            elif [ "$LOCAL_IP" = "$INTERNAL_IP" ]; then
                echo "  ✓ Flannel configured correctly (using internal IP)"
            else
                echo "  ⚠ WARNING: Flannel local IP ($LOCAL_IP) differs from internal IP ($INTERNAL_IP)"
                echo "     Please verify this is expected (e.g., VPN setup)"
            fi
        fi

        # 检查 K3s 配置文件
        if ssh "root@$NODE" "[ -f /etc/rancher/k3s/config.yaml ]" 2>/dev/null; then
            FLANNEL_IFACE=$(ssh "root@$NODE" "grep flannel-iface /etc/rancher/k3s/config.yaml" 2>/dev/null || echo "")
            if [ -n "$FLANNEL_IFACE" ]; then
                echo "  K3s config: $FLANNEL_IFACE"
            else
                echo "  ⚠ WARNING: flannel-iface not configured in /etc/rancher/k3s/config.yaml"
            fi
        fi
    else
        echo "  ⚠ WARNING: Cannot SSH to node $NODE for detailed checks"
        echo "     Please manually verify flannel configuration:"
        echo "     Run on $NODE: ip -d link show flannel.1"
    fi

    echo ""
done

echo "==> Testing cross-node pod communication..."
echo ""

# 创建测试 pods
echo "Creating test pods on different nodes..."

# 获取两个不同的节点
NODE1=$(echo $NODES | awk '{print $1}')
NODE2=$(echo $NODES | awk '{print $2}')

if [ -z "$NODE2" ]; then
    echo "⚠ Only one node found, skipping cross-node test"
else
    # 创建临时测试 namespace
    kubectl create namespace network-test --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

    # 在 node1 上创建测试 pod
    kubectl run test-pod-1 -n network-test --image=busybox --restart=Never \
        --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"'$NODE1'"}}}' \
        --command -- sleep 3600 2>/dev/null || echo "test-pod-1 already exists"

    # 在 node2 上创建测试 pod
    kubectl run test-pod-2 -n network-test --image=busybox --restart=Never \
        --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"'$NODE2'"}}}' \
        --command -- sleep 3600 2>/dev/null || echo "test-pod-2 already exists"

    # 等待 pods 就绪
    echo "Waiting for test pods to be ready..."
    kubectl wait --for=condition=Ready pod/test-pod-1 -n network-test --timeout=60s 2>/dev/null || {
        echo "❌ test-pod-1 failed to start"
        ((ERRORS++))
    }
    kubectl wait --for=condition=Ready pod/test-pod-2 -n network-test --timeout=60s 2>/dev/null || {
        echo "❌ test-pod-2 failed to start"
        ((ERRORS++))
    }

    if [ $ERRORS -eq 0 ]; then
        # 获取 pod IPs
        POD1_IP=$(kubectl get pod test-pod-1 -n network-test -o jsonpath='{.status.podIP}')
        POD2_IP=$(kubectl get pod test-pod-2 -n network-test -o jsonpath='{.status.podIP}')

        echo "test-pod-1 (on $NODE1): $POD1_IP"
        echo "test-pod-2 (on $NODE2): $POD2_IP"
        echo ""

        # 测试 pod1 -> pod2
        echo "Testing connectivity: pod1 -> pod2..."
        if kubectl exec test-pod-1 -n network-test -- ping -c 2 -W 2 "$POD2_IP" > /dev/null 2>&1; then
            echo "✓ Success: pod1 can reach pod2"
        else
            echo "❌ FAILED: pod1 cannot reach pod2"
            echo "   This indicates a cross-node networking issue!"
            ((ERRORS++))
        fi

        # 测试 pod2 -> pod1
        echo "Testing connectivity: pod2 -> pod1..."
        if kubectl exec test-pod-2 -n network-test -- ping -c 2 -W 2 "$POD1_IP" > /dev/null 2>&1; then
            echo "✓ Success: pod2 can reach pod1"
        else
            echo "❌ FAILED: pod2 cannot reach pod1"
            echo "   This indicates a cross-node networking issue!"
            ((ERRORS++))
        fi
    fi

    # 清理测试资源
    echo ""
    read -p "Clean up test resources? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace network-test 2>/dev/null || true
        echo "Test resources cleaned up"
    fi
fi

echo ""
echo "==> Check Summary"
if [ $ERRORS -eq 0 ]; then
    echo "✓ All checks passed!"
    echo "Your cluster networking is properly configured."
    exit 0
else
    echo "❌ Found $ERRORS error(s)"
    echo ""
    echo "Common fixes:"
    echo "1. Ensure K3s is configured with flannel-iface pointing to VPN interface"
    echo "   Add to /etc/rancher/k3s/config.yaml on each node:"
    echo "   ---"
    echo "   flannel-iface: wg0  # or your VPN interface name"
    echo ""
    echo "2. Delete old flannel interface and restart K3s:"
    echo "   ip link delete flannel.1"
    echo "   systemctl restart k3s          # on control plane"
    echo "   systemctl restart k3s-agent    # on workers"
    echo ""
    echo "For detailed instructions, see: docs/DEPLOYMENT.md"
    exit 1
fi
