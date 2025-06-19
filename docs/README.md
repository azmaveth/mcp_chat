# Arbor Documentation

Welcome to the Arbor documentation! Arbor is a production-ready, distributed AI agent orchestration system built on Elixir/OTP principles.

## 📚 Documentation Structure

### 🚀 Getting Started

- **[Arbor Overview](./arbor/01-overview/README.md)** - Start here for high-level understanding
- **[Quick Start Guide](./arbor/07-implementation/getting-started.md)** - Get Arbor running quickly
- **[Architecture Overview](./arbor/01-overview/architecture-overview.md)** - System architecture and components

### 📖 Core Documentation

The Arbor documentation is organized into numbered sections for easy navigation:

1. **[Overview](./arbor/01-overview/README.md)** - High-level introduction and system overview
2. **[Philosophy](./arbor/02-philosophy/README.md)** - Design philosophy and BEAM principles
3. **[Contracts](./arbor/03-contracts/README.md)** - Contract specifications and validation
4. **[Components](./arbor/04-components/README.md)** - Core component specifications
5. **[Architecture](./arbor/05-architecture/README.md)** - Architecture patterns and decisions
6. **[Infrastructure](./arbor/06-infrastructure/README.md)** - Production infrastructure and tooling
7. **[Implementation](./arbor/07-implementation/README.md)** - Implementation guides and setup
8. **[Reference](./arbor/08-reference/README.md)** - API reference and technical details

### 🔄 Migration

- **[Migrating from MCP Chat](./migration/mcp-chat-to-arbor.md)** - Guide for migrating existing MCP Chat installations

### 📦 Legacy Documentation

- **[Legacy MCP Chat Docs](./legacy/README.md)** - Original MCP Chat documentation (preserved for reference)

## 🎯 Quick Links

### For New Users
1. [Architecture Overview](./arbor/01-overview/architecture-overview.md)
2. [Getting Started](./arbor/07-implementation/getting-started.md)
3. [Core Concepts](./arbor/08-reference/glossary.md)

### For Developers
1. [Development Setup](./arbor/07-implementation/development-setup.md)
2. [Contract Specifications](./arbor/03-contracts/core-contracts.md)
3. [Testing Strategy](./arbor/07-implementation/testing-strategy.md)

### For Operations
1. [Observability Strategy](./arbor/06-infrastructure/observability.md)
2. [Deployment Guide](./arbor/06-infrastructure/deployment.md)
3. [Configuration Reference](./arbor/08-reference/configuration.md)

## 🗺️ Documentation Map

```
📁 arbor/
├── 📂 01-overview/        → Start here for system overview
├── 📂 02-philosophy/      → Understand design principles
├── 📂 03-contracts/       → Learn about data contracts
├── 📂 04-components/      → Dive into core components
├── 📂 05-architecture/    → Explore architecture patterns
├── 📂 06-infrastructure/  → Production deployment guides
├── 📂 07-implementation/  → Development and setup guides
└── 📂 08-reference/       → API and configuration reference
```

## 🔍 Finding Information

### By Topic

- **Security**: See [Security Specification](./arbor/04-components/arbor-security/specification.md) and [Capability Model](./arbor/04-components/arbor-security/capability-model.md)
- **Agents**: See [Agent Architecture](./arbor/05-architecture/agent-architecture.md) and [Agent Runtime](./arbor/04-components/arbor-core/agent-runtime.md)
- **Persistence**: See [State Persistence](./arbor/04-components/arbor-persistence/state-persistence.md)
- **Monitoring**: See [Observability Strategy](./arbor/06-infrastructure/observability.md)

### By Role

- **Architects**: Start with [Philosophy](./arbor/02-philosophy/README.md) and [Architecture](./arbor/05-architecture/README.md)
- **Developers**: Focus on [Contracts](./arbor/03-contracts/README.md) and [Components](./arbor/04-components/README.md)
- **DevOps**: See [Infrastructure](./arbor/06-infrastructure/README.md) and [Implementation](./arbor/07-implementation/README.md)

## 📝 Contributing

When adding new documentation:
1. Place it in the appropriate numbered section
2. Update the section's README.md with a link
3. Follow the established naming conventions (lowercase, hyphens)
4. Include cross-references to related documents

## 🔄 Recent Updates

- Reorganized documentation structure for clarity (2025-06-19)
- Added comprehensive observability strategy
- Completed tooling and library analysis
- Unified architecture documentation

---

*For questions or improvements to the documentation, please open an issue in the repository.*