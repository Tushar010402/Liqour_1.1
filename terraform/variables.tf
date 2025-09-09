variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Cloud provider region"
  type        = string
  default     = "us-west-2"
}

variable "app_version" {
  description = "Application version"
  type        = string
  default     = "latest"
}

# Database Configuration
variable "database_host" {
  description = "Database host"
  type        = string
  default     = "postgres"
}

variable "database_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "liquorpro"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "database_storage_class" {
  description = "Storage class for database persistent volume"
  type        = string
  default     = "gp2"
}

variable "database_storage_size" {
  description = "Storage size for database"
  type        = string
  default     = "20Gi"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15-alpine"
}

variable "database_backup_schedule" {
  description = "Cron schedule for database backups"
  type        = string
  default     = "0 2 * * *"
}

# Redis Configuration
variable "redis_host" {
  description = "Redis host"
  type        = string
  default     = "redis"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
  default     = ""
}

# Application Secrets
variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

# Monitoring Configuration
variable "jaeger_endpoint" {
  description = "Jaeger endpoint for distributed tracing"
  type        = string
  default     = "jaeger:6831"
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "alertmanager_config" {
  description = "Alertmanager configuration"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be one of: debug, info, warn, error."
  }
}

# Service Configuration
variable "service_config" {
  description = "Configuration for application services"
  type = object({
    gateway = object({
      replicas = number
      cpu      = string
      memory   = string
      port     = number
    })
    auth = object({
      replicas = number
      cpu      = string
      memory   = string
      port     = number
    })
    sales = object({
      replicas = number
      cpu      = string
      memory   = string
      port     = number
    })
    inventory = object({
      replicas = number
      cpu      = string
      memory   = string
      port     = number
    })
    finance = object({
      replicas = number
      cpu      = string
      memory   = string
      port     = number
    })
  })
  default = {
    gateway = {
      replicas = 2
      cpu      = "200m"
      memory   = "256Mi"
      port     = 8090
    }
    auth = {
      replicas = 2
      cpu      = "100m"
      memory   = "128Mi"
      port     = 8091
    }
    sales = {
      replicas = 2
      cpu      = "100m"
      memory   = "128Mi"
      port     = 8092
    }
    inventory = {
      replicas = 2
      cpu      = "100m"
      memory   = "128Mi"
      port     = 8093
    }
    finance = {
      replicas = 1
      cpu      = "100m"
      memory   = "128Mi"
      port     = 8094
    }
  }
}

# Ingress Configuration
variable "ingress_config" {
  description = "Ingress configuration"
  type = object({
    enabled           = bool
    class_name        = string
    host              = string
    tls_enabled       = bool
    cert_manager      = bool
    annotations       = map(string)
  })
  default = {
    enabled     = true
    class_name  = "nginx"
    host        = "api.liquorpro.local"
    tls_enabled = false
    cert_manager = false
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/$2"
    }
  }
}

# Autoscaling Configuration
variable "autoscaling_config" {
  description = "Horizontal Pod Autoscaler configuration"
  type = object({
    enabled = bool
    gateway = object({
      min_replicas                    = number
      max_replicas                    = number
      target_cpu_utilization_percentage = number
      target_memory_utilization_percentage = number
    })
    auth = object({
      min_replicas                    = number
      max_replicas                    = number
      target_cpu_utilization_percentage = number
      target_memory_utilization_percentage = number
    })
    sales = object({
      min_replicas                    = number
      max_replicas                    = number
      target_cpu_utilization_percentage = number
      target_memory_utilization_percentage = number
    })
    inventory = object({
      min_replicas                    = number
      max_replicas                    = number
      target_cpu_utilization_percentage = number
      target_memory_utilization_percentage = number
    })
    finance = object({
      min_replicas                    = number
      max_replicas                    = number
      target_cpu_utilization_percentage = number
      target_memory_utilization_percentage = number
    })
  })
  default = {
    enabled = true
    gateway = {
      min_replicas                    = 2
      max_replicas                    = 10
      target_cpu_utilization_percentage = 70
      target_memory_utilization_percentage = 80
    }
    auth = {
      min_replicas                    = 2
      max_replicas                    = 8
      target_cpu_utilization_percentage = 70
      target_memory_utilization_percentage = 80
    }
    sales = {
      min_replicas                    = 2
      max_replicas                    = 12
      target_cpu_utilization_percentage = 70
      target_memory_utilization_percentage = 80
    }
    inventory = {
      min_replicas                    = 2
      max_replicas                    = 8
      target_cpu_utilization_percentage = 70
      target_memory_utilization_percentage = 80
    }
    finance = {
      min_replicas                    = 1
      max_replicas                    = 6
      target_cpu_utilization_percentage = 70
      target_memory_utilization_percentage = 80
    }
  }
}

# Network Configuration
variable "network_policies_enabled" {
  description = "Enable Kubernetes network policies"
  type        = bool
  default     = true
}

variable "pod_security_standards_enabled" {
  description = "Enable Pod Security Standards"
  type        = bool
  default     = true
}

# Backup Configuration
variable "backup_config" {
  description = "Backup configuration"
  type = object({
    enabled   = bool
    schedule  = string
    retention = string
    storage   = object({
      class = string
      size  = string
    })
  })
  default = {
    enabled   = true
    schedule  = "0 2 * * *"
    retention = "30d"
    storage = {
      class = "gp2"
      size  = "50Gi"
    }
  }
}

# Resource Quotas
variable "resource_quota" {
  description = "Resource quota for the namespace"
  type = object({
    enabled = bool
    limits  = object({
      cpu              = string
      memory           = string
      pods             = string
      persistent_volume_claims = string
      services         = string
      secrets          = string
      config_maps      = string
    })
  })
  default = {
    enabled = true
    limits = {
      cpu              = "10"
      memory           = "20Gi"
      pods             = "50"
      persistent_volume_claims = "10"
      services         = "20"
      secrets          = "20"
      config_maps      = "20"
    }
  }
}

# Security Configuration
variable "security_config" {
  description = "Security configuration"
  type = object({
    pod_security_policy_enabled = bool
    network_policies_enabled    = bool
    rbac_enabled               = bool
    service_mesh_enabled       = bool
  })
  default = {
    pod_security_policy_enabled = true
    network_policies_enabled    = true
    rbac_enabled               = true
    service_mesh_enabled       = false
  }
}