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

import enum   NIORedis.RESPValue
import struct NIORedis.RESPError
import struct NIO.ByteBuffer
import struct Foundation.Data

fileprivate enum TypeValues {
  static let none   = RESPValue(simpleString: "none")
  static let string = RESPValue(simpleString: "string")
  static let list   = RESPValue(simpleString: "list")
  static let set    = RESPValue(simpleString: "set")
  static let hash   = RESPValue(simpleString: "hash")
}


extension Commands {
  
  static func KEYS(pattern v: RESPValue, in ctx: CommandContext) throws {
    var bb : ByteBuffer
    switch v {
      case .simpleString(let cs), .bulkString(.some(let cs)): bb = cs
      default: throw RedisError.syntaxError
    }
    
    guard let pattern = RedisPattern(bb) else {
      let s = bb.readString(length: bb.readableBytes)
      throw RedisError.patternNotImplemented(s)
    }
    
    let keys = ctx.readInDatabase { db in db.keys }
    
    if case .matchAll = pattern {
      let values = ContiguousArray<RESPValue>(
                      keys.lazy.map { RESPValue(bulkString: $0) })
      return ctx.write(.array(values))
    }
    
    var values = ContiguousArray<RESPValue>()
    for key in keys {
      guard pattern.match(key) else { continue }
      values.append(RESPValue(bulkString: key))
    }
    
    ctx.write(.array(values))
  }

  static func DBSIZE(_ ctx: CommandContext) throws {
    ctx.write(ctx.readInDatabase { db in db.count })
  }
  
  static func TYPE(key: Data, in ctx: CommandContext) throws {
    ctx.get(key) { value in
      ctx.eventLoop.execute {
        guard let value = value else { return ctx.write(TypeValues.none) }
        
        switch value {
          case .string: ctx.write(TypeValues.string)
          case .list:   ctx.write(TypeValues.list)
          case .set:    ctx.write(TypeValues.set)
          case .hash:   ctx.write(TypeValues.hash)
          case .clear:  fatalError("use of .clear case")
        }
      }
    }
  }

  static func DEL(keys: ContiguousArray<Data>, in ctx: CommandContext) throws {
    ctx.writeInDatabase { db in
      
      var count = 0
      for key in keys {
        if db.removeValue(forKey: key) != nil {
          count += 1
        }
      }
      
      ctx.write(count)
    }
  }

  static func RENAME(oldKey: Data, newKey: Data,
                     in ctx: CommandContext) throws
  {
    let isSame = oldKey == newKey
    
    try ctx.writeInDatabase { db in
      if isSame {
        guard db[oldKey] != nil else { throw RedisError.noSuchKey }
      }
      else {
        if !db.renameKey(oldKey, to: newKey) { throw RedisError.noSuchKey }
      }
    }
    
    ctx.write(RESPValue.ok)
  }

  static func RENAMENX(oldKey: Data, newKey: Data,
                       in ctx: CommandContext) throws
  {
    let isSame = oldKey == newKey
    
    let didExist : Bool = try ctx.writeInDatabase { db in
      if isSame {
        guard db[oldKey] != nil else { throw RedisError.noSuchKey }
        return true
      }
      
      if db[newKey] != nil {
        return true
      }

      if !db.renameKey(oldKey, to: newKey) { throw RedisError.noSuchKey }
      return false
    }
    ctx.write(didExist ? 0 : 1)
  }

  static func EXISTS(keys: ContiguousArray<Data>,
                     in ctx: CommandContext) throws
  {
    let count : Int = ctx.readInDatabase { db in
      var count = 0
      for key in keys {
        if db[key] != nil { count += 1 }
      }
      return count
    }
    ctx.write(count)
  }
}
