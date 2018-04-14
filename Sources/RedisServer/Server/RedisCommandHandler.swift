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

import NIO
import NIORedis
import class NIOConcurrencyHelpers.Atomic
import struct Foundation.Data
import struct Foundation.Date
import struct Foundation.TimeInterval

/**
 * Redis commands are sent as plain RESP arrays. For example
 *
 *     SET answer 42
 *
 * Arrives as:
 *
 *     [ "SET", "answer", 42 ]
 *
 */
final class RedisCommandHandler : RESPChannelHandler {
  // See [Avoid NIO Pipeline](Performance.md#avoid-nio-pipeline-for-non-bb)
  // for the reason why this is a subclass (instead of a consumer of the
  // RESPChannelHandler producer.
  
  public typealias Context = RedisCommandContext
  public typealias Command = RedisCommand

  let id            : Int
  let creationDate  = Date()
  let server        : RedisServer // intentional cycle!
  let commandMap    : [ String : Command ]
  
  var channel       : Channel?
  var eventLoop     : EventLoop?
  var remoteAddress : SocketAddress?
  
  var lastActivity  = Date()
  var lastCommand   : String?
  var name          : String?
  var databaseIndex = 0
  var isMonitoring  = Atomic<Bool>(value: false)
  
  var subscribedChannels : Set<Data>?
  var subscribedPatterns : Set<RedisPattern>?

  init(id: Int, server: RedisServer) {
    self.id         = id
    self.server     = server
    self.commandMap = server.commandMap
    super.init()
  }
  
  
  // MARK: - Channel Activation
  
  override open func channelActive(ctx: ChannelHandlerContext) {
    eventLoop     = ctx.eventLoop
    remoteAddress = ctx.remoteAddress
    channel       = ctx.channel
    
    super.channelActive(ctx: ctx)
  }
  
  override open func channelInactive(ctx: ChannelHandlerContext) {
    if let channels = subscribedChannels, !channels.isEmpty {
      subscribedChannels = nil
      
      server.pubSub.Q.async {
        for channel in channels {
          self.server.pubSub.unsubscribe(channel, handler: self)
        }
      }
    }
    if let patterns = subscribedPatterns, !patterns.isEmpty {
      subscribedPatterns = nil
      
      server.pubSub.Q.async {
        for pattern in patterns {
          self.server.pubSub.unsubscribe(pattern, handler: self)
        }
      }
    }
    
    super.channelInactive(ctx: ctx)

    server.Q.async {
      self.server._unregisterClient(self)
    }
    self.channel   = nil
  }
  
  
  // MARK: - PubSub
  
  func handleNotification(_ payload: RESPValue) {
    guard let channel = channel else {
      assert(self.channel != nil, "notification, but channel is gone?")
      return
    }
    
    channel.writeAndFlush(payload, promise: nil)
  }
  
  
  // MARK: - Reading

  override open func channelRead(ctx: ChannelHandlerContext, value: RESPValue) {
    lastActivity = Date()
    do {
      let ( command, args ) = try parseCommandCall(value)
      
      if server.monitors.load() > 0 {
        let info = MonitorInfo(db: databaseIndex, addr: remoteAddress,
                               call: value)
        server.notifyMonitors(info: info)
      }
      
      lastCommand = command.name
      
      guard let dbs = server.databases else {
        assert(server.databases != nil, "server has no databases?!")
        throw RedisError.internalServerError
      }
      
      let cmdctx = RedisCommandContext(command   : command,
                                       handler   : self,
                                       context   : ctx,
                                       databases : dbs)
      try callCommand(command, with: args, in: cmdctx)
    }
    catch let error as RESPError {
      self.write(ctx: ctx, value: error.toRESPValue(), promise: nil)
    }
    catch let error as RESPEncodable {
      self.write(ctx: ctx, value: error.toRESPValue(), promise: nil)
    }
    catch {
      let respError = RESPError(message: "\(error)")
      self.write(ctx: ctx, value: respError.toRESPValue(), promise: nil)
    }
  }
  
  override open func errorCaught(ctx: ChannelHandlerContext, error: Error) {
    super.errorCaught(ctx: ctx, error: error)
    server.logger.error("Channel", error)
    ctx.close(promise: nil)
  }
  
  
  // MARK: - Command Parsing and Invocation
  
  private func parseCommandCall(_ respValue: RESPValue) throws
                 -> ( Command, ContiguousArray<RESPValue>)
  {
    guard case .array(.some(let commandList)) = respValue else {
      // RESPError(code: "ERR", message: "unknown command \'$4\'")
      throw RESPError(message: "invalid command \(respValue)")
    }
    
    guard let commandName = commandList.first?.stringValue else {
      throw RESPError(message: "missing command \(respValue)")
    }
    
    guard let command = commandMap[commandName.uppercased()] else {
      throw RESPError(message: "unknown command \(commandName)")
    }
    
    server.logger.trace("Parsed command:", commandName, commandList,
                        "\n ", command)
    
    guard isArgumentCountValid(commandList.count, for: command) else {
      throw RESPError(message:
              "wrong number of arguments for '\(commandName)' command")
    }
    
    return ( command, commandList )
  }
  
  private func isArgumentCountValid(_ countIncludingCommand: Int,
                                    for command: Command) -> Bool
  {
    switch command.type.keys.arity {
      case .fix(let count):
        return (count + 1) == countIncludingCommand
      
      case .minimum(let minimumCount):
        return countIncludingCommand > minimumCount
    }
  }
  
