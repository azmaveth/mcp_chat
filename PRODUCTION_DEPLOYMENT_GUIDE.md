# MCP Chat Security Model - Production Deployment Guide

## 🚀 Overview

This guide provides comprehensive instructions for deploying MCP Chat's Capability-Based Security (CapSec) model in production environments. The security system provides AI agent orchestration with cryptographic capability validation, distributed authentication, and comprehensive audit logging.

## 📋 Prerequisites

### System Requirements

- **Elixir**: 1.15+ with OTP 26+
- **Database**: PostgreSQL 14+ (for audit logging) or equivalent
- **Memory**: Minimum 512MB RAM (2GB+ recommended)
- **CPU**: 2+ cores recommended for concurrent agent operations
- **Storage**: 10GB+ for audit logs and security keys

### Dependencies

```bash
# Install required system packages
sudo apt-get update
sudo apt-get install -y erlang-dev elixir postgresql-client openssl

# Verify installations
elixir --version
openssl version
```

### Network Requirements

- **Outbound HTTPS**: For LLM API calls (anthropic.com, openai.com, etc.)
- **Internal Communication**: Ports 4000-4010 for agent coordination
- **Database Access**: PostgreSQL port 5432 (or configured port)

## 🔧 Configuration

### 1. Environment Variables

Create a production environment file:

```bash
# /etc/mcp_chat/production.env

# Security Configuration
MCP_SECURITY_MODE=production
MCP_TOKEN_MODE=true
MCP_KEY_ROTATION_INTERVAL=86400  # 24 hours in seconds
MCP_AUDIT_RETENTION_DAYS=90

# Database Configuration
DATABASE_URL=postgresql://mcp_user:secure_password@localhost:5432/mcp_chat_prod
DATABASE_POOL_SIZE=10

# API Keys (set these securely)
ANTHROPIC_API_KEY=your_anthropic_key_here
OPENAI_API_KEY=your_openai_key_here

# Performance Settings
MCP_MAX_CONCURRENT_AGENTS=50
MCP_AGENT_TIMEOUT_MS=300000  # 5 minutes
MCP_RATE_LIMIT_WINDOW=3600   # 1 hour

# Monitoring
MCP_PROMETHEUS_ENABLED=true
MCP_PROMETHEUS_PORT=9090
```

### 2. TOML Configuration

Create production config at `/etc/mcp_chat/config.toml`:

```toml
[environment]
mode = "production"

[security]
# Enable production security features
token_mode = true
audit_enabled = true
violation_monitoring = true

# Key management
key_rotation_enabled = true
key_rotation_interval = 86400  # 24 hours
key_backup_enabled = true
key_backup_path = "/var/lib/mcp_chat/keys/backup"

# Rate limiting
rate_limiting_enabled = true
default_rate_limit = 1000
high_risk_rate_limit = 100

[security.capabilities]
# Default capability settings
default_ttl = 3600  # 1 hour
max_delegation_depth = 3
require_audit_trail = true

[security.violation_thresholds]
critical = 5      # Max critical violations before account suspension
high = 20         # Max high-severity violations per hour
medium = 100      # Max medium-severity violations per hour

[audit]
# Audit logging configuration
enabled = true
buffer_size = 1000
flush_interval = 30  # seconds
retention_days = 90

# Audit storage
storage_type = "database"  # or "file"
database_table = "security_audit_log"

[monitoring]
# Performance monitoring
enabled = true
metrics_interval = 60  # seconds
health_check_enabled = true

# Alerting
alert_on_violations = true
alert_webhook_url = "https://your-monitoring-system.com/webhook"
```

### 3. Database Setup

