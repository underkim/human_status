/// Shared defaults for Claude-backed HTTP sources (goal decomposition, quest
/// suggestion, financial advice) so a request to an offline or unresponsive
/// network fails in bounded time instead of hanging the caller indefinitely.
const Duration kClaudeRequestTimeout = Duration(seconds: 20);
