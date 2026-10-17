import Foundation

// One binary, two modes: with arguments it's the `lgremote` CLI, without it's the GUI app.
// Launch Services and Xcode may inject their own flags, so ignore those when deciding.
let cliArguments = CommandLine.arguments.dropFirst().filter {
    !$0.hasPrefix("-psn_") && !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") && $0 != "--background"
}

if cliArguments.isEmpty {
    LGRemoteApp.main()
} else {
    Task {
        exit(await CLI.run(Array(cliArguments)))
    }
    dispatchMain()
}