```sql
-- Create production database and user
CREATE DATABASE mcp_chat_prod;
CREATE USER mcp_user WITH ENCRYPTED PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE mcp_chat_prod TO mcp_user;

-- Switch to the database
\c mcp_chat_prod

-- Create audit logging table
CREATE TABLE security_audit_log (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    principal_id VARCHAR(100) NOT NULL,
    session_id VARCHAR(100),
    capability_id VARCHAR(100),
    resource_type VARCHAR(50),
    operation VARCHAR(50),
    resource VARCHAR(500),
    result VARCHAR(20) NOT NULL, -- 'allowed', 'denied', 'error'
    violation_type VARCHAR(50),
    metadata JSONB,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_audit_timestamp ON security_audit_log(timestamp);
CREATE INDEX idx_audit_principal ON security_audit_log(principal_id);
CREATE INDEX idx_audit_event_type ON security_audit_log(event_type);
CREATE INDEX idx_audit_violation ON security_audit_log(violation_type);

-- Create violation monitoring table
CREATE TABLE security_violations (
    id BIGSERIAL PRIMARY KEY,
    principal_id VARCHAR(100) NOT NULL,
    violation_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL, -- 'low', 'medium', 'high', 'critical'
    details JSONB,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_violations_principal ON security_violations(principal_id);
CREATE INDEX idx_violations_severity ON security_violations(severity);
CREATE INDEX idx_violations_unresolved ON security_violations(resolved) WHERE NOT resolved;

-- Create capability tracking table
CREATE TABLE active_capabilities (
    id VARCHAR(100) PRIMARY KEY,
    principal_id VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    constraints JSONB,
    issued_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    revoked_at TIMESTAMP WITH TIME ZONE,
    delegation_depth INTEGER DEFAULT 0,
    parent_capability_id VARCHAR(100)
);

CREATE INDEX idx_capabilities_principal ON active_capabilities(principal_id);
CREATE INDEX idx_capabilities_expires ON active_capabilities(expires_at);
CREATE INDEX idx_capabilities_active ON active_capabilities(revoked_at) WHERE revoked_at IS NULL;
```

## 🏗️ Deployment Architecture

### Recommended Production Setup

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │────│  MCP Chat Node  │────│   PostgreSQL    │
│     (nginx)     │    │    (Primary)    │    │   (Database)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              │
                       ┌─────────────────┐    ┌─────────────────┐
                       │  MCP Chat Node  │────│     Redis       │
                       │   (Secondary)   │    │    (Cache)      │
                       └─────────────────┘    └─────────────────┘
                              │
                              │
                       ┌─────────────────┐    ┌─────────────────┐
                       │   Monitoring    │────│   Log Storage   │
                       │  (Prometheus)   │    │  (Elasticsearch)│
                       └─────────────────┘    └─────────────────┘
```

### Single-Node Deployment

For smaller deployments, use a single node with all components:

```bash
# Create deployment directory
sudo mkdir -p /opt/mcp_chat
sudo mkdir -p /var/lib/mcp_chat/{keys,logs,data}
sudo mkdir -p /var/log/mcp_chat

# Set ownership
sudo useradd -r -s /bin/false mcp_chat
sudo chown -R mcp_chat:mcp_chat /opt/mcp_chat /var/lib/mcp_chat /var/log/mcp_chat
```

## 🔐 Security Hardening

### 1. Key Management

```bash
# Generate production keys
sudo -u mcp_chat openssl genrsa -out /var/lib/mcp_chat/keys/jwt_private.pem 4096
sudo -u mcp_chat openssl rsa -in /var/lib/mcp_chat/keys/jwt_private.pem -pubout -out /var/lib/mcp_chat/keys/jwt_public.pem

# Generate HMAC signing key
sudo -u mcp_chat openssl rand -hex 64 > /var/lib/mcp_chat/keys/hmac_secret.key

