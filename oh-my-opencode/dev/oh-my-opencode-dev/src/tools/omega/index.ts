/**
 * OMEGA Tool
 * 
 * OMEGA v120.0 - Köstebek İliği Sistem Entegrasyonu
 * Python tabanlı CLI emülasyonu, hafıza ve kalkan sistemi
 */

import type { PluginInput } from "@opencode-ai/plugin"
import { tool, type ToolDefinition } from "@opencode-ai/plugin/tool"
import { execSync } from "child_process"
import { existsSync } from "fs"
import { join } from "path"

// Environment Configuration
const OMEGA_PYTHON = process.env.OMEGA_PYTHON || "python"
const OMEGA_SCRIPT = process.env.OMEGA_SCRIPT || 
  "D:/OpenCode/PersonalOS/integration/agents/runtime/skills/omega/omega.py"

// ==================== TOOL FACTORIES =====================

export function createOmegaTools(_ctx?: PluginInput): Record<string, ToolDefinition> {
  return {
    omega_status: tool({
      description: "OMEGA v120.0 sistem durumunu getirir. Hafıza, biyoloji ve sistem bilgilerini gösterir.",
      args: {},
      execute: async () => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" DUR`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_execute: tool({
      description: "OMEGA sisteminde komut çalıştırır. CLI emülasyonu üzerinden işlem yapar.",
      args: {
        command: tool.schema.string().describe("Çalıştırılacak komut (O, L, S, DUR, TEMIZLE vb.)"),
      },
      execute: async (args) => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" ${args.command}`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_summary: tool({
      description: "OMEGA hafızasını ve özetini getirir. Tüm kayıtları ve sistem durumunu gösterir.",
      args: {},
      execute: async () => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" O`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_logs: tool({
      description: "OMEGA ebedi log kayıtlarını getirir. Son 10 işlemi gösterir.",
      args: {
        limit: tool.schema.number().optional().describe("Gösterilecek kayıt sayısı (varsayılan: 10)"),
      },
      execute: async (args) => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" L`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_clear: tool({
      description: "OMEGA hafızasını temizler. Tüm kayıtları siler.",
      args: {},
      execute: async () => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" TEMIZLE`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_help: tool({
      description: "OMEGA yardım menüsünü getirir. Kullanılabilir komutları gösterir.",
      args: {},
      execute: async () => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" YARDIM`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_sprint: tool({
      description: "OMEGA hızlı sistem döngüsü çalıştırır. Tam performans testi yapar.",
      args: {},
      execute: async () => {
        try {
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" S`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          return result
        } catch (error) {
          return JSON.stringify({ error: String(error) })
        }
      },
    }),

    omega_check: tool({
      description: "OMEGA sistem sağlık kontrolü yapar. Çalışıp çalışmadığını doğrular.",
      args: {},
      execute: async () => {
        try {
          if (!existsSync(OMEGA_SCRIPT)) {
            return JSON.stringify({ 
              status: "error", 
              message: "OMEGA script not found",
              path: OMEGA_SCRIPT
            })
          }
          
          const result = execSync(`"${OMEGA_PYTHON}" "${OMEGA_SCRIPT}" DUR`, {
            encoding: "utf-8",
            timeout: 10000,
          })
          
          return JSON.stringify({
            status: "ok",
            script_path: OMEGA_SCRIPT,
            result: result.trim()
          })
        } catch (error) {
          return JSON.stringify({ 
            status: "error", 
            error: String(error) 
          })
        }
      },
    }),
  }
}
