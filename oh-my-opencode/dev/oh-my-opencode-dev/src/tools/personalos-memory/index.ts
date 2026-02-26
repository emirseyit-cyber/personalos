/**
 * PersonalOS Tools
 * 
 * HTTP API tabanlı PersonalOS entegrasyonu
 * Gateway, Agent ve Dispatcher servisleriyle iletişim
 */

import type { PluginInput } from "@opencode-ai/plugin"
import { tool, type ToolDefinition } from "@opencode-ai/plugin/tool"

// Environment Configuration
const GATEWAY_URL = process.env.PERSONALOS_GATEWAY_URL || "http://localhost:8080"
const GATEWAY_TOKEN = process.env.PERSONALOS_GATEWAY_TOKEN || "devtoken"
const AGENT_URL = process.env.PERSONALOS_AGENT_URL || "http://localhost:8081"
const DISPATCHER_URL = process.env.PERSONALOS_DISPATCHER_URL || "http://localhost:9400"

// ==================== HELPER FUNCTIONS ====================

async function gatewayRequest<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${GATEWAY_URL}${endpoint}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${GATEWAY_TOKEN}`,
      ...options.headers,
    },
  })
  
  if (!response.ok) {
    throw new Error(`Gateway error: ${response.status} ${response.statusText}`)
  }
  
  return response.json() as Promise<T>
}

async function agentRequest<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${AGENT_URL}${endpoint}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
  })
  
  if (!response.ok) {
    throw new Error(`Agent error: ${response.status} ${response.statusText}`)
  }
  
  return response.json() as Promise<T>
}

async function dispatcherRequest<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${DISPATCHER_URL}${endpoint}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...options.headers,
    },
  })
  
  if (!response.ok) {
    throw new Error(`Dispatcher error: ${response.status} ${response.statusText}`)
  }
  
  return response.json() as Promise<T>
}

// ==================== TOOL FACTORIES ====================

export function createPersonalosGatewayTools(_ctx?: PluginInput): Record<string, ToolDefinition> {
  return {
    personalos_health: tool({
      description: "PersonalOS Gateway sağlık kontrolü yapar. Tüm servislerin durumunu gösterir.",
      args: {},
      execute: async () => {
        const result = await gatewayRequest<{ status: string; deps: Record<string, boolean> }>("/health")
        return JSON.stringify(result)
      },
    }),

    personalos_session_create: tool({
      description: "PersonalOS Gateway'de yeni oturum oluşturur.",
      args: {
        user_id: tool.schema.string().optional().describe("Kullanıcı ID"),
        metadata: tool.schema.record(tool.schema.string(), tool.schema.unknown()).optional().describe("Oturum metadata"),
      },
      execute: async (args) => {
        const result = await gatewayRequest<{ session_id: string; created_at: string }>("/session", {
          method: "POST",
          body: JSON.stringify(args),
        })
        return JSON.stringify(result)
      },
    }),

    personalos_session_info: tool({
      description: "Oturum bilgilerini getirir.",
      args: {
        session_id: tool.schema.string().describe("Oturum ID"),
      },
      execute: async (args) => {
        const result = await gatewayRequest<Record<string, unknown>>(`/session/${args.session_id}`)
        return JSON.stringify(result)
      },
    }),

    personalos_queue_status: tool({
      description: "PersonalOS kuyruk durumunu getirir.",
      args: {},
      execute: async () => {
        const result = await gatewayRequest<Record<string, unknown>>("/queues/status")
        return JSON.stringify(result)
      },
    }),

    personalos_analytics: tool({
      description: "Oturum analitiklerini getirir.",
      args: {
        session_id: tool.schema.string().describe("Oturum ID"),
      },
      execute: async (args) => {
        const result = await gatewayRequest<Record<string, unknown>>(`/analytics/${args.session_id}`)
        return JSON.stringify(result)
      },
    }),
  }
}

export function createPersonalosAgentTools(_ctx?: PluginInput): Record<string, ToolDefinition> {
  return {
    personalos_agent_invoke: tool({
      description: "PersonalOS Agent'ı çağırır ve yanıt alır. AI işlemleri için kullanılır.",
      args: {
        prompt: tool.schema.string().describe("Agent'a gönderilecek prompt"),
        model: tool.schema.string().optional().describe("Kullanılacak model"),
        session_id: tool.schema.string().optional().describe("Oturum ID"),
      },
      execute: async (args) => {
        const result = await agentRequest<{ response: string; session_id: string }>("/invoke", {
          method: "POST",
          body: JSON.stringify(args),
        })
        return JSON.stringify(result)
      },
    }),
  }
}

export function createPersonalosDispatcherTools(_ctx?: PluginInput): Record<string, ToolDefinition> {
  return {
    personalos_workflow_run: tool({
      description: "PersonalOS Dispatcher ile workflow çalıştırır.",
      args: {
        workflow_id: tool.schema.string().describe("Workflow ID"),
        input: tool.schema.record(tool.schema.string(), tool.schema.unknown()).optional().describe("Workflow input"),
      },
      execute: async (args) => {
        const result = await dispatcherRequest<{ job_id: string; status: string }>(`/workflows/${args.workflow_id}/run`, {
          method: "POST",
          body: JSON.stringify(args.input || {}),
        })
        return JSON.stringify(result)
      },
    }),

    personalos_workflow_status: tool({
      description: "Workflow durumunu kontrol eder.",
      args: {
        job_id: tool.schema.string().describe("İş ID"),
      },
      execute: async (args) => {
        const result = await dispatcherRequest<Record<string, unknown>>(`/jobs/${args.job_id}`)
        return JSON.stringify(result)
      },
    }),
  }
}

export function createPersonalosChannelTools(_ctx?: PluginInput): Record<string, ToolDefinition> {
  return {
    personalos_send_whatsapp: tool({
      description: "WhatsApp mesajı gönderir.",
      args: {
        phone: tool.schema.string().describe("Telefon numarası"),
        message: tool.schema.string().describe("Mesaj içeriği"),
      },
      execute: async (args) => {
        const result = await gatewayRequest<{ success: boolean; message_id: string }>("/channel/whatsapp/send", {
          method: "POST",
          body: JSON.stringify(args),
        })
        return JSON.stringify(result)
      },
    }),

    personalos_send_telegram: tool({
      description: "Telegram mesajı gönderir.",
      args: {
        chat_id: tool.schema.string().describe("Sohbet ID"),
        message: tool.schema.string().describe("Mesaj içeriği"),
      },
      execute: async (args) => {
        const result = await gatewayRequest<{ success: boolean; message_id: string }>("/channel/telegram/send", {
          method: "POST",
          body: JSON.stringify(args),
        })
        return JSON.stringify(result)
      },
    }),

    personalos_send_email: tool({
      description: "E-posta gönderir.",
      args: {
        to: tool.schema.string().describe("Alıcı e-posta"),
        subject: tool.schema.string().describe("Konu"),
        body: tool.schema.string().describe("E-posta içeriği"),
      },
      execute: async (args) => {
        const result = await gatewayRequest<{ success: boolean; message_id: string }>("/channel/email/send", {
          method: "POST",
          body: JSON.stringify(args),
        })
        return JSON.stringify(result)
      },
    }),
  }
}

// ==================== COMBINED EXPORT ====================

export function createPersonalosTools(ctx?: PluginInput): Record<string, ToolDefinition> {
  return {
    ...createPersonalosGatewayTools(ctx),
    ...createPersonalosAgentTools(ctx),
    ...createPersonalosDispatcherTools(ctx),
    ...createPersonalosChannelTools(ctx),
  }
}

export const personalosMemoryTools = {}
