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

import struct Foundation.Date
import struct Foundation.Data
import struct Foundation.TimeInterval
import NIORedis
import NIO

extension Commands {
  
  static func APPEND(_ key: Data, _ value: RESPValue, in ctx: CommandContext)
                throws
  {
    guard var bb = value.byteBuffer else { throw RedisError.wrongType }
    
    let result : Int = try ctx.writeInDatabase { ( db : Databases.Database ) in
      if let oldValue : RedisValue = db[key] {
        guard case .string(var s) = oldValue else { throw RedisError.wrongType }
        s.writeBuffer(&bb)
        db[key] = .string(s)
        return s.readableBytes
      }
      else {
        db[key] = .string(bb)
        return bb.readableBytes
      }
      
    }
    ctx.write(result)
  }
  
  fileprivate enum KeyOverrideBehaviour {
    case always
    case ifMissing
    case ifExisting
  }
  fileprivate enum SetReturnStyle {
    case ok
    case bool
  }
  
  @inline(__always)
  fileprivate
  static func set(_ key       : Data,
                  _ value     : RESPValue,
                  keyOverride : KeyOverrideBehaviour = .always,
                  expiration  : TimeInterval? = nil,
                  result      : SetReturnStyle,
                  in ctx      : CommandContext) throws
  {
    guard let redisValue = RedisValue(string: value) else {
      throw RedisError.wrongType
    }

    let db = ctx.database
    
    let doSet : Bool
    do {
      let lock = ctx.databases.context.lock
      lock.lockForWriting()
      defer { lock.unlock() }
      
      switch keyOverride {
        case .always:     doSet = true
        case .ifMissing:  doSet = db[key] == nil // NX
        case .ifExisting: doSet = db[key] != nil // XX
      }
      
      if doSet {
        db[key] = redisValue
        
        if let expiration = expiration {
          db[expiration: key] = Date(timeIntervalSinceNow: expiration)
        }
        else { // YES, SET removes the expiration!
          _ = db.removeExpiration(forKey: key)
        }
      }
    }
    
    if result == .ok {
      ctx.write(doSet ? RESPValue.ok : RESPValue.init(bulkString: nil))
    }
    else {
      ctx.write(doSet)
    }
  }
  
  static func SET(_ key: Data, _ value: RESPValue,
                  _ opts: ArraySlice<RESPValue>, in ctx: CommandContext)
                throws
  {
    // [EX seconds] [PX milliseconds] [NX|XX]
    var keyOverride : KeyOverrideBehaviour? = nil
    var expiration  : TimeInterval? = nil
    
    // Report: slice fails on indexing (4.0)
    // TODO => wrong. We just need to use proper indices (start at `startIndex`
    //                and then advance)
    let opts  = ContiguousArray(opts)
    var i     = opts.startIndex
    let count = opts.count
    while i < count {
      guard let s = opts[i].stringValue, !s.isEmpty else {
        throw RedisError.syntaxError
      }
      
      switch s {
        case "EX", "PX":
          guard expiration == nil, (i + 1 < count),
                let v = opts[i + 1].intValue
           else {
            throw RedisError.syntaxError
           }
          if s == "PX" { expiration = TimeInterval(v) / 1000.0 }
          else         { expiration = TimeInterval(v) }
          i += 1
        
        case "NX", "XX":
          guard keyOverride == nil else { throw RedisError.syntaxError }
          keyOverride = s == "NX" ? .ifMissing : .ifExisting
        
        default: throw RedisError.syntaxError
      }
      
      i += 1
    }
    
    try set(key, value,
            keyOverride: keyOverride ?? .always,
            expiration: expiration, result: .ok,
            in: ctx)
  }
  
  static func SETNX(_ key: Data, _ value: RESPValue,
                    in ctx: CommandContext) throws
  {
    try set(key, value, keyOverride: .ifMissing, result: .bool, in: ctx)
  }
  
  static func SETEX(_ key: Data, _ seconds: RESPValue, _ value: RESPValue,
                    in ctx: CommandContext) throws
  {
    let inMilliseconds = ctx.command.name.hasPrefix("P")
    guard let v = seconds.intValue else { throw RedisError.notAnInteger }
    
    let timeout = inMilliseconds ? (TimeInterval(v) / 1000.0) : TimeInterval(v)
    try set(key, value, expiration: timeout, result: .ok, in: ctx)
  }
  
  
  static func MSET(pairs: ContiguousArray< ( Data, RESPValue )>,
                   in ctx: CommandContext)
                throws
  {
    let redisPairs = try pairs.lazy.map {
      ( pair : ( Data, RESPValue ) ) -> ( Data, RedisValue ) in
      
      guard let redisValue = RedisValue(string: pair.1) else {
        throw RedisError.wrongType
      }
      return ( pair.0, redisValue )
    }
    
    ctx.writeInDatabase { db in
      for ( key, value ) in redisPairs {
        db[key] = value
      }
      
      ctx.write(RESPValue.ok)
    }
  }
  
