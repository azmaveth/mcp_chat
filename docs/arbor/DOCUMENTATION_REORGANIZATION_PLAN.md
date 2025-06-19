# Arbor Documentation Reorganization Plan

## Overview

This document outlines the reorganization of Arbor's documentation structure to improve clarity, consistency, and navigation. The goal is to create a logical hierarchy that guides readers from high-level concepts to implementation details.

## Current Issues

1. **Mixed Hierarchy**: Some documents are in `/docs/arbor/` while related content is in `/docs/architecture/`
2. **Duplicate Topics**: Multiple documents cover similar concepts (e.g., agent architecture)
3. **Unclear Entry Points**: No clear starting point for new readers
4. **Inconsistent Naming**: Mix of ARBOR_ prefixes and descriptive names
5. **Legacy Content**: Old MCP Chat documentation mixed with new Arbor docs

## Proposed Structure

```
docs/
├── README.md                           # Main entry point with navigation guide
├── arbor/                              # All Arbor-specific documentation
│   ├── README.md                       # Arbor documentation index
│   │
│   ├── 01-overview/                    # High-level introduction
│   │   ├── README.md                   # Section index
│   │   ├── architecture-overview.md    # (from ARBOR_ARCHITECTURE_OVERVIEW.md)
│   │   ├── umbrella-structure.md       # (from UMBRELLA_ARCHITECTURE.md)
│   │   └── roadmap.md                  # Future development plans
│   │
│   ├── 02-philosophy/                  # Design philosophy and principles
│   │   ├── README.md                   # Section index
│   │   ├── beam-philosophy.md         # (from BEAM_PHILOSOPHY_AND_CONTRACTS.md)
│   │   ├── contracts-first-design.md   # Extract from BEAM_PHILOSOPHY
│   │   └── design-principles.md        # Core design decisions
│   │
│   ├── 03-contracts/                   # Contract specifications
│   │   ├── README.md                   # Section index
│   │   ├── core-contracts.md          # (from ARBOR_CONTRACTS.md)
│   │   ├── schema-driven-design.md     # (from SCHEMA_DRIVEN_DESIGN.md)
│   │   └── validation-strategy.md      # Extract from SCHEMA_DRIVEN_DESIGN
│   │
│   ├── 04-components/                  # Core component specifications
│   │   ├── README.md                   # Section index
│   │   ├── arbor-core/                 
│   │   │   ├── specification.md        # (from ARBOR_CORE_SPEC.md)
│   │   │   ├── gateway-patterns.md     # (from GATEWAY_AND_DISCOVERY_PATTERNS.md)
│   │   │   └── agent-runtime.md        # Agent lifecycle and management
│   │   ├── arbor-security/
│   │   │   ├── specification.md        # (from ARBOR_SECURITY_SPEC.md)
│   │   │   └── capability-model.md     # Detailed capability system
│   │   └── arbor-persistence/
│   │       └── state-persistence.md    # (from STATE_PERSISTENCE_DESIGN.md)
│   │
│   ├── 05-architecture/                # Architecture patterns and decisions
│   │   ├── README.md                   # Section index
│   │   ├── agent-architecture.md       # (consolidate AGENT_ARCHITECTURE_*.md)
│   │   ├── communication-patterns.md   # (from NATIVE_AGENT_COMMUNICATION.md)
│   │   ├── command-architecture.md     # (from AGENT_COMMAND_ARCHITECTURE*.md)
│   │   └── integration-patterns.md     # (consolidate CLI integration docs)
│   │
│   ├── 06-infrastructure/              # Production infrastructure
│   │   ├── README.md                   # Section index
│   │   ├── observability.md            # (from OBSERVABILITY_STRATEGY.md)
│   │   ├── tooling-analysis.md         # (from TOOLING_AND_LIBRARY_ANALYSIS.md)
│   │   └── deployment.md               # Deployment strategies
│   │
│   ├── 07-implementation/              # Implementation guides
│   │   ├── README.md                   # Section index
│   │   ├── getting-started.md          # Quick start guide
│   │   ├── development-setup.md        # Development environment
│   │   └── testing-strategy.md         # Testing approach
│   │
│   └── 08-reference/                   # API and technical reference
│       ├── README.md                   # Section index
│       ├── api-reference.md            # Generated API docs
│       ├── configuration.md            # Configuration options
│       └── glossary.md                 # Terms and definitions
│
├── legacy/                             # Legacy MCP Chat documentation
│   ├── architecture/                   # (move old architecture docs here)
│   ├── development/                    # (move old development docs here)
│   ├── features/                       # (move old features docs here)
│   └── user/                           # (move old user docs here)
│
└── migration/                          # Migration guides
    └── mcp-chat-to-arbor.md           # Guide for migrating from MCP Chat
```

