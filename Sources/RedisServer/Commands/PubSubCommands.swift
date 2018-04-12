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
import NIO
import enum   NIORedis.RESPValue
import struct Foundation.Data

extension Commands {
  static func PUBLISH(channel: Data, message value: RESPValue,
                      in ctx: CommandContext) throws
  {
    guard let message = value.byteBuffer else { throw RedisError.wrongType }
    
    let pubsub = ctx.handler.server.pubSub
    pubsub.Q.async {
      let count = pubsub.publish(channel, message)
      ctx.write(count)
    }
  }
  
  static func SUBSCRIBE(channelKeys: ContiguousArray<Data>,
                        in ctx: CommandContext) throws
  {
    guard !channelKeys.isEmpty else { throw RedisError.syntaxError }
    
    let subscribeCmd = RESPValue(simpleString: "subscribe")
    
    var subscribedChannels = ctx.handler.subscribedChannels ?? Set()
    
    let pubsub = ctx.handler.server.pubSub
    pubsub.Q.async {
      for key in channelKeys {
        if !subscribedChannels.contains(key) {
          subscribedChannels.insert(key)
          pubsub.subscribe(key, handler: ctx.handler)
        }
        
        ctx.eventLoop.execute {
          if ctx.handler.subscribedChannels == nil {
            ctx.handler.subscribedChannels = Set()
          }
          ctx.handler.subscribedChannels!.insert(key)
          let count = ctx.handler.subscribedChannels!.count
          ctx.write([ subscribeCmd,
                      RESPValue(bulkString: key),
                      RESPValue.integer(count) ].toRESPValue())
        }
      }
    }
  }
  
  static func UNSUBSCRIBE(channelKeys: ContiguousArray<Data>,
                          in ctx: CommandContext) throws
  {
    guard !channelKeys.isEmpty else { throw RedisError.syntaxError }
    
    let subscribeCmd = RESPValue(simpleString: "unsubscribe")
    
    var subscribedChannels = ctx.handler.subscribedChannels ?? Set()
    
    let pubsub = ctx.handler.server.pubSub
    pubsub.Q.async {
      for key in channelKeys {
        if subscribedChannels.contains(key) {
          subscribedChannels.remove(key)
          pubsub.unsubscribe(key, handler: ctx.handler)
        }
        
        ctx.eventLoop.execute {
          ctx.handler.subscribedChannels?.remove(key)
          let count = ctx.handler.subscribedChannels?.count ?? 0
          ctx.write([ subscribeCmd,
                      RESPValue(bulkString: key),
                      RESPValue.integer(count) ].toRESPValue())
        }
      }
    }
  }
  
  static func PSUBSCRIBE(patternValues: ArraySlice<RESPValue>,
                         in ctx: CommandContext) throws
  {
    // sigh: lots of WET
    guard !patternValues.isEmpty else { throw RedisError.syntaxError }
    guard let patterns = patternValues.extractByteBuffersAndPatterns() else {
      throw RedisError.wrongType
    }
    
    let subscribeCmd = RESPValue(simpleString: "psubscribe")
    
    var subscribedPatterns = ctx.handler.subscribedPatterns ?? Set()
    
    let pubsub = ctx.handler.server.pubSub
    pubsub.Q.async {
      for ( bb, key ) in patterns {
        if !subscribedPatterns.contains(key) {
          subscribedPatterns.insert(key)
          pubsub.subscribe(key, handler: ctx.handler)
        }
        
        ctx.eventLoop.execute {
          if ctx.handler.subscribedPatterns == nil {
            ctx.handler.subscribedPatterns = Set()
          }
          ctx.handler.subscribedPatterns!.insert(key)
          let count = ctx.handler.subscribedPatterns!.count
          ctx.write([ subscribeCmd,
                      RESPValue.bulkString(bb),
                      RESPValue.integer(count) ].toRESPValue())
        }
      }
    }
  }
  
