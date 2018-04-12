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
  
  static func SCARD(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write(0) }
      guard case .set(let set) = value else { throw RedisError.wrongType }
      
      ctx.write(set.count)
    }
  }
  
  static func SMEMBERS(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write([]) }
      guard case .set(let set) = value else { throw RedisError.wrongType }
      
      ctx.eventLoop.execute {
        ctx.write(set.toRESPValue())
      }
    }
  }
  
  static func SISMEMBER(key: Data, member: Data,
                        in ctx: CommandContext) throws
  {
    ctx.get(key) { value in
      guard let value = value else { return ctx.write(false) }
      guard case .set(let set) = value else { throw RedisError.wrongType }
      
      ctx.write(set.contains(member))
    }
  }
  
  static func SADD(keys: ContiguousArray<Data>, in ctx: CommandContext) throws {
    guard let key = keys.first else { throw RedisError.syntaxError }
    let members = keys[1..<keys.count]
    
    let count = try ctx.writeInDatabase { db in
      return try db.sadd(key, members: members)
    }
    ctx.write(count)
  }
  
  static func SREM(keys: ContiguousArray<Data>, in ctx: CommandContext) throws {
    guard let key = keys.first else { throw RedisError.syntaxError }
    let members = keys[1..<keys.count]
    
    let count = try ctx.writeInDatabase { db in
      return try db.srem(key, members: members)
    }
    ctx.write(count)
  }

  static func setop(keys: ContiguousArray<Data>,
                    in ctx: CommandContext,
                    _ op: @escaping (inout Set<Data>, Set<Data>) -> Void) throws
  {
    guard !keys.isEmpty else { return ctx.write([]) }
    
    let baseKey = keys[0]
    
    let result = try ctx.writeInDatabase { db in
      return try db.setOp(baseKey, against: keys[1..<keys.count], op)
    }
    ctx.write(result.toRESPValue())
  }

  static func setopStore(keys: ContiguousArray<Data>,
                         in ctx: CommandContext,
                         _ op: @escaping (inout Set<Data>, Set<Data>) -> Void)
                throws
  {
    guard keys.count > 1 else { throw RedisError.syntaxError }
    
    let destination = keys[0]
    let baseKey     = keys[1]

    let count : Int
    let db = ctx.database
    
    do {
      let lock = ctx.databases.context.lock
      lock.lockForWriting()
      defer { lock.unlock() }
      
      let result = try db.setOp(baseKey, against: keys[2..<keys.count], op)
      db[destination] = .set(result)
      count = result.count
    }

    ctx.write(count)
  }
  
  static func SDIFF(keys: ContiguousArray<Data>, in ctx: CommandContext) throws
  {
    try setop(keys: keys, in: ctx) { $0.subtract($1) }
  }
  static func SDIFFSTORE(keys: ContiguousArray<Data>,
                         in ctx: CommandContext) throws
  {
    try setopStore(keys: keys, in: ctx) { $0.subtract($1) }
  }
  
  static func SINTER(keys: ContiguousArray<Data>, in ctx: CommandContext) throws
  {
    try setop(keys: keys, in: ctx) { $0.formIntersection($1) }
  }
  static func SINTERSTORE(keys: ContiguousArray<Data>,
                         in ctx: CommandContext) throws
  {
    try setopStore(keys: keys, in: ctx) { $0.formIntersection($1) }
  }
  
  static func SUNION(keys: ContiguousArray<Data>, in ctx: CommandContext) throws
  {
    try setop(keys: keys, in: ctx) { $0.formUnion($1) }
  }
  static func SUNIONSTORE(keys: ContiguousArray<Data>,
                          in ctx: CommandContext) throws
  {
    try setopStore(keys: keys, in: ctx) { $0.formUnion($1) }
  }
}