## File Mapping

### Moves and Renames

1. **Overview Section**:
   - `ARBOR_ARCHITECTURE_OVERVIEW.md` → `01-overview/architecture-overview.md`
   - `UMBRELLA_ARCHITECTURE.md` → `01-overview/umbrella-structure.md`

2. **Philosophy Section**:
   - `BEAM_PHILOSOPHY_AND_CONTRACTS.md` → `02-philosophy/beam-philosophy.md`
   - Extract contracts philosophy → `02-philosophy/contracts-first-design.md`

3. **Contracts Section**:
   - `ARBOR_CONTRACTS.md` → `03-contracts/core-contracts.md`
   - `SCHEMA_DRIVEN_DESIGN.md` → `03-contracts/schema-driven-design.md`

4. **Components Section**:
   - `ARBOR_CORE_SPEC.md` → `04-components/arbor-core/specification.md`
   - `ARBOR_SECURITY_SPEC.md` → `04-components/arbor-security/specification.md`
   - `architecture/GATEWAY_AND_DISCOVERY_PATTERNS.md` → `04-components/arbor-core/gateway-patterns.md`
   - `architecture/STATE_PERSISTENCE_DESIGN.md` → `04-components/arbor-persistence/state-persistence.md`

5. **Architecture Section**:
   - Consolidate all `AGENT_ARCHITECTURE_*.md` → `05-architecture/agent-architecture.md`
   - `architecture/NATIVE_AGENT_COMMUNICATION.md` → `05-architecture/communication-patterns.md`
   - Consolidate command architecture docs → `05-architecture/command-architecture.md`

6. **Infrastructure Section**:
   - `OBSERVABILITY_STRATEGY.md` → `06-infrastructure/observability.md`
   - `TOOLING_AND_LIBRARY_ANALYSIS.md` → `06-infrastructure/tooling-analysis.md`

### Content Consolidation

1. **Agent Architecture**: Merge these files into a single comprehensive document:
   - `architecture/AGENT_ARCHITECTURE_DESIGN.md`
   - `architecture/AGENT_ARCHITECTURE_WITH_SUBAGENTS.md`
   - Relevant sections from `ARBOR_ARCHITECTURE_OVERVIEW.md`

2. **Command Architecture**: Consolidate:
   - `architecture/AGENT_COMMAND_ARCHITECTURE.md`
   - `architecture/AGENT_COMMAND_ARCHITECTURE_ANALYSIS.md`

3. **Integration Patterns**: Merge:
   - `architecture/SECURITY_CLI_AGENT_INTEGRATION.md`
   - `architecture/CLI_AGENT_INTEGRATION.md`

## Implementation Steps

### Phase 1: Structure Creation
1. Create new directory structure
2. Add README.md files for each section with navigation
3. Create top-level README.md with documentation map

### Phase 2: File Migration
1. Move and rename files according to mapping
2. Update internal links in all documents
3. Remove ARBOR_ prefixes from filenames

### Phase 3: Content Consolidation
1. Merge related agent architecture documents
2. Consolidate command architecture content
3. Extract and reorganize overlapping content

### Phase 4: Legacy Migration
1. Move old MCP Chat docs to legacy/
2. Create migration guide
3. Update any remaining references

### Phase 5: Enhancement
1. Add missing documentation (deployment, getting started)
2. Generate API reference from code
3. Create comprehensive glossary

## Benefits

1. **Clear Navigation**: Numbered sections guide readers through complexity levels
2. **Reduced Duplication**: Consolidated documents eliminate redundancy
3. **Better Organization**: Related content grouped together
4. **Easier Maintenance**: Clear structure makes updates straightforward
5. **Legacy Separation**: Old docs preserved but clearly marked

## Next Steps

1. Review and approve this plan
2. Create new directory structure
3. Begin file migration in phases
4. Update all cross-references
5. Add navigation aids (README indexes)

## Notes

- All file moves will preserve git history
- Links will be updated using automated tools where possible
- Legacy documentation remains accessible but clearly marked
- New structure supports future growth with clear categories