# Set secure permissions
sudo chmod 600 /var/lib/mcp_chat/keys/*.pem /var/lib/mcp_chat/keys/*.key
sudo chmod 700 /var/lib/mcp_chat/keys
```

### 2. Service Configuration

Create systemd service file `/etc/systemd/system/mcp-chat.service`:

```ini
[Unit]
Description=MCP Chat Security Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=exec
User=mcp_chat
Group=mcp_chat
WorkingDirectory=/opt/mcp_chat
Environment=MIX_ENV=prod
Environment=RELEASE_TMP=/var/lib/mcp_chat/tmp
EnvironmentFile=/etc/mcp_chat/production.env

ExecStart=/opt/mcp_chat/bin/mcp_chat start
ExecReload=/bin/kill -USR1 $MAINPID
ExecStop=/opt/mcp_chat/bin/mcp_chat stop

Restart=always
RestartSec=10
LimitNOFILE=65536

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/mcp_chat /var/log/mcp_chat

[Install]
WantedBy=multi-user.target
```

### 3. Network Security

Configure firewall rules:

```bash
# Allow only necessary ports
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (redirect to HTTPS)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 9090/tcp  # Prometheus (restrict to monitoring network)

# Enable firewall
sudo ufw enable
```

## 🚀 Deployment Steps

### 1. Build Release

```bash
# Clone repository
git clone https://github.com/yourusername/mcp_chat.git
cd mcp_chat

# Install dependencies
mix deps.get --only prod

# Compile
MIX_ENV=prod mix compile

# Build release
MIX_ENV=prod mix release

# Copy to deployment directory
sudo cp -r _build/prod/rel/mcp_chat/* /opt/mcp_chat/
```

### 2. Database Migration

```bash
# Run database migrations
sudo -u mcp_chat MIX_ENV=prod /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Release.migrate()"
```

### 3. Start Services

```bash
# Enable and start service
sudo systemctl enable mcp-chat
sudo systemctl start mcp-chat

# Check status
sudo systemctl status mcp-chat
sudo journalctl -u mcp-chat -f
```

### 4. Health Check

```bash
# Verify service health
curl http://localhost:4000/health

# Check security kernel status
/opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.health_check()"

# Verify audit logging
psql -h localhost -U mcp_user -d mcp_chat_prod -c "SELECT COUNT(*) FROM security_audit_log;"
```

## 📊 Monitoring & Alerting

### 1. Prometheus Configuration

Add to `/etc/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'mcp_chat'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 30s
    metrics_path: /metrics
```

### 2. Key Metrics to Monitor

- **Security Violations**: Rate and severity of security violations
- **Capability Usage**: Active capabilities and delegation patterns
- **Authentication**: Token validation success/failure rates
- **Performance**: Agent response times and resource usage
- **Audit Events**: Rate of audit log generation

### 3. Alert Rules

```yaml
# security_alerts.yml
groups:
  - name: mcp_chat_security
    rules:
      - alert: HighSecurityViolationRate
        expr: rate(mcp_security_violations_total[5m]) > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High rate of security violations detected"
          
      - alert: CapabilityExhaustionRisk
        expr: mcp_active_capabilities_count > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of active capabilities"
          
      - alert: AuditLogBacklog
        expr: mcp_audit_buffer_size > 5000
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Audit log buffer growing too large"
```

## 🔄 Maintenance & Operations

### 1. Regular Maintenance Tasks

```bash
#!/bin/bash
# /opt/mcp_chat/scripts/maintenance.sh

# Rotate logs
sudo journalctl --rotate
sudo journalctl --vacuum-time=30d

# Clean up expired capabilities
/opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.cleanup_expired_capabilities()"

# Backup security keys
sudo tar -czf /var/backups/mcp_chat_keys_$(date +%Y%m%d).tar.gz -C /var/lib/mcp_chat keys/

# Database maintenance
psql -h localhost -U mcp_user -d mcp_chat_prod -c "VACUUM ANALYZE security_audit_log;"

# Audit log cleanup (keep 90 days)
psql -h localhost -U mcp_user -d mcp_chat_prod -c "DELETE FROM security_audit_log WHERE timestamp < NOW() - INTERVAL '90 days';"
```

### 2. Key Rotation

```bash
#!/bin/bash
# /opt/mcp_chat/scripts/rotate_keys.sh

# Generate new keys
openssl genrsa -out /tmp/jwt_private_new.pem 4096
openssl rsa -in /tmp/jwt_private_new.pem -pubout -out /tmp/jwt_public_new.pem
openssl rand -hex 64 > /tmp/hmac_secret_new.key

# Backup current keys
cp /var/lib/mcp_chat/keys/jwt_private.pem /var/lib/mcp_chat/keys/backup/
cp /var/lib/mcp_chat/keys/jwt_public.pem /var/lib/mcp_chat/keys/backup/
cp /var/lib/mcp_chat/keys/hmac_secret.key /var/lib/mcp_chat/keys/backup/

# Install new keys
mv /tmp/jwt_private_new.pem /var/lib/mcp_chat/keys/jwt_private.pem
mv /tmp/jwt_public_new.pem /var/lib/mcp_chat/keys/jwt_public.pem
mv /tmp/hmac_secret_new.key /var/lib/mcp_chat/keys/hmac_secret.key

# Set permissions
chown mcp_chat:mcp_chat /var/lib/mcp_chat/keys/*
chmod 600 /var/lib/mcp_chat/keys/*.pem /var/lib/mcp_chat/keys/*.key

# Reload service
systemctl reload mcp-chat

echo "Key rotation completed successfully"
```

### 3. Backup Strategy

```bash
#!/bin/bash
# /opt/mcp_chat/scripts/backup.sh

BACKUP_DIR="/var/backups/mcp_chat/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup database
pg_dump -h localhost -U mcp_user mcp_chat_prod | gzip > "$BACKUP_DIR/database.sql.gz"

# Backup configuration
cp -r /etc/mcp_chat "$BACKUP_DIR/"

# Backup security keys
cp -r /var/lib/mcp_chat/keys "$BACKUP_DIR/"

# Backup application data
tar -czf "$BACKUP_DIR/app_data.tar.gz" -C /var/lib/mcp_chat data/

echo "Backup completed in $BACKUP_DIR"
```

## 🚨 Troubleshooting

### Common Issues

1. **High Memory Usage**
   ```bash
   # Check capability count
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.get_capability_stats()"
   
   # Clean expired capabilities
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.cleanup_expired_capabilities()"
   ```

2. **Audit Log Performance**
   ```sql
   -- Check audit log size
   SELECT pg_size_pretty(pg_total_relation_size('security_audit_log'));
   
   -- Check slow queries
   SELECT query, mean_time, calls FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;
   ```

3. **Security Violations**
   ```bash
   # Check recent violations
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.ViolationMonitor.get_recent_violations()"
   
   # View violation details
   psql -c "SELECT * FROM security_violations WHERE created_at > NOW() - INTERVAL '1 hour' ORDER BY created_at DESC;"
   ```

### Emergency Procedures

1. **Security Breach Response**
   ```bash
   # Immediately revoke all capabilities
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.emergency_revoke_all()"
   
   # Stop new capability issuance
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.enable_lockdown_mode()"
   
   # Generate incident report
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.generate_incident_report()"
   ```

2. **Service Recovery**
   ```bash
   # Restart with clean state
   sudo systemctl stop mcp-chat
   /opt/mcp_chat/bin/mcp_chat eval "MCPChat.Security.reset_kernel_state()"
   sudo systemctl start mcp-chat
   ```

## 📚 Additional Resources

- **Architecture Documentation**: `/docs/architecture/SECURITY_ARCHITECTURE.md`
- **API Reference**: `/docs/api/SECURITY_API.md`
- **Performance Tuning**: `/docs/operations/PERFORMANCE_TUNING.md`
- **Security Best Practices**: `/docs/security/BEST_PRACTICES.md`

## 🆘 Support

For production support:
- **Documentation**: Check the `/docs` directory for detailed guides
- **Logs**: Monitor `/var/log/mcp_chat/` and systemd journal
- **Health Checks**: Use built-in health check endpoints
- **Emergency Contact**: Set up 24/7 monitoring alerts

---

**Note**: This guide provides a comprehensive foundation for production deployment. Customize the configuration based on your specific infrastructure requirements and security policies.