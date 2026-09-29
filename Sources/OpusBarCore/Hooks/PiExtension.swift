import Foundation
import OpusBarWire

/// pi and OMP have no hooks file: they load TypeScript extensions from `<agent dir>/extensions/`.
/// OpusBar writes one file there, `opusbar.ts`, that turns pi events into the same hook payloads
/// Claude sends and hands them to `opusbar-hook`. Only that file is ever written or removed.
public struct PiExtensionInstaller: Sendable {
    public static let fileName = "opusbar.ts"
    /// First line of every file OpusBar writes; a file without it is never touched.
    static let marker = "// OpusBar live states for pi and OMP."

    public let agent: AgentKind
    /// `~/.pi/agent/extensions/opusbar.ts`, `~/.omp/agent/extensions/opusbar.ts`.
    public let fileURL: URL
    public let hookBinary: URL

    public init(agent: AgentKind, fileURL: URL, hookBinary: URL) {
        self.agent = agent
        self.fileURL = fileURL
        self.hookBinary = hookBinary
    }

    public func status() -> HookInstaller.Status {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else { return .notInstalled }
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix(Self.marker) else {
            return .unreadable("Another \(Self.fileName) is there")
        }
        // Ours but written by another OpusBar version or for another hook path: Connect rewrites it.
        return text == source ? .installed : .partial(missing: [])
    }

    /// Copies the hook into place, then writes the extension. Refuses to replace a file that isn't ours.
    @discardableResult
    public func install(hookSource: URL, installBinary: (URL) throws -> Void) throws -> HookInstaller.Status {
        if case .unreadable(let reason) = status() { throw HookInstaller.InstallError.unreadable(reason) }
        try installBinary(hookSource)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(source.utf8).write(to: fileURL, options: .atomic)
        guard status() == .installed else { throw HookInstaller.InstallError.verifyFailed }
        return .installed
    }

    /// Removes the file only when it is ours.
    @discardableResult
    public func uninstall() throws -> HookInstaller.Status {
        switch status() {
        case .installed, .partial: try FileManager.default.removeItem(at: fileURL)
        case .notInstalled, .unreadable: break
        }
        return status()
    }

    /// The extension. Sends the session id, cwd, session file, event name and tool name; never prompts,
    /// tool input or output, or messages. Spawns the hook without a shell, never waits on it, swallows
    /// every error, and returns nothing from handlers (a return value could block a tool or change a prompt).
    public var source: String {
        """
        \(Self.marker)
        // Written by OpusBar; Disconnect in OpusBar's Settings removes it. Edits are overwritten on Connect.
        // Sends session state only (ids, folder, event and tool names) to OpusBar on this Mac.
        import { spawn } from "node:child_process";

        const HOOK = \(Self.jsString(hookBinary.path));
        const AGENT = \(Self.jsString(agent.rawValue));

        export default function (pi: any) {
          // One hook at a time, in event order: the hook stamps the time when it starts, and OpusBar
          // drops events older than the last one it applied.
          let queue: Promise<void> = Promise.resolve();
          const run = (payload: string) => new Promise<void>((done) => {
            try {
              const child = spawn(HOOK, ["--agent", AGENT], { stdio: ["pipe", "ignore", "ignore"], detached: true });
              child.on("error", () => done());
              child.on("close", () => done());
              child.stdin?.on("error", () => {});
              child.stdin?.end(payload);
              child.unref();
            } catch { done(); }
          });
          const send = (ctx: any, event: string, extra: Record<string, unknown> = {}, now = false) => {
            try {
              const sessions = ctx?.sessionManager;
              const sessionId = sessions?.getSessionId?.();
              if (!sessionId) return;
              const payload = JSON.stringify({
                session_id: sessionId,
                hook_event_name: event,
                cwd: ctx.cwd,
                transcript_path: sessions.getSessionFile?.(),
                ...extra,
              });
              if (now) void run(payload);
              else queue = queue.then(() => run(payload));
            } catch {}
          };

          pi.on("session_start", (_event: any, ctx: any) => { send(ctx, "SessionStart"); });
          pi.on("before_agent_start", (_event: any, ctx: any) => { send(ctx, "UserPromptSubmit"); });
          pi.on("tool_call", (event: any, ctx: any) => { send(ctx, "PreToolUse", { tool_name: event?.toolName }); });
          pi.on("tool_result", (event: any, ctx: any) => { send(ctx, "PostToolUse", { tool_name: event?.toolName }); });
          pi.on("agent_end", (event: any, ctx: any) => {
            const messages = Array.isArray(event?.messages) ? event.messages : [];
            const last = [...messages].reverse().find((message: any) => message?.role === "assistant");
            if (last?.stopReason === "error") send(ctx, "StopFailure");
            else if (last?.stopReason === "aborted") send(ctx, "Stop", { reason: "aborted" });
            else send(ctx, "Stop");
          });
          // pi may exit without waiting: SessionEnd goes out at once, and again after the queue, so an
          // event still in line can't bring the row back.
          pi.on("session_shutdown", async (_event: any, ctx: any) => {
            send(ctx, "SessionEnd", {}, true);
            send(ctx, "SessionEnd");
            await queue;
          });
        }

        """
    }

    /// A JSON string literal is a valid JavaScript string literal.
    static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }
}
