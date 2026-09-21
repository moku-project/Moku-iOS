import Darwin
import Foundation
import MokuIOSCore

var activeRunner: Runner?
var sources: [DispatchSourceSignal] = []
do {
  let command = try Command(Array(CommandLine.arguments.dropFirst()))
  if command.name == "help" {
    print(Command.help)
  } else {
    let runner = Runner(root: try Runner.findRoot(command.repo))
    activeRunner = runner
    for number in [SIGINT, SIGTERM] {
      signal(number, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { runner.cancel() }
      source.resume()
      sources.append(source)
    }
    try Workflow(runner: runner).execute(command)
    if runner.cancelled { exit(130) }
  }
} catch {
  FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
  exit(activeRunner?.cancelled == true ? 130 : 1)
}
