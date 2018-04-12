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

import NIORedis

enum RedisError : Swift.Error, RESPEncodable {
  
  case wrongType
  case noSuchKey
  case indexOutOfRange
  case notAnInteger
  case unknownSubcommand
  case syntaxError
  case dbIndexOutOfRange
  case invalidDBIndex
  case wrongNumberOfArguments(command: String?)
  case expectedKey
  case internalServerError
  case patternNotImplemented(String?)
  
  var code : String {
    switch self {
      case .wrongType:             return "WRONGTYPE"
      case .expectedKey:           return "Protocol error"
      case .internalServerError,
           .patternNotImplemented: return "500"
      default:                     return "ERR"
    }
  }
  
  var reason : String {
    switch self {
      case .noSuchKey:           return "no such key"
      case .indexOutOfRange:     return "index out of range"
      case .syntaxError:         return "syntax error"
      case .dbIndexOutOfRange:   return "DB index is out of range"
      case .invalidDBIndex:      return "invalid DB index"
      case .expectedKey:         return "expected key."
      case .internalServerError: return "internal server error"
      
      case .patternNotImplemented(let s):
        return "pattern not implemented \(s ?? "-")"

      case .wrongType:
        return "Operation against a key holding the wrong kind of value"
      case .notAnInteger:
        return "value is not an integer or out of range"
      case .unknownSubcommand:
        return "Unknown subcommand or wrong number of arguments."
      
      case .wrongNumberOfArguments(let command):
        if let command = command {
          return "wrong number of arguments for: \(command.uppercased())"
        }
        else {
          return "wrong number of arguments"
        }
    }
  }
  
  func toRESPValue() -> RESPValue {
    return RESPValue(errorCode: code, message: reason)
  }
  
}
