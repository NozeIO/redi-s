//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-redis open source project
//
// Copyright (c) 2018 ZeeZide GmbH. and the swift-nio-redis project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import RedisServer
import Foundation


// MARK: - Handle Commandline Arguments

func help() {
  let cmd = CommandLine.arguments.first ?? "redis-server"
  print("Usage: \(cmd) -h or --help")
  print()
  print("Examples:")
  print("       \(cmd) (run the server with default conf)")
  print("       \(cmd) -p 1337")
}

let args = CommandLine.arguments.dropFirst()
if args.contains("--help") || args.contains("-h") {
  help()
  exit(0)
}

let cmdLinePort : Int? = {
  guard let idx = args.index(where: { [ "-p", "--port" ].contains($0) }) else {
    return nil
  }
  guard idx < args.count, let port = UInt16(args[idx + 1]) else {
    print("Missing or invalid value for", args[idx], "argument")
    exit(42)
  }
  return Int(port)
}()


// MARK: - Setup Configuration

let logger = RedisPrintLogger()

logger.warn("sSZSsSZSsSZSs Redi/S is starting sSZSsSZSsSZSs")
logger.warn("Redi/S"
          + " bits=\(MemoryLayout<Int>.size * 8),"
          + " pid=\(getpid()),"
          + " just started")


let configuration = RedisServer.Configuration()
configuration.logger = logger
configuration.port   = cmdLinePort ?? 1337

configuration.savePoints = {
  typealias SavePoint = RedisServer.Configuration.SavePoint
  return [ SavePoint(delay: 10, changeCount: 100) ]
}()

logger.warn("Configuration loaded")

// MARK: - Run Server

let server = RedisServer(configuration: configuration)
defer { try! server.group.syncShutdownGracefully() }

signal(SIGINT) { // Safe? Unsafe. No idea :-)
  s in server.stopOnSigInt()
}

server.listenAndWait()