  static func PUNSUBSCRIBE(patternValues: ArraySlice<RESPValue>,
                           in ctx: CommandContext) throws
  {
    // sigh: lots of WET
    guard !patternValues.isEmpty else { throw RedisError.syntaxError }
    guard let patterns = patternValues.extractByteBuffersAndPatterns() else {
      throw RedisError.wrongType
    }
    
    let subscribeCmd = RESPValue(simpleString: "punsubscribe")
    
    var subscribedPatterns = ctx.handler.subscribedPatterns ?? Set()
    
    let pubsub = ctx.handler.server.pubSub
    pubsub.Q.async {
      for ( bb, key ) in patterns {
        if subscribedPatterns.contains(key) {
          subscribedPatterns.remove(key)
          pubsub.unsubscribe(key, handler: ctx.handler)
        }
        
        ctx.eventLoop.execute {
          ctx.handler.subscribedPatterns?.remove(key)
          let count = ctx.handler.subscribedPatterns?.count ?? 0
          ctx.write([ subscribeCmd,
                      RESPValue.bulkString(bb),
                      RESPValue.integer(count) ].toRESPValue())
        }
      }
    }
  }
  
  static func PUBSUB(values: ArraySlice<RESPValue>,
                     in ctx: CommandContext) throws
  {
    guard let subcmd = values.first?.stringValue?.uppercased() else {
      throw RedisError.syntaxError
    }
    
    let argIdx = values.startIndex.advanced(by: 1)
    let args   = values[argIdx..<values.endIndex]
    
    switch subcmd {
      case "CHANNELS":
        guard args.count == 0 || args.count == 1 else {
          throw RedisError.wrongNumberOfArguments(command: "PUBSUB")
        }
        
        if args.count == 0 {
          channelList(in: ctx)
        }
        else {
          switch args[args.startIndex] {
            case .simpleString(let bb), .bulkString(.some(let bb)):
              guard let pattern = RedisPattern(bb) else {
                throw RedisError.wrongType
              }
              channelList(pattern: pattern, in: ctx)
            
            default:
              throw RedisError.wrongType
          }
        }
      
      case "NUMSUB":
        guard !args.isEmpty else { return ctx.write([]) }
        let keys : [ Data ] = try args.map {
          guard let key = $0.keyValue else { throw RedisError.wrongType }
          return key
        }
        channelSubscriberCounts(keys, in: ctx)
      
      case "NUMPAT":
        let pubSub = ctx.handler.server.pubSub
        pubSub.Q.async {
          ctx.write(pubSub.patternToEventLoopToSubscribers.count)
        }
      
      default:
        throw RedisError.unknownSubcommand
    }
  }
  
  static func channelSubscriberCounts(_ channels: [ Data ],
                                      in ctx: CommandContext)
  {
    let pubSub = ctx.handler.server.pubSub
    pubSub.Q.async {
      var channelCountPairs = ContiguousArray<RESPValue>()
      
      for channel in channels {
        guard let loop2Sub = pubSub.channelToEventLoopToSubscribers[channel],
                 !loop2Sub.isEmpty else {
          channelCountPairs.append(RESPValue(bulkString: channel))
          channelCountPairs.append(.integer(0))
          continue
        }
        
        let count = loop2Sub.values.reduce(0) { $0 + $1.count }
        channelCountPairs.append(RESPValue(bulkString: channel))
        channelCountPairs.append(.integer(count))
      }
      
      ctx.write(.array(channelCountPairs))
    }
  }
  
  static func channelList(pattern: RedisPattern? = nil,
                          in ctx: CommandContext)
  {
    let pubSub = ctx.handler.server.pubSub
    pubSub.Q.async {
      var channels = ContiguousArray<RESPValue>()
      
      for ( channel, loop2Sub ) in pubSub.channelToEventLoopToSubscribers {
        guard !loop2Sub.isEmpty                      else { continue }
        if let pattern = pattern {
          if !pattern.match(channel) { continue }
        }
        
        var isActive = false
        for sub in loop2Sub.values {
          if !sub.isEmpty {
            isActive = true
            break
          }
        }
        if isActive { channels.append(RESPValue(bulkString: channel)) }
      }
      
      ctx.write(.array(channels))
    }
  }
}


extension Collection where Element == RESPValue {
  
  func extractByteBuffersAndPatterns()
         -> ContiguousArray<(ByteBuffer, RedisPattern)>?
  {
    var patterns = ContiguousArray<(ByteBuffer, RedisPattern)>()
    #if swift(>=4.1)
      patterns.reserveCapacity(count)
    #else
      if let count = count as? Int { patterns.reserveCapacity(count) }
    #endif
    
    for item in self {
      guard let bb = item.byteBuffer else { return nil }
      guard let pattern = RedisPattern(bb) else { return nil }
      patterns.append( ( bb, pattern ) )
    }
    return patterns
  }
  
}
