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

import Dispatch
import struct NIO.ByteBufferAllocator
import struct NIO.NIOAny
import enum   NIORedis.RESPValue
import struct Foundation.Data

extension Commands {
  
  static func COMMAND(value: RESPValue?, in ctx: CommandContext) throws {
    let commandTable = ctx.handler.server.commandTable
    
    if let value = value {
      guard let s = value.stringValue else {
        throw RedisError.unknownSubcommand // TBD? ProtocolError?
      }
      
      switch s.uppercased() {
        case "COUNT": ctx.write(commandTable.count)
        default: throw RedisError.unknownSubcommand
      }
    }
    else {
      ctx.write(commandTable)
    }
  }
  
  static func SELECT(value: RESPValue?, in ctx: CommandContext) throws {
    guard let dbIndex = value?.intValue else {
      throw RedisError.invalidDBIndex
    }
    guard dbIndex >= 0 && dbIndex < ctx.databases.databases.count else {
      throw RedisError.dbIndexOutOfRange
    }
    
    ctx.handler.databaseIndex = dbIndex
    
    ctx.write(RESPValue.ok)
  }
  
  static func SWAPDB(swap from: RESPValue, with to: RESPValue,
                     in ctx: CommandContext) throws
  {
    guard let fromIndex = from.intValue, let toIndex = to.intValue else {
      throw RedisError.invalidDBIndex
    }
    
    let dbs   = ctx.databases
    let count = dbs.databases.count
    
    guard fromIndex >= 0 && fromIndex < count
       && toIndex   >= 0 && toIndex   < count else {
      throw RedisError.dbIndexOutOfRange
    }
    guard fromIndex != toIndex else {
      return ctx.write(RESPValue.ok)
    }
    
    do {
      let lock = dbs.context.lock
      lock.lockForWriting()
      defer { lock.unlock() }
      
      let other = dbs.databases[fromIndex]
      dbs.databases[fromIndex] = dbs.databases[toIndex]
      dbs.databases[toIndex] = other
    }
    
    ctx.write(RESPValue.ok)
  }

  static func PING(value: RESPValue?, in ctx: CommandContext) throws {
    guard let value = value else {
      return ctx.write(RESPValue(simpleString: "PONG"))
    }
    ctx.write(value)
  }
  
  static func MONITOR(_ ctx: CommandContext) throws {
    let client = ctx.handler
    guard !client.isMonitoring.load() else { return ctx.write(RESPValue.ok) }
    
    client.isMonitoring.store(true)
    _ = client.server.monitors.add(1)
    ctx.write(RESPValue.ok)
  }
  
  static func QUIT(_ ctx: CommandContext) throws {
    ctx.context.channel.close(mode: .input, promise: nil)
    
    ctx.context.writeAndFlush(NIOAny(RESPValue.ok))
               .whenComplete {
                 ctx.context.channel.close(promise: nil)
               }
  }
  
  static func SAVE(_ ctx: CommandContext) throws {
    let async  = ctx.command.name.uppercased() == "BGSAVE"
    let server = ctx.handler.server
    
    try ctx.writeInDatabase { _ in
      try server.dumpManager.saveDump(of: ctx.databases, to: server.dumpURL,
                                      asynchronously: async)
      ctx.write(RESPValue.ok)
    }
  }
  
  static func LASTSAVE(_ ctx: CommandContext) throws {
    ctx.handler.server.dumpManager.getLastSave { stamp, _ in
      ctx.write(Int(stamp.timeIntervalSince1970))
    }
  }


  // MARK: - Client

  static func CLIENT(values: ArraySlice<RESPValue>,
                     in ctx: CommandContext) throws
  {
    guard let subcmd = values.first?.stringValue?.uppercased() else {
      throw RedisError.syntaxError
    }
    let args = values[1..<values.count]
    
    switch subcmd {
      case "SETNAME":
        guard let name = args.first?.stringValue else {
          throw RedisError.syntaxError
        }
        ctx.handler.name = name
        ctx.write(RESPValue.ok)

      case "GETNAME":
        guard args.isEmpty else { throw RedisError.syntaxError }
        ctx.write(RESPValue(bulkString: ctx.handler.name))
      
      case "LIST":
        clientList(ctx)
      
      // TODO: KILL, PAUSE, REPLY
      default:
        throw RedisError.unknownSubcommand
    }
  }
  
  static func clientList(_ ctx: CommandContext) {
    let server = ctx.handler.server
    
    let listQueue = DispatchQueue(label: "de.zeezide.nio.redisd.client.info")
    
    server.Q.async {
      
      let clients = server.clients.values
      
      // do not block the server
      listQueue.async {
        let nl : [ UInt8 ] = [ 10 ]
        var count  = clients.count
        guard count > 0 else { return ctx.write("") } // Never
        
        var result = ByteBufferAllocator().buffer(capacity: 1024)
        func yield(_ info: RedisCommandHandler.ClientInfo) {
          listQueue.async {
            assert(count > 0)
            count -= 1
            
            result.write(string: info.redisClientLogLine)
            result.write(bytes: nl)
            
            if count == 0 {
              ctx.write(.bulkString(result))
            }
          }
        }
        
        // This could be improved by grouping the clients by eventLoop and only
        // issue a single statistics collector.
        for client in clients {
          if let eventLoop = client.eventLoop {
            eventLoop.execute {
              yield(client.getClientInfo())
            }
          }
          else {
            yield(client.getClientInfo())
          }
        }
      }
    }
  }
}

fileprivate extension RedisCommandHandler.ClientInfo {
  
  var redisClientLogLine : String {
    var ms = "id=\(id)"
    
    if let v = addr { ms += " addr=\(v)" }
    if let v = name { ms += " name=\(v)" }

    ms += " age=\(Int64(age)) idle=\(Int64(idle))"
    // flags
    ms += " db=\(db)"
    
    if let v = cmd?.lowercased() { ms += " cmd=\(v)" }
    return ms
  }
}

