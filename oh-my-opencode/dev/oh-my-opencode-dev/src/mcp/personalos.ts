/**
 * PersonalOS Gateway MCP
 * 
 * Integration with PersonalOS Gateway service for:
 * - Session management
 * - Agent invocation
 * - Queue status monitoring
 * - Multi-channel messaging (WhatsApp, Telegram, Email)
 * 
 * Environment Variables:
 * - PERSONALOS_GATEWAY_URL: Gateway URL (default: http://localhost:8080)
 * - PERSONALOS_GATEWAY_TOKEN: Admin token for authentication
 */

type RemoteMcpConfig = {
  type: "remote"
  url: string
  enabled: boolean
  headers?: Record<string, string>
  oauth?: false
}

export function createPersonalOsGatewayConfig(): RemoteMcpConfig {
  const gatewayUrl = process.env.PERSONALOS_GATEWAY_URL || "http://localhost:8080"
  const gatewayToken = process.env.PERSONALOS_GATEWAY_TOKEN || ""

  return {
    type: "remote" as const,
    url: `${gatewayUrl}/mcp`,
    enabled: true,
    headers: gatewayToken ? { Authorization: `Bearer ${gatewayToken}` } : undefined,
    oauth: false as const,
  }
}

export function createPersonalOsAgentConfig(): RemoteMcpConfig {
  const agentUrl = process.env.PERSONALOS_AGENT_URL || "http://localhost:8081"
  const agentToken = process.env.PERSONALOS_AGENT_TOKEN || ""

  return {
    type: "remote" as const,
    url: `${agentUrl}/mcp`,
    enabled: true,
    headers: agentToken ? { Authorization: `Bearer ${agentToken}` } : undefined,
    oauth: false as const,
  }
}

export function createPersonalOsDispatcherConfig(): RemoteMcpConfig {
  const dispatcherUrl = process.env.PERSONALOS_DISPATCHER_URL || "http://localhost:9400"

  return {
    type: "remote" as const,
    url: `${dispatcherUrl}/mcp`,
    enabled: true,
    oauth: false as const,
  }
}

export const personalosGateway = createPersonalOsGatewayConfig()
export const personalosAgent = createPersonalOsAgentConfig()
export const personalosDispatcher = createPersonalOsDispatcherConfig()
