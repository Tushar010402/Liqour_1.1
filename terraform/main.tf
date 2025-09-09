terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Local variables
locals {
  app_name      = "liquorpro"
  environment   = var.environment
  region        = var.region
  
  common_tags = {
    Application = local.app_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Project     = "liquorpro-backend"
  }
}

# Data sources
data "kubernetes_namespace" "system_namespaces" {
  for_each = toset(["kube-system", "kube-public", "kube-node-lease"])
  metadata {
    name = each.key
  }
}

# Kubernetes namespace for the application
resource "kubernetes_namespace" "liquorpro" {
  metadata {
    name = "${local.app_name}-${local.environment}"
    labels = merge(local.common_tags, {
      "app.kubernetes.io/name"       = local.app_name
      "app.kubernetes.io/instance"   = local.environment
      "app.kubernetes.io/version"    = var.app_version
      "app.kubernetes.io/component"  = "namespace"
      "app.kubernetes.io/part-of"    = local.app_name
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

# ConfigMap for application configuration
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "${local.app_name}-config"
    namespace = kubernetes_namespace.liquorpro.metadata[0].name
    labels    = local.common_tags
  }
  
  data = {
    "config.yaml" = templatefile("${path.module}/config/app-config.yaml.tpl", {
      environment     = local.environment
      database_host   = var.database_host
      database_port   = var.database_port
      database_name   = var.database_name
      redis_host      = var.redis_host
      redis_port      = var.redis_port
      jaeger_endpoint = var.jaeger_endpoint
      log_level       = var.log_level
    })
  }
}

# Secret for sensitive configuration
resource "kubernetes_secret" "app_secrets" {
  metadata {
    name      = "${local.app_name}-secrets"
    namespace = kubernetes_namespace.liquorpro.metadata[0].name
    labels    = local.common_tags
  }
  
  type = "Opaque"
  
  data = {
    database_password = base64encode(var.database_password)
    redis_password    = base64encode(var.redis_password)
    jwt_secret        = base64encode(var.jwt_secret)
  }
}

# Service Account
resource "kubernetes_service_account" "liquorpro" {
  metadata {
    name      = "${local.app_name}-sa"
    namespace = kubernetes_namespace.liquorpro.metadata[0].name
    labels    = local.common_tags
  }
  
  automount_service_account_token = true
}

# RBAC - ClusterRole for the application
resource "kubernetes_cluster_role" "liquorpro" {
  metadata {
    name   = "${local.app_name}-${local.environment}"
    labels = local.common_tags
  }
  
  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets"]
    verbs      = ["get", "list", "watch"]
  }
  
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }
}

# RBAC - ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "liquorpro" {
  metadata {
    name   = "${local.app_name}-${local.environment}"
    labels = local.common_tags
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.liquorpro.metadata[0].name
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.liquorpro.metadata[0].name
    namespace = kubernetes_namespace.liquorpro.metadata[0].name
  }
}

# Application modules
module "database" {
  source = "./modules/database"
  
  environment   = local.environment
  namespace     = kubernetes_namespace.liquorpro.metadata[0].name
  app_name      = local.app_name
  
  database_config = {
    storage_class    = var.database_storage_class
    storage_size     = var.database_storage_size
    postgres_version = var.postgres_version
    backup_schedule  = var.database_backup_schedule
  }
  
  tags = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"
  
  environment = local.environment
  namespace   = kubernetes_namespace.liquorpro.metadata[0].name
  app_name    = local.app_name
  
  monitoring_config = {
    prometheus_retention = var.prometheus_retention
    grafana_admin_password = var.grafana_admin_password
    alertmanager_config    = var.alertmanager_config
  }
  
  tags = local.common_tags
}

module "kubernetes" {
  source = "./modules/kubernetes"
  
  environment = local.environment
  namespace   = kubernetes_namespace.liquorpro.metadata[0].name
  app_name    = local.app_name
  
  service_config = var.service_config
  ingress_config = var.ingress_config
  autoscaling_config = var.autoscaling_config
  
  config_map_name = kubernetes_config_map.app_config.metadata[0].name
  secret_name     = kubernetes_secret.app_secrets.metadata[0].name
  service_account = kubernetes_service_account.liquorpro.metadata[0].name
  
  tags = local.common_tags
  
  depends_on = [module.database]
}