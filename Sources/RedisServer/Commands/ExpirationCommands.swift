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

import Foundation
import NIORedis

extension Commands {
  
  static func TTL(key: Data, in ctx: CommandContext) throws {
    let inMilliseconds = ctx.command.name.hasPrefix("P")
    
    enum Result {
      case keyMissing // -2
      case noExpire   // -1
      case deadline(Date)
    }
    
    let result : Result = ctx.readInDatabase { db in
      guard db[key] != nil else { return .keyMissing }
      guard let deadline = db[expiration: key] else { return .noExpire }
      return .deadline(deadline)
    }
    
    switch result {
      case .deadline(let deadline):
        let now    = Date()
        let ttl    = deadline.timeIntervalSince(now)
        let result = ttl >= 0
                   ? (inMilliseconds ? Int(ttl * 1000.0) : Int(ttl))
                   : 0
        ctx.write(result)
      case .keyMissing: ctx.write(-2)
      case .noExpire:   ctx.write(-1)
    }
  }
  
  static func PERSIST(key: Data, in ctx: CommandContext) throws {
    let result : Bool = ctx.writeInDatabase { db in
      guard db.removeExpiration(forKey: key) != nil else { return false }
      return db[key] != nil
    }
    return ctx.write(result)
  }
  
  static func EXPIRE(key: Data, value: RESPValue,
                     in ctx: CommandContext) throws
  {
    guard let intValue = value.intValue else { throw RedisError.notAnInteger }
    
    let now      = Date()
    let deadline : Date
    
    switch ctx.command.name {
      case "EXPIRE":
        deadline = Date(timeIntervalSinceNow:  TimeInterval(intValue))
      case "PEXPIRE":
        deadline = Date(timeIntervalSinceNow:  TimeInterval(intValue) / 1000.0)
      
      case "EXPIREAT":
        deadline = Date(timeIntervalSince1970: TimeInterval(intValue))
      case "PEXPIREAT":
        deadline = Date(timeIntervalSince1970: TimeInterval(intValue) / 1000.0)
      
      default: fatalError("Internal inconsistency, unexpected cmd: \(ctx)")
    }
    
    let didDeadlinePass = deadline < now
    
    let didSet : Bool = ctx.writeInDatabase { db in
      if didDeadlinePass {
        return db.removeValue(forKey: key) != nil
      }
      if db[key] == nil {
        return false
      }

      db[expiration: key] = deadline
      return true
    }
    return ctx.write(didSet)
  }
}
