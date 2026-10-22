# ------------------------------------------------------------------------------
# Helm-installed cluster defaults
#
# Two releases run right after the cluster is up:
#   1. cluster-defaults (local chart in ./charts): default gp3 StorageClass
#      and an ALB IngressClass, the two objects EKS Auto Mode leaves to you.
#   2. metrics-server (upstream chart): kubectl top + HorizontalPodAutoscaler.
#
# Add more charts the same way (cert-manager, external-dns, argo-cd, ...).
# ------------------------------------------------------------------------------

resource "helm_release" "cluster_defaults" {
  name      = "cluster-defaults"
  chart     = "${path.module}/charts/cluster-defaults"
  namespace = "kube-system"

  set = [
    { name = "storageClass.name", value = var.default_storage_class_name },
    { name = "ingressClass.name", value = var.ingress_class_name },
    { name = "ingressClass.scheme", value = var.ingress_scheme },
  ]

  # Auto Mode registers the eks.amazonaws.com CRDs shortly after the control
  # plane reports ACTIVE; wait for the cluster (and its access entry) first.
  depends_on = [module.eks]
}

resource "helm_release" "metrics_server" {
  count = var.install_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_chart_version
  namespace  = "kube-system"

  # Auto Mode system node pool is tainted CriticalAddonsOnly; let metrics-server
  # schedule there alongside the other add-ons.
  set = [
    { name = "tolerations[0].key", value = "CriticalAddonsOnly" },
    { name = "tolerations[0].operator", value = "Exists" },
    { name = "tolerations[0].effect", value = "NoSchedule" },
  ]

  depends_on = [module.eks]
}
