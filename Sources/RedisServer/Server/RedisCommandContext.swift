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

import NIO
import NIORedis
import struct Foundation.Data

/**
 * The environment commands need to run.
 */
public struct RedisCommandContext {
  
  let command   : RedisCommand
  let handler   : RedisCommandHandler
  let context   : ChannelHandlerContext
  let databases : Databases
  
  
  // MARK: - Convenience Accessors
  
  var database  : Databases.Database {
    return databases[handler.databaseIndex]
  }
  
  var eventLoop : EventLoop {
    return context.eventLoop
  }
  
  
  // MARK: - Database Synchronization
  
  func readInDatabase<T>(_ cb: ( Databases.Database ) throws -> T) throws -> T {
    let db = database

    do {
      let lock = databases.context.lock
      lock.lockForReading()
      defer { lock.unlock() }
      
      return try cb(db)
    }
    catch let error as RedisError { throw error }
    catch { fatalError("unexpected error: \(error)") }
  }
  func readInDatabase<T>(_ cb: ( Databases.Database ) -> T) -> T {
    let db = database
    
    let lock = databases.context.lock
    lock.lockForReading()
    defer { lock.unlock() }
    
    return cb(db)
  }

  func writeInDatabase<T>(_ cb: (Databases.Database) throws -> T) throws -> T {
    let db = database
    
    do {
      let lock = databases.context.lock
      lock.lockForWriting()
      defer { lock.unlock() }
      
      return try cb(db)
    }
    catch let error as RedisError { throw error }
    catch { fatalError("unexpected error: \(error)") }
  }
  
  func writeInDatabase<T>(_ cb: ( Databases.Database ) -> T) -> T {
    let db = database
    
    let lock = databases.context.lock
    lock.lockForWriting()
    defer { lock.unlock() }
    
    return cb(db)
  }

  func get(_ key: Data, _ cb: ( RedisValue? ) throws -> Void) {
    let db   = database
    let loop = eventLoop
    
    let value : RedisValue?
    
    do {
      let lock = databases.context.lock
      lock.lockForReading()
      defer { lock.unlock() }
      
      value = db[key]
    }
    
    assert(loop.inEventLoop)

    do { return try cb(value) }
    catch let error as RedisError { self.write(error) }
    catch { fatalError("unexpected error: \(error)") }
  }
  
  
  // MARK: - Write output
  
  @_specialize(where T == Int)
  @_specialize(where T == String)
  func write<T: RESPEncodable>(_ value: T, flush: Bool = true) {
    let context = self.context
    let handler = self.handler
    
    if eventLoop.inEventLoop {
      handler.write(context: context, value: value.toRESPValue(), promise: nil)
      if flush { context.channel.flush() }
    }
    else {
      eventLoop.execute {
        handler.write(context: context, value: value.toRESPValue(),
                      promise: nil)
        if flush { context.channel.flush() }
      }
    }
  }
  
  func write(_ value: RESPValue, flush: Bool = true) {
    let context = self.context
    let handler = self.handler
    
    if eventLoop.inEventLoop {
      handler.write(context: context, value: value, promise: nil)
      if flush { context.channel.flush() }
    }
    else {
      eventLoop.execute {
        handler.write(context: context, value: value, promise: nil)
        if flush { context.channel.flush() }
      }
    }
  }
}
