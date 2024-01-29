//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-nio-redis open source project
//
// Copyright (c) 2018-2024 ZeeZide GmbH. and the swift-nio-redis project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import struct Foundation.Data
import struct NIO.ByteBuffer
import enum   NIORedis.RESPValue

class PubSub {
  
  typealias SubscriberList     = ContiguousArray<RedisCommandHandler>
  typealias LoopSubscribersMap = [ ObjectIdentifier : SubscriberList ]
  
  let Q : DispatchQueue
  var channelToEventLoopToSubscribers = [ Data         : LoopSubscribersMap ]()
  var patternToEventLoopToSubscribers = [ RedisPattern : LoopSubscribersMap ]()
  
  let subscriberCapacity = 128
  
  init(Q: DispatchQueue) {
    self.Q = Q
  }
  
  // MARK: - Publish
  
  func publish(_ channel: Data, _ message: ByteBuffer) -> Int {
    var count = 0
    
    let messagePayload : RESPValue = {
      var messageList = ContiguousArray<RESPValue>()
      messageList.reserveCapacity(3)
      messageList.append(RESPValue(simpleString: "message"))
      messageList.append(RESPValue(bulkString: channel))
      messageList.append(.bulkString(message))
      return .array(messageList)
    }()
    
    func notifySubscribers(_ map: LoopSubscribersMap) {
      for ( _, subscribers ) in map {
        guard !subscribers.isEmpty else { continue }
        
        guard let loop = subscribers[0].eventLoop else {
          assert(subscribers[0].eventLoop != nil, "subscriber without loop?!")
          continue
        }
        count += subscribers.count
        
        loop.execute {
          for subscriber in subscribers {
            subscriber.handleNotification(messagePayload)
          }
        }
      }
    }
    
    if let exact = channelToEventLoopToSubscribers[channel] {
      notifySubscribers(exact)
    }

    for ( pattern, loopToSubscribers ) in patternToEventLoopToSubscribers {
      guard pattern.match(channel) else { continue }
      notifySubscribers(loopToSubscribers)
    }
    
    return count
  }
  
  
  // MARK: - Subscribe/Unsubscribe
  
  func subscribe(_ channel: Data, handler: RedisCommandHandler) {
    subscribe(channel, registry: &channelToEventLoopToSubscribers,
              handler: handler)
  }
  
  func subscribe(_ pattern: RedisPattern, handler: RedisCommandHandler) {
    subscribe(pattern, registry: &patternToEventLoopToSubscribers,
              handler: handler)
  }
  
  func unsubscribe(_ channel: Data, handler: RedisCommandHandler) {
    unsubscribe(channel, registry: &channelToEventLoopToSubscribers,
                handler: handler)
  }
  
  func unsubscribe(_ pattern: RedisPattern, handler: RedisCommandHandler) {
    unsubscribe(pattern, registry: &patternToEventLoopToSubscribers,
                handler: handler)
  }

  @_specialize(where Key == Data)
  @_specialize(where Key == RedisPattern)
  private func subscribe<Key>(_ key: Key,
                              registry: inout [ Key : LoopSubscribersMap ],
                              handler: RedisCommandHandler)
  {
    guard let loop = handler.eventLoop else {
      assert(handler.eventLoop != nil, "try to operate on handler w/o loop")
      return
    }
    let loopID = ObjectIdentifier(loop)
    
    if var loopToSubscribers = registry[key] {
      if case nil = loopToSubscribers[loopID]?.append(handler) {
        loopToSubscribers[loopID] =
          ContiguousArray(handler, capacity: subscriberCapacity)
      }
      registry[key] = loopToSubscribers
    }
    else {
      registry[key] =
        [ loopID : ContiguousArray(handler, capacity: subscriberCapacity) ]
    }
  }
  
  @_specialize(where Key == Data)
  @_specialize(where Key == RedisPattern)
  private func unsubscribe<Key>(_ key: Key,
                                registry: inout [ Key : LoopSubscribersMap ],
                                handler: RedisCommandHandler)
  {
    guard let loop = handler.eventLoop else {
      assert(handler.eventLoop != nil, "try to operate on handler w/o loop")
      return
    }
    let loopID = ObjectIdentifier(loop)
    
    guard var loopToSubscribers = registry[key]                  else { return }
    guard var subscribers = loopToSubscribers[loopID]            else { return }
    guard let idx = subscribers.firstIndex(where: { $0 === handler }) else {
      return
    }
    
    subscribers.remove(at: idx)
    if subscribers.isEmpty {
      loopToSubscribers.removeValue(forKey: loopID)
      if loopToSubscribers.isEmpty {
        registry.removeValue(forKey: key)
      }
      else {
        registry[key] = loopToSubscribers
      }
    }
    else {
      loopToSubscribers[loopID] = subscribers
      registry[key]             = loopToSubscribers
    }
  }
}

fileprivate extension ContiguousArray where Element == RedisCommandHandler {
  
  init(_ e: Element, capacity: Int) {
    self.init(repeating: e, count: 1)
    reserveCapacity(capacity)
  }
}
