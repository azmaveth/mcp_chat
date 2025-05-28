# Performance Optimizations in MCP Chat

This document describes the performance optimizations implemented in MCP Chat v0.2.0.

## Startup Time Optimization

### Startup Profiler
Created `MCPChat.StartupProfiler` to measure and report application startup phases:
- **Config Loading**: Time to load and parse TOML configuration
- **Supervision Tree**: Time to start all GenServers and supervisors
- **MCP Servers**: Time to connect to configured MCP servers
- **LLM Initialization**: Time to initialize LLM adapters
- **UI Setup**: Time to prepare the CLI interface

Enable profiling with: `MCP_CHAT_STARTUP_PROFILING=true ./mcp_chat`

### Lazy Server Manager
Implemented `MCPChat.MCP.LazyServerManager` with three connection modes:

1. **Lazy Mode** (default): Connect to MCP servers only when first accessed
   - Fastest startup time
   - Slight delay on first server use
   
2. **Eager Mode**: Connect to all servers at startup
   - Slower startup time
   - No delays during usage
   
3. **Background Mode**: Start connections after UI loads
   - Balanced approach
   - Connections happen in background

Configure in `config.toml`:
```toml
[startup]
mcp_connection_mode = "lazy"  # or "eager", "background"
```

## Memory Optimization

### Message Store with Pagination
Created `MCPChat.Memory.MessageStore` for efficient message handling:
- **Hybrid Storage**: Recent messages in memory, older ones on disk
- **Configurable Limits**: Set memory and disk limits
- **Smart Pagination**: Seamlessly page through messages
- **Automatic Cleanup**: Remove old messages when limits exceeded

### Session Memory Adapter
Implemented `MCPChat.Memory.SessionMemoryAdapter` for context management:
- **Sliding Window**: Keep most recent N messages
- **Smart Truncation**: Preserve system messages and recent context
- **Token-Aware**: Consider token counts when building context
- **Efficient Retrieval**: Fast access to relevant messages

Configure in `config.toml`:
```toml
[memory]
memory_limit = 100      # Messages in memory
page_size = 20          # Messages per page
disk_cache_enabled = true
cache_directory = "~/.config/mcp_chat/message_cache"
```

## Resource Caching

### Local Resource Cache
Created `MCPChat.MCP.ResourceCache` for MCP resources:
- **Automatic Caching**: Cache frequently accessed resources
- **LRU Eviction**: Remove least recently used items
- **Size Limits**: Configurable maximum cache size
- **TTL Support**: Expire old cache entries
- **Subscription-Based Invalidation**: Auto-invalidate on changes

### Cache Statistics
Track and display cache performance:
- Hit rate percentage
- Average response time
- Memory usage
- Total cached resources

Configure in `config.toml`:
```toml
[resource_cache]
enabled = true
max_size = 104857600    # 100MB
ttl = 3600              # 1 hour
cache_directory = "~/.config/mcp_chat/resource_cache"
cleanup_interval = 300  # 5 minutes
```

## TUI Components

### Progress Display
Implemented `MCPChat.UI.ProgressDisplay` using Owl:
- **Real-time Progress Bars**: Show operation progress
- **Multiple Operations**: Track concurrent operations
- **Color-Coded Status**: Visual feedback for status
- **Minimal Overhead**: Efficient screen updates

### Resource Cache Display
Created `MCPChat.UI.ResourceCacheDisplay` for cache monitoring:
- **Summary View**: Quick overview of cache status
- **Detailed View**: List cached resources with stats
- **Real-time Updates**: Live cache statistics
- **Keyboard Controls**: Interactive display management

### TUI Manager
Centralized control with `MCPChat.UI.TUIManager`:
- **Unified Interface**: Single point of control
- **Display Modes**: Progress, cache, or both
- **Keyboard Shortcuts**: Quick display toggles
- **Layout Options**: Stacked or side-by-side

Control TUI with `/tui` command:
```
/tui show progress     # Show progress bars
/tui show cache        # Show cache status
/tui show both         # Show both displays
/tui hide              # Hide all displays
/tui status            # Current display status
```

## Performance Benefits

1. **Faster Startup**: 
   - Lazy loading reduces startup from ~5s to <1s
   - Background connections eliminate blocking

2. **Lower Memory Usage**:
   - Pagination prevents unbounded growth
   - Smart eviction keeps memory controlled

3. **Improved Responsiveness**:
   - Resource caching reduces server roundtrips
   - Progress feedback for long operations

4. **Better Scalability**:
   - Handle larger conversations efficiently
   - Support more MCP servers without overhead

## Monitoring and Debugging

Enable startup profiling:
```bash
MCP_CHAT_STARTUP_PROFILING=true ./mcp_chat
```

View cache statistics:
```
/tui show cache full
```

Monitor progress operations:
```
/tui show progress
```

## Response Streaming Optimization

### Enhanced Streaming Implementation
Created advanced streaming components for better performance:

1. **StreamManager**: Async stream processing with backpressure
   - Producer/consumer pattern with buffering
   - Automatic backpressure when buffer fills
   - Concurrent chunk processing
   - Comprehensive metrics tracking

2. **StreamBuffer**: Efficient circular buffer
   - O(1) push/pop operations
   - Fixed memory footprint
   - Overflow detection and handling
   - Buffer statistics and monitoring

3. **EnhancedConsumer**: Smart chunk batching
   - Reduces I/O operations by batching
   - Handles slow terminals gracefully
   - Configurable batch sizes and intervals
   - Fallback to simple streaming on error

Configure in `config.toml`:
```toml
[streaming]
enhanced = true          # Use enhanced streaming
buffer_capacity = 100    # Max chunks to buffer
write_interval = 25      # Flush interval in ms
min_batch_size = 3       # Min chunks per write
max_batch_size = 10      # Max chunks per write
```

### Streaming Metrics
The enhanced streaming collects:
- **Throughput**: Bytes per second
- **Buffer Health**: Overflow count, fill percentage
- **Write Performance**: Operations count, slow writes
- **Chunk Statistics**: Min/max/average sizes
- **Efficiency**: Bytes per write operation

Enable metrics logging:
```toml
[debug]
log_streaming_metrics = true
```

## Future Optimizations

Planned improvements:
- [ ] Parallel MCP server initialization
- [x] Streaming response backpressure ✅
- [ ] Concurrent tool execution
- [ ] Background session autosave
- [ ] Memory usage telemetry