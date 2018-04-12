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

import struct NIO.ByteBuffer
import enum   NIORedis.RESPValue
import struct Foundation.Data

extension Commands {
  
  static func HLEN(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write(0) }
      guard case .hash(let hash) = value else { throw RedisError.wrongType }
      ctx.write(hash.count)
    }
  }
  
  static func HGETALL(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value  else { return ctx.write([]) }
      guard case .hash = value else { throw RedisError.wrongType }
      ctx.write(value)
    }
  }
  
  static func HSTRLEN(key: Data, field: RESPValue,
                      in ctx: CommandContext) throws
  {
    guard let fieldKey = field.keyValue else { throw RedisError.syntaxError }
    
    ctx.get(key) { value in
      guard let value = value               else { return ctx.write(0) }
      guard case .hash(let hash) = value    else { throw RedisError.wrongType }
      guard let fieldValue = hash[fieldKey] else { return ctx.write(0) }
      ctx.write(fieldValue.readableBytes)
    }
  }

  static func HGET(key: Data, field: RESPValue, in ctx: CommandContext) throws {
    guard let fieldKey = field.keyValue else { throw RedisError.syntaxError }
    
    ctx.get(key) { value in
      guard let value = value else { return ctx.write(.bulkString(nil)) }
      guard case .hash(let hash) = value else { throw RedisError.wrongType }
      ctx.write(.bulkString(hash[fieldKey]))
    }
  }

  static func HEXISTS(key: Data, field: RESPValue,
                      in ctx: CommandContext) throws
  {
    guard let fieldKey = field.keyValue else { throw RedisError.syntaxError }
    
    ctx.get(key) { value in
      guard let value = value else { return ctx.write(false) }
      guard case .hash(let hash) = value else { throw RedisError.wrongType }
      ctx.write(hash[fieldKey] != nil)
    }
  }
  
  static func HKEYS(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write([]) }
      guard case .hash(let hash) = value else { throw RedisError.wrongType }
      
      ctx.eventLoop.execute {
        let keys = hash.keys.lazy.map { RESPValue(bulkString: $0) }
        ctx.write(.array(ContiguousArray(keys)))
      }
    }
  }
  
  static func HVALS(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write([]) }
      guard case .hash(let hash) = value else { throw RedisError.wrongType }
      
      ctx.eventLoop.execute {
        let vals = hash.values.lazy.map { RESPValue.bulkString($0) }
        ctx.write(.array(ContiguousArray(vals)))
      }
    }
  }
  
  static func HSET(key: Data, field: RESPValue, value: RESPValue,
                   in ctx: CommandContext) throws
  {
    guard let fieldKey = field.keyValue else { throw RedisError.syntaxError }
    guard let bb = value.byteBuffer     else { throw RedisError.syntaxError }
    let isNX = ctx.command.name == "HSETNX"
    
    let isNew : Bool = try ctx.writeInDatabase { db in
      let isNew : Bool
      
      if let oldValue = db[key] {
        guard case .hash(var hash) = oldValue else {
          throw RedisError.wrongType
        }
        
        isNew = hash[fieldKey] == nil
        if isNew || !isNX {
          hash[fieldKey] = bb
          db[key] = .hash(hash)
        }
      }
      else {
        db[key] = .hash([fieldKey: bb])
        isNew = true
      }
      return isNew
    }
    
    ctx.write(isNew)
  }
  
  static func HINCRBY(key: Data, field: RESPValue, value: RESPValue,
                      in ctx: CommandContext) throws
  {
    guard let fieldKey = field.keyValue else { throw RedisError.syntaxError }
    guard let intValue = value.intValue else { throw RedisError.notAnInteger }
    
    let result : Int = try ctx.writeInDatabase { db in
      
      let result : Int
      
      if let oldValue = db[key] {
        guard case .hash(var hash) = oldValue else {
          throw RedisError.wrongType
        }
        
        if let bb = hash[fieldKey] {
          guard let oldInt = bb.stringAsInteger else {
            throw RedisError.notAnInteger
          }
          result = oldInt + intValue
        }
        else {
          result = 0 + intValue
        }
        
        hash[fieldKey] = ByteBuffer.makeFromIntAsString(result)
        db[key] = .hash(hash)
      }
      else {
        result = 0 + intValue
        db[key] = .hash([fieldKey: ByteBuffer.makeFromIntAsString(result)])
      }
      
      return result
    }
    
    ctx.write(result)
  }

  static func HMSET(key: Data, values: ArraySlice<RESPValue>,
                    in ctx: CommandContext) throws
  {
    guard values.count % 2 == 0 else {
      throw RedisError.wrongNumberOfArguments(command: "HMSET")
    }
    
    let newValues = try values.convertToRedisHash()
    
    try ctx.writeInDatabase { db in
      if let oldValue = db[key] {
        guard case .hash(var oldDict) = oldValue else {
          throw RedisError.wrongType
        }
        
        oldDict.merge(newValues) { $1 }
        db[key] = .hash(oldDict)
      }
      else {
        db[key] = .hash(newValues)
      }
      
    }
    
    ctx.write(RESPValue.ok)
  }
  
  static func HDEL(key: Data, fields: ArraySlice<RESPValue>,
                    in ctx: CommandContext) throws
  {
    guard !fields.isEmpty else { return ctx.write([]) }
    
    let keys : [ Data ] = try fields.lazy.map {
      guard let key = $0.keyValue else {
        throw RedisError.syntaxError
      }
      return key
    }
    
    let delCount : Int = try ctx.writeInDatabase { db in
      guard let value = db[key] else { return 0 }
      guard case .hash(var hash) = value else { throw RedisError.wrongType }

      var delCount = 0
      
      for field in keys {
        if hash.removeValue(forKey: field) != nil {
          delCount += 1
        }
      }
      if delCount > 0 {
        db[key] = .hash(hash)
      }
      return delCount
    }
    
    ctx.write(delCount)
  }
  
  static func HMGET(key: Data, fields: ArraySlice<RESPValue>,
                    in ctx: CommandContext) throws
  {
    guard !fields.isEmpty else { return ctx.write([]) }
    
    let keys : [ Data ] = try fields.lazy.map {
      guard let key = $0.keyValue else {
        throw RedisError.syntaxError
      }
      return key
    }
    
    ctx.get(key) { value in
      let nilValue = RESPValue.bulkString(nil)
      guard let value = value else {
        return ctx.write(Array(repeating: nilValue, count: keys.count))
      }
      
      guard case .hash(let hash) = value else {
        return ctx.write(RedisError.wrongType)
      }
      
      ctx.eventLoop.execute {
        var results = ContiguousArray<RESPValue>()
        results.reserveCapacity(keys.count)
        for key in keys {
          results.append(RESPValue.bulkString(hash[key]))
        }
        ctx.write(RESPValue.array(results))
      }
    }
  }

}

extension ArraySlice where Element == RESPValue {
  // ArraySlice to please Swift 4.0, which has IndexDistance
  
  func convertToRedisHash() throws -> Dictionary<Data, ByteBuffer> {
    guard count % 2 == 0 else {
      throw RedisError.wrongNumberOfArguments(command: nil)
    }
    
    let pairCount = count / 2
    var dict = Dictionary<Data, ByteBuffer>(minimumCapacity: pairCount + 1)
    
    var i = startIndex
    while i < endIndex {
      guard let key = self[i].keyValue else {
        throw RedisError.syntaxError
      }
      i = i.advanced(by: 1)
      
      let value = self[i]
      i = i.advanced(by: 1)
      
      switch value {
        case .bulkString(.some(let cs)), .simpleString(let cs):
          dict[key] = cs
        default:
          throw RedisError.syntaxError
      }
    }
    return dict
  }
  
}
