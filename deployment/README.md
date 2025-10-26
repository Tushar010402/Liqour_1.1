# LiquorPro Production Deployment

## Server Information
- **IP Address**: 72.60.96.174
- **SSH Port**: 2222 (custom for security)
- **OS**: Ubuntu 22.04 LTS (recommended)
- **User**: deploy (non-root with sudo)

## Directory Structure on Server

```
/opt/liquorpro/
├── backend/                      # Application code
│   ├── cmd/                      # Service executables
│   ├── internal/                 # Service implementations
│   ├── pkg/                      # Shared packages
│   ├── config/                   # Configuration files
│   ├── credentials/              # OCR API credentials
│   ├── docker-compose.production.yml
│   └── .env.production
│
├── nginx/                        # Nginx configuration
│   ├── nginx.conf               # Main nginx config
│   ├── sites-available/
│   │   └── liquorpro.conf       # Site configuration
│   ├── conf.d/
│   │   ├── ssl-params.conf      # SSL/TLS settings
│   │   ├── security-headers.conf # Security headers
│   │   └── rate-limiting.conf   # Rate limiting
│   └── ssl/                     # SSL certificates
│       ├── liquorpro.crt
│       └── liquorpro.key
│
├── logs/                         # Application logs
│   ├── nginx/
│   │   ├── access.log
│   │   └── error.log
│   ├── gateway/
│   ├── auth/
│   ├── sales/
│   ├── inventory/
│   ├── finance/
│   └── saas/
│
├── backups/                      # Database backups
│   ├── postgres/
│   │   └── liquorpro_YYYYMMDD.sql.gz
│   └── redis/
│       └── dump_YYYYMMDD.rdb.gz
│
├── scripts/                      # Deployment scripts
│   ├── deploy-production.sh
│   ├── rollback.sh
│   ├── backup-all.sh
│   ├── health-check-all.sh
│   └── update-ssl.sh
│
└── monitoring/                   # Monitoring configuration
    ├── prometheus.yml
    ├── alerts.yml
    └── grafana-dashboards/
