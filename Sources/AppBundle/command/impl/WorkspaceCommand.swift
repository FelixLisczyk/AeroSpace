import AppKit
import Common
import Foundation

struct WorkspaceCommand: Command {
    let args: WorkspaceCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool { // todo refactor
        print("""
        WorkspaceCommand.run() started with:
        - args: \(args)
        - env: \(env)
        - io: \(io)
        - current focus: \(focus)
        - previous focus: \(String(describing: _prevFocus))
        - current workspace: \(focus.workspace.name)
        - current window: \(String(describing: focus.windowOrNil))
        - current monitor: \(focus.workspace.workspaceMonitor)
        - prev workspace: \(_prevFocusedWorkspaceName ?? "nil")
        - prev window: \(_prevFocus?.windowId.map { "\($0)" } ?? "nil")
        """)
        guard let target = args.resolveTargetOrReportError(env, io) else {
            print("""
            WorkspaceCommand.run() failed to resolve target:
            - args: \(args)
            - env: \(env)
            - current workspace: \(focus.workspace.name)
            """)
            return false
        }
        print("WorkspaceCommand.run() resolved target: \(target)")
        let focusedWs = target.workspace
        let workspaceName: String
        switch args.target.val {
            case .relative(let isNext):
                print("WorkspaceCommand.run() handling relative target (isNext: \(isNext))")
                let workspace = getNextPrevWorkspace(
                    current: focusedWs,
                    isNext: isNext,
                    wrapAround: args.wrapAround,
                    stdin: io.readStdin(),
                    target: target
                )
                guard let workspace else { return false }
                workspaceName = workspace.name
            case .direct(let name):
                workspaceName = name.raw
                print("WorkspaceCommand.run() handling direct target '\(workspaceName)'")
                if args.autoBackAndForth && focusedWs.name == workspaceName {
                    print("WorkspaceCommand.run() autoBackAndForth triggered for workspace '\(workspaceName)'")
                    return WorkspaceBackAndForthCommand(args: WorkspaceBackAndForthCmdArgs(rawArgs: [])).run(env, io)
                }
        }
        if focusedWs.name == workspaceName {
            print("WorkspaceCommand.run() no-op - already focused on workspace '\(workspaceName)'")
            io.err("Workspace '\(workspaceName)' is already focused. Tip: use --fail-if-noop to exit with non-zero code")
            return !args.failIfNoop
        } else {
            print("WorkspaceCommand.run() focusing workspace '\(workspaceName)'")
            return Workspace.get(byName: workspaceName).focusWorkspace()
        }
    }
}

@MainActor func getNextPrevWorkspace(current: Workspace, isNext: Bool, wrapAround: Bool, stdin: String, target: LiveFocus) -> Workspace? {
    let stdinWorkspaces: [String] = stdin.split(separator: "\n").map { String($0).trim() }.filter { !$0.isEmpty }
    let currentMonitor = current.workspaceMonitor
    let workspaces: [Workspace] = stdinWorkspaces.isEmpty
        ? Workspace.all.filter { $0.workspaceMonitor.rect.topLeftCorner == currentMonitor.rect.topLeftCorner }
            .toSet()
            .union([current])
            .sorted()
        : stdinWorkspaces.map { Workspace.get(byName: $0) }
    let index = workspaces.firstIndex(where: { $0 == target.workspace }) ?? 0
    let workspace: Workspace? = if wrapAround {
        workspaces.get(wrappingIndex: isNext ? index + 1 : index - 1)
    } else {
        workspaces.getOrNil(atIndex: isNext ? index + 1 : index - 1)
    }
    return workspace
}
