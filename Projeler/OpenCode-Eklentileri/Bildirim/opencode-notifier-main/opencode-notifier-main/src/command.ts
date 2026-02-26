import { spawn } from "child_process"
import type { EventType, NotifierConfig } from "./config"

function substituteTokens(value: string, event: EventType, message: string, sessionTitle?: string | null, projectName?: string | null): string {
  let result = value.replaceAll("{event}", event).replaceAll("{message}", message)
  result = result.replaceAll("{sessionTitle}", sessionTitle || "")
  result = result.replaceAll("{projectName}", projectName || "")
  return result
}

export function runCommand(config: NotifierConfig, event: EventType, message: string, sessionTitle?: string | null, projectName?: string | null): void {
  if (!config.command.enabled || !config.command.path) {
    return
  }

  const args = (config.command.args ?? []).map((arg) => substituteTokens(arg, event, message, sessionTitle, projectName))
  const command = substituteTokens(config.command.path, event, message, sessionTitle, projectName)

  const proc = spawn(command, args, {
    stdio: "ignore",
    detached: true,
  })

  proc.on("error", () => {})
  proc.unref()
}
