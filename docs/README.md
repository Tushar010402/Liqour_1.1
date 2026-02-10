# LiquorPro Documentation

Industrial-grade documentation for the LiquorPro Liquor Shop Management Platform.

## Quick Start

### Prerequisites

- Python 3.8+
- pip

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Serve locally
mkdocs serve

# Access at http://localhost:8000
```

### Build Static Site

```bash
# Build documentation
./build.sh

# Static files will be in ./site/
```

### Docker

```bash
# Build and run
docker-compose up -d

# Access at http://localhost:8000
```

## Deployment Options

### Option 1: GitHub Pages

```bash
./deploy.sh
```

Documentation will be available at: `https://liquorpro.github.io/liquorpro-docs/`

### Option 2: Nginx (Self-Hosted)

1. Build the documentation:
```bash
./build.sh
```

2. Copy nginx config:
```bash
sudo cp nginx.conf /etc/nginx/sites-available/liquorpro-docs
sudo ln -s /etc/nginx/sites-available/liquorpro-docs /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

3. Get SSL certificate:
```bash
sudo certbot --nginx -d docs.liquorpro.io
```

### Option 3: Docker + Nginx

```bash
docker-compose up -d docs-static
```

Static site served at port 8080.

## Documentation Structure

```
docs/
├── index.md                 # Home page
├── system/                  # System architecture
│   ├── overview.md
│   ├── infrastructure.md
│   ├── security.md
│   └── scalability.md
├── software/                # Software specifications
│   ├── technical-spec.md
│   ├── database-design.md
│   ├── api-design.md
│   └── technology-stack.md
├── user-guide/              # User documentation
│   ├── getting-started.md
│   ├── daily-operations.md
│   ├── sales-management.md
│   ├── inventory-management.md
│   ├── finance-management.md
│   ├── reports.md
│   └── troubleshooting.md
├── product/                 # Product documentation
│   ├── overview.md
│   ├── features.md
│   ├── roadmap.md
│   └── release-notes.md
├── workflows/               # Business workflows
│   ├── sales-workflow.md
│   ├── approval-workflow.md
│   ├── inventory-workflow.md
│   ├── finance-workflow.md
│   └── ocr-workflow.md
├── api-reference/           # API documentation
│   ├── auth-api.md
│   ├── sales-api.md
│   ├── inventory-api.md
│   ├── finance-api.md
│   └── websocket-api.md
└── deployment/              # Deployment guides
    ├── installation.md
    ├── configuration.md
    ├── docker.md
    ├── kubernetes.md
    └── monitoring.md
```

## Contributing

1. Edit markdown files in `docs/`
2. Preview changes with `mkdocs serve`
3. Submit pull request

## License

Copyright (c) 2024-2025 LiquorPro. All rights reserved.
