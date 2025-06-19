# Plan Mode Design Document

## Overview

Plan Mode is a safety-first execution preview system that shows users exactly what actions will be taken before executing them. This is inspired by Claude Code's approach and is critical for building user trust.

## Core Concepts

### 1. Plan Structure

A plan consists of:
- **Metadata**: ID, creation time, description, estimated cost
- **Steps**: Ordered list of actions to execute
- **Context**: Current session state and constraints
- **Status**: draft, approved, executing, completed, failed

### 2. Step Types

Each step can be:
- **Tool Execution**: MCP tool call with parameters
- **Message**: LLM interaction
- **Command**: System command execution
- **Checkpoint**: Savepoint for rollback
- **Conditional**: Branch based on previous results

### 3. Safety Features

- **Preview**: Full display of planned actions
- **Approval**: Explicit user consent required
- **Rollback**: Undo capability per step
- **Dry Run**: Simulate without side effects
- **Risk Assessment**: Highlight dangerous operations

## Implementation Architecture

```
lib/mcp_chat/plan_mode/
├── plan.ex                 # Plan data structure
├── step.ex                 # Step definitions
├── parser.ex               # Parse user intent into plans
├── executor.ex             # Execute approved plans
├── renderer.ex             # Display plans to user
├── safety_analyzer.ex      # Risk assessment
├── rollback_manager.ex     # Undo operations
└── templates/              # Common plan templates
    ├── refactor.ex
    ├── debug.ex
    └── test_generation.ex
```

## Data Structures

### Plan
```elixir
defmodule MCPChat.PlanMode.Plan do
  defstruct [
    :id,
    :description,
    :created_at,
    :status,
    :steps,
    :context,
    :estimated_cost,
    :risk_level,
    :metadata
  ]
end
```

### Step
```elixir
defmodule MCPChat.PlanMode.Step do
  defstruct [
    :id,
    :type,           # :tool | :message | :command | :checkpoint | :conditional
    :description,
    :action,         # Specific action data
    :prerequisites,  # Dependencies on other steps
    :rollback_info,  # How to undo this step
    :risk_level,     # :safe | :moderate | :dangerous
    :estimated_cost,
    :status          # :pending | :approved | :executing | :completed | :failed
  ]
end
```

## CLI Interface

### Commands

1. **Create Plan**
```
/plan Create a refactoring plan for the user module
```

2. **Review Plan**
```
Plan: Refactor user module
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Step 1: Analyze current structure [SAFE]
  └─ Tool: analyze_code {"path": "lib/user.ex"}
  
Step 2: Create backup [SAFE]
  └─ Command: cp lib/user.ex lib/user.ex.backup
  
Step 3: Extract validation logic [MODERATE]
  └─ Tool: refactor {"type": "extract_module", ...}
  
Step 4: Update tests [SAFE]
  └─ Tool: update_tests {"module": "User"}
  
Step 5: Run tests [SAFE]
  └─ Command: mix test test/user_test.exs

Estimated tokens: 2,500 (~$0.05)
Risk: MODERATE (file modifications)

Approve? [y/N/edit/step]:
```

3. **Interactive Approval**
- `y` - Approve entire plan
- `n` - Reject plan
- `edit` - Modify plan steps
- `step` - Approve step-by-step

4. **Execution Control**
```
Executing Step 2/5: Create backup
✓ Completed

Continue? [y/n/rollback]:
```

## Workflow

1. **User Request** → "Refactor this module to be more modular"
2. **Plan Generation** → AI creates structured plan
3. **Risk Analysis** → Identify dangerous operations
4. **User Review** → Display plan with risks highlighted
5. **Approval** → Get explicit consent
6. **Execution** → Run steps with progress updates
7. **Rollback** → Available at each step if needed

## Safety Mechanisms

### Risk Levels

1. **SAFE**: Read-only operations, queries
2. **MODERATE**: File modifications, reversible changes
3. **DANGEROUS**: Deletions, system changes, network operations

### Rollback System

Each step must define its rollback:
```elixir
%Step{
  action: {:write_file, "config.json", new_content},
  rollback_info: %{
    type: :restore_file,
    backup_path: "/tmp/config.json.backup",
    original_content: original_content
  }
}
```

### Dry Run Mode

Execute plan without side effects:
- Tool calls return mock responses
- Commands logged but not executed
- File operations simulated
- Full execution path tested

## Integration Points

### With Existing Systems

1. **Session Management**: Plans tied to sessions
2. **Tool Execution**: Reuse Gateway.execute_tool
3. **Cost Tracking**: Integrate with ExLLM costs
4. **Event System**: Broadcast plan events
5. **Web UI**: Real-time plan monitoring

### New Capabilities

1. **Plan Templates**: Reusable patterns
2. **Plan Sharing**: Export/import plans
3. **Plan History**: Learn from past executions
4. **Plan Optimization**: Suggest improvements

## Example Implementation Flow

```elixir
# User command
"/plan refactor the user module to extract validation"

# System flow
1. Parser.parse_intent(message)
   → {:refactor, "user module", "extract validation"}

2. PlanGenerator.generate(intent, context)
   → %Plan{steps: [...]}

3. SafetyAnalyzer.analyze(plan)
   → adds risk_level to each step

4. Renderer.display(plan)
   → formatted output for user

5. Executor.get_approval(plan)
   → :approved | :rejected | {:modified, new_plan}

6. Executor.execute(plan)
   → step-by-step execution with checkpoints

7. RollbackManager.save_state(step)
   → enables undo if needed
```

## Success Metrics

1. **User Trust**: Reduced anxiety about AI actions
2. **Error Recovery**: Successful rollbacks
3. **Efficiency**: Batch operations vs individual
4. **Learning**: Improved plans over time

## Future Enhancements

1. **Visual Plan Editor**: Drag-drop step arrangement
2. **Collaborative Plans**: Multi-user approval
3. **Plan Analytics**: Success rates, optimization
4. **AI Plan Learning**: Improve generation over time