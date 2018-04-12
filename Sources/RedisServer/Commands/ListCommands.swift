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

import struct Foundation.Data
import struct NIO.ByteBuffer
import NIORedis

extension Commands {
  
  static func LLEN(key: Data, in ctx: CommandContext) throws {
    let count = try ctx.readInDatabase { db in try db.listCount(key: key) }
    ctx.write(count)
  }
  
  static func LINDEX(key: Data, index: Int, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write(.bulkString(nil)) }
      guard case .list(let list) = value else { throw RedisError.wrongType }
      
      let count = list.count
      if count == 0 { return ctx.write(.bulkString(nil)) }

      let cindex = index < 0 ? (count + index) : index
      if cindex < 0 || cindex >= count { return ctx.write(.bulkString(nil)) }
      
      ctx.write(list[cindex])
    }
  }

  static func LRANGE(key: Data, start: Int, stop: Int, in ctx: CommandContext)
                throws
  {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write([]) }
      guard case .list(let list) = value else { throw RedisError.wrongType }
      
      let count = list.count
      if count == 0 { return ctx.write([]) }
      
      let range = list.rangeForRedisRange(start: start, stop: stop)
      
      ctx.write(list[range].toRESPValue())
    }
  }
  
  static func LSET(key: Data, index: Int, value: RESPValue,
                   in ctx: CommandContext) throws
  {
    guard let bb = value.byteBuffer else { throw RedisError.wrongType }
    
    try ctx.writeInDatabase { db in
      try db.lset(key: key, index: index, value: bb)
    }
    ctx.write(RESPValue.ok)
  }

  @inline(__always)
  static func pop(key: Data, left : Bool, in ctx: CommandContext) throws {
    let v = try ctx.writeInDatabase { db in
      return try db.listPop(key: key, left: left)
    }
    ctx.write(.bulkString(v))
  }
  
  @_specialize(where T == ArraySlice<RESPValue>)
  @inline(__always)
  static func push<T: Collection>(key  : Data, values: T,
                                  left : Bool, createIfMissing : Bool = true,
                                  in ctx: CommandContext) throws
                where T.Element == RESPValue
  {
    let valueCount : Int
    #if swift(>=4.1)
      valueCount = values.count
    #else
      if let c = values.count as? Int { valueCount = c }
      else { fatalError("non-int count") }
    #endif
    
    if valueCount == 0 {
      let result = try ctx.writeInDatabase { db in try db.listCount(key: key) }
      return ctx.write(result)
    }
    else if valueCount == 1 {
      switch values[values.startIndex] {
        case .simpleString(let bb), .bulkString(.some(let bb)):
          let count = try ctx.writeInDatabase { db in
            return try db.listPush(key: key, value: bb, left: left,
                                   createIfMissing: createIfMissing)
          }
          return ctx.write(count)
        default: throw RedisError.wrongType
      }
    }

    guard let byteBuffers = values.extractRedisList(reverse: left) else {
      throw RedisError.wrongType
    }
    
    let count = try ctx.writeInDatabase { db in
      try db.listPush(key: key, values: byteBuffers, left: left,
                      createIfMissing: createIfMissing)
    }
    ctx.write(count)
  }
  
  static func RPOP(key: Data, in ctx: CommandContext) throws {
    try pop(key: key, left: false, in: ctx)
  }
  static func LPOP(key: Data, in ctx: CommandContext) throws {
    try pop(key: key, left: true, in: ctx)
  }

  static func RPUSH(key: Data, values: ArraySlice<RESPValue>,
                    in ctx: CommandContext) throws
  {
    try push(key: key, values: values, left: false, in: ctx)
  }
  static func LPUSH(key: Data, values: ArraySlice<RESPValue>,
                    in ctx: CommandContext) throws
  {
    try push(key: key, values: values, left: true, in: ctx)
  }

  static func RPUSHX(key: Data, value: RESPValue,
                     in ctx: CommandContext) throws
  {
    try push(key: key, values: [ value ],
             left: false, createIfMissing: false, in: ctx)
  }
  static func LPUSHX(key: Data, value: RESPValue,
                     in ctx: CommandContext) throws
  {
    try push(key: key, values: [ value ],
             left: true, createIfMissing: false, in: ctx)
  }
}
