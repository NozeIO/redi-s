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

import NIO
import NIORedis
import struct Foundation.Data

public struct RedisCommand : RESPEncodable {
  
  public let name  : String
  public let type  : CommandType
  public let flags : Flags
  
  public struct Flags : OptionSet, RESPEncodable, CustomStringConvertible {
    
    public let rawValue : Int
    
    public init(rawValue: Int) { self.rawValue = rawValue }
    
    /// command may result in modifications
    public static let write    = Flags(rawValue: 1 << 0)
    
    /// command will never modify keys
    public static let readonly = Flags(rawValue: 1 << 1)
    
    /// reject command if currently OOM
    public static let denyoom  = Flags(rawValue: 1 << 2)
    
    /// server admin command
    public static let admin    = Flags(rawValue: 1 << 3)
    
    /// pubsub-related command
    public static let pubsub   = Flags(rawValue: 1 << 4)
    
    /// deny this command from scripts
    public static let noscript = Flags(rawValue: 1 << 5)
    
    /// command has random results, dangerous for scripts
    public static let random   = Flags(rawValue: 1 << 6)
    
    /// allow command while database is loading
    public static let loading  = Flags(rawValue: 1 << 7)
    
    /// allow command while replica has stale data
    public static let stale    = Flags(rawValue: 1 << 8)
    
    public static let fast     = Flags(rawValue: 1 << 9)

    public static let sortForScript = Flags(rawValue: 1 << 10)

    public var stringArray : [ String ] {
      var values = [ String ]()
      if contains(.write)         { values.append("write")           }
      if contains(.readonly)      { values.append("readonly")        }
      if contains(.denyoom)       { values.append("denyoom")         }
      if contains(.admin)         { values.append("admin")           }
      if contains(.pubsub)        { values.append("pubsub")          }
      if contains(.noscript)      { values.append("noscript")        }
      if contains(.random)        { values.append("random")          }
      if contains(.loading)       { values.append("loading")         }
      if contains(.stale)         { values.append("stale")           }
      if contains(.fast)          { values.append("fast")            }
      if contains(.sortForScript) { values.append("sort_for_script") }
      return values
    }
    public func toRESPValue() -> RESPValue {
      return stringArray.toRESPValue()
    }
    public var description : String {
      return "<Flags: " + stringArray.joined(separator: ",") + ">"
    }
  }
  
  public func toRESPValue() -> RESPValue {
    let keys = type.keys
    return [
      name.lowercased(),
      keys.arity,
      flags,
      keys.firstKey, keys.lastKey, keys.step
    ].toRESPValue()
  }
}


