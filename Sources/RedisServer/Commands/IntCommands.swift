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
import enum   NIORedis.RESPValue

extension Commands {
  
  static func workOnInt(_ key: Data, in ctx: CommandContext,
                        _ op: ( Int ) -> Int) throws
  {
    let result = try ctx.writeInDatabase { db in
      return try db.intOp(key, op)
    }
    ctx.write(result)
  }
  
  static func INCR(key: Data, in ctx: CommandContext) throws {
    try workOnInt(key, in: ctx) { $0 + 1 }
  }
  static func DECR(key: Data, in ctx: CommandContext) throws {
    try workOnInt(key, in: ctx) { $0 - 1 }
  }
  
  static func INCRBY(key: Data, value: RESPValue,
                     in ctx: CommandContext) throws
  {
    guard let intValue = value.intValue else { throw RedisError.notAnInteger }
    try workOnInt(key, in: ctx) { $0 + intValue }
  }
  static func DECRBY(key: Data, value: RESPValue,
                     in ctx: CommandContext) throws
  {
    guard let intValue = value.intValue else { throw RedisError.notAnInteger }
    try workOnInt(key, in: ctx) { $0 - intValue }
  }

}