  private func callCommand(_ command      : Command,
                           with arguments : ContiguousArray<RESPValue>,
                           in   ctx       : Context) throws
  {
    // Note: Argument counts are validated. Safe to access the values.
    let firstKeyIndex = command.type.keys.firstKey
    
    // This Nice Not Is. Ideas welcome, in a proper language we would just
    // reflect. In a not so proper language we would use macros to hide the
    // non-sense. But in Swift, hm.
    switch command.type {
      case .noArguments(let cb):
        try cb(ctx)
      
      case .singleValue(let cb):
        try cb(arguments[1], ctx)
      
      case .valueValue(let cb):
        try cb(arguments[1], arguments[2], ctx)

      case .optionalValue(let cb):
        if arguments.count > 2 {
          throw RESPError(message: "wrong number of arguments for "
                                 + "'\(command.name.lowercased())' command")
        }
        try cb(arguments.count > 1 ? arguments[1] : nil, ctx)

      case .oneOrMoreValues(let cb):
        try cb(arguments[1..<arguments.count], ctx)

      case .key(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          try cb(key, ctx)
        }
      
      case .keyKey(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key1 in
          guard let key1 = key1 else { throw RedisError.expectedKey }
          try arguments[firstKeyIndex + 1].withSafeKeyValue { key2 in
            guard let key2 = key2 else { throw RedisError.expectedKey }
            try cb(key1, key2, ctx)
          }
        }
      
      case .keyValue(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          try cb(key, arguments[firstKeyIndex + 1], ctx)
        }
      
      case .keyValueValue(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          try cb(key, arguments[firstKeyIndex + 1], arguments[firstKeyIndex + 2],
                 ctx)
        }

      case .keyIndexValue(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          guard let idx = arguments[firstKeyIndex + 1].intValue else {
            throw RedisError.notAnInteger
          }
        
          try cb(key, idx, arguments[firstKeyIndex + 2], ctx)
        }
      
      case .keyValues(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          try cb(key, arguments[firstKeyIndex + 1..<arguments.count], ctx)
        }
      
      case .keyValueOptions(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          let value   = arguments[firstKeyIndex + 1]
          let options = arguments[firstKeyIndex + 2..<arguments.count]
          try cb(key, value, options, ctx)
        }
      
      case .keyRange(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          guard let from = arguments[firstKeyIndex + 1].intValue,
                let to   = arguments[firstKeyIndex + 2].intValue else {
            throw RedisError.notAnInteger
          }
          try cb(key, from, to, ctx)
        }
      
      case .keyIndex(let cb):
        try arguments[firstKeyIndex].withSafeKeyValue { key in
          guard let key = key else { throw RedisError.expectedKey }
          guard let idx = arguments[firstKeyIndex + 1].intValue else {
            throw RedisError.notAnInteger
          }
          try cb(key, idx, ctx)
        }
      
      case .keys(let cb):
        let range =
          arguments.rangeForRedisRange(start: firstKeyIndex,
                                       stop: command.type.keys.lastKey)
        let keysOpt = arguments[range].lazy.map { $0.keyValue }
        #if swift(>=4.1)
          let keys  = keysOpt.compactMap( { $0 })
        #else
          let keys  = keysOpt.flatMap( { $0 })
        #endif
        guard keysOpt.count == keys.count else {
          throw RESPError(message: "Protocol error: expected keys.")
        }
        
        try cb(ContiguousArray(keys), ctx)
      
      case .keyValueMap(let cb):
        let count = arguments.count
        guard count % 2 == 1 else {
          throw RESPError(message:
                            "wrong number of arguments for '\(command.name)'")
        }
        
        let step   = command.type.keys.step
        var values = ContiguousArray<( Data, RESPValue )>()
        values.reserveCapacity(count + 1)
        
        for i in stride(from: firstKeyIndex, to: count, by: step) {
          guard let key = arguments[i].keyValue else {
            throw RESPError(message: "Protocol error: expected key.")
          }
          values.append( ( key, arguments[i + 1] ) )
        }
      
        try cb(values, ctx)
    }
    
  }
  
  struct MonitorInfo {
    let db   : Int
    let addr : SocketAddress?
    let call : RESPValue
  }
  
  struct ClientInfo {
    let id   : Int
    let addr : SocketAddress?
    let name : String?
    let age  : TimeInterval
    let idle : TimeInterval
    // flags
    let db   : Int
    let cmd  : String?
  }
  
  func getClientInfo() -> ClientInfo {
    let now = Date()
    return ClientInfo(
      id   : id,
      addr : remoteAddress,
      name : name,
      age  : now.timeIntervalSince(creationDate),
      idle : now.timeIntervalSince(lastActivity),
      db   : databaseIndex,
      cmd  : lastCommand
    )
  }
  
}

fileprivate extension RESPValue {
  
  @inline(__always)
  func withSafeKeyValue(_ cb: ( Data? ) throws -> Void) rethrows {
    // SR-7378
    switch self {
      case .simpleString(let cs), .bulkString(.some(let cs)):
        #if false // this does not work, because key `Data` leaves scope
          try cs.withVeryUnsafeBytes { ptr in
            let ip = ptr.baseAddress!.advanced(by: cs.readerIndex)
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: ip),
                            count: cs.readableBytes,
                            deallocator: .none)
            try cb(data)
          }
        #else
          let data = cs.getData(at: cs.readerIndex, length: cs.readableBytes)
          try cb(data)
        #endif
      
      default:
        try cb(nil)
    }
  }
}