  static func MSETNX(pairs: ContiguousArray< ( Data, RESPValue )>,
                     in ctx: CommandContext)
                throws
  {
    let redisPairs = try pairs.lazy.map {
      ( pair : ( Data, RESPValue ) ) -> ( Data, RedisValue ) in
      
      guard let redisValue = RedisValue(string: pair.1) else {
        throw RedisError.wrongType
      }
      return ( pair.0, redisValue )
    }
    
    let result : Bool = ctx.writeInDatabase { db in
      for ( key, _ ) in redisPairs {
        if db[key] != nil { return false }
      }
      
      for ( key, value ) in redisPairs {
        db[key] = value
      }
      
      return true
    }
    ctx.write(result)
  }
  
  static func GETSET(_ key: Data, _ value: RESPValue, in ctx: CommandContext)
                throws
  {
    guard let redisValue = RedisValue(string: value) else {
      throw RedisError.wrongType
    }
    
    ctx.writeInDatabase { db in
      
      let value = db[key]
      db[key] = redisValue
      db[expiration: key] = nil
      
      ctx.eventLoop.execute {
        guard let value = value else { return ctx.write(.bulkString(nil)) }
        ctx.write(value)
      }
    }
  }
  
  static func SETRANGE(key: Data, index: Int, value: RESPValue,
                       in ctx: CommandContext) throws
  {
    guard index >= 0                else { throw RedisError.indexOutOfRange }
    guard var bb = value.byteBuffer else { throw RedisError.wrongType }

    let result : Int = try ctx.writeInDatabase { db in
      var s : ByteBuffer
      
      if let value = db[key] {
        guard case .string(let olds) = value else {
          throw RedisError.wrongType
        }
        s = olds
      }
      else {
        let size  = index + bb.readableBytes + 1
        let alloc = ByteBufferAllocator()
        s = alloc.buffer(capacity: size)
      }
      
      if index > s.readableBytes { // if index > count, 0-padded!!!
        let countToWrite = index - s.readableBytes
        s.writeRepeatingByte(0, count: countToWrite)
      }
      
      s.moveWriterIndex(to: s.readerIndex + index)
      s.writeBuffer(&bb)
      
      db[key] = .string(s)
      return s.readableBytes
    }
    
    ctx.write(result)
  }
  
  
  // MARK: - Read Commands

  static func GET(_ key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value       else { return ctx.write(.bulkString(nil)) }
      guard case .string(_) = value else { throw RedisError.wrongType }
      ctx.write(value)
    }
  }
  
  static func STRLEN(_ key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value           else { return ctx.write(0) }
      guard case .string(let s) = value else { throw RedisError.wrongType }
      ctx.write(s.readableBytes)
    }
  }
  
  static func GETRANGE(key: Data, start: Int, stop: Int,
                       in ctx: CommandContext) throws
  {
    ctx.get(key) { value in
      guard let value = value           else { return ctx.write("") }
      guard case .string(let s) = value else { throw RedisError.wrongType }
      
      let count = s.readableBytes
      if count == 0 { return ctx.write("") }
      
      let range = s.rangeForRedisRange(start: start, stop: stop)
      if range.isEmpty { return ctx.write("") }
      
      let from  = s.readerIndex + range.lowerBound
      guard let slice = s.getSlice(at: from, length: range.count) else {
        throw RedisError.indexOutOfRange
      }
      
      ctx.write(slice)
    }
  }

  static func MGET(keys: ContiguousArray<Data>, in ctx: CommandContext) throws {
    let count = keys.count
    if count == 0 { return ctx.write([]) }
    
    let values : ContiguousArray<RESPValue> = ctx.readInDatabase { db in
      
      var values = ContiguousArray<RESPValue>()
      values.reserveCapacity(count)
      
      for key in keys {
        if let value = db[key] {
          if case .string(let s) = value { values.append(.bulkString(s))   }
          else                           { values.append(.bulkString(nil)) }
        }
        else {
          values.append(.bulkString(nil))
        }
      }
      return values
    }
    
    ctx.write(.array(values))
  }
}
