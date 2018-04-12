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
import Foundation

/**
 * Redis commands are typed by number of arguments etc. Checkout the
 * documentation for the `COMMAND` command for all the details:
 *
 *   https://redis.io/commands/command
 *
 * CommandType represents the "reflection" information,
 * and adds the *implementation* of the command (in the form of a closure).
 *
 * (In a language w/ proper runtime information, you would just derive all that
 *  via reflection. In Swift we have to type it down).
 */
public enum CommandType {
  
  public typealias Context = RedisCommandContext
  
  // This ain't no beauty, but apart from hardcoding this seems to be the
  // best option? Recommendations are welcome!
  
  case noArguments    ( (                        Context ) throws -> Void )
  case optionalValue  ( ( RESPValue?,            Context ) throws -> Void )
  case singleValue    ( ( RESPValue,             Context ) throws -> Void )
  case valueValue     ( ( RESPValue, RESPValue,  Context ) throws -> Void )
  case oneOrMoreValues( ( ArraySlice<RESPValue>, Context ) throws -> Void )
  case key            ( ( Data,                  Context ) throws -> Void )
  case keyKey         ( ( Data, Data,            Context ) throws -> Void )
  case keyValue       ( ( Data, RESPValue,       Context ) throws -> Void )
  case keyValueValue  ( ( Data, RESPValue, RESPValue,
                                                 Context ) throws -> Void )
  case keyValueOptions( ( Data, RESPValue, ArraySlice<RESPValue>,
                                                 Context ) throws -> Void )
  case keyValues      ( ( Data, ArraySlice<RESPValue>,
                                                 Context ) throws -> Void )
  case keyRange       ( ( Data, Int, Int,        Context ) throws -> Void )
  case keyIndex       ( ( Data, Int,             Context ) throws -> Void )
  case keyIndexValue  ( ( Data, Int, RESPValue,  Context ) throws -> Void )
  case keys           ( ( ContiguousArray<Data>, Context ) throws -> Void )
  case keyValueMap    ( ( ContiguousArray< ( Data, RESPValue )>,
                                                 Context ) throws -> Void )

  public  struct ArgumentSpecification {
    
    enum Arity : RESPEncodable {
      case fix    (Int)
      case minimum(Int)
      
      func toRESPValue() -> RESPValue {
        switch self {
          case .fix    (let value): return .integer(value + 1)
          case .minimum(let value): return .integer(-(value + 1))
        }
      }
    }
    
    let arity    : Arity
    let firstKey : Int
    let lastKey  : Int
    let step     : Int
    
    init(arity: Arity,
         firstKey: Int = 0, lastKey: Int? = nil, step: Int? = nil)
    {
      self.arity    = arity
      self.firstKey = firstKey
      self.lastKey  = lastKey ?? firstKey
      self.step     = step ?? (firstKey != 0 ? 1 : 0)
    }
    
    init(argumentCount fixCount: Int) {
      self.init(arity: .fix(fixCount), firstKey: 1, lastKey: 1)
    }
    init(minimumArgumentCount fixCount: Int) {
      self.init(arity: .minimum(fixCount), firstKey: 1, lastKey: 1)
    }
  }
  
  /// Essentially the `Mirror` for the command type.
  var keys : ArgumentSpecification {
    switch self {
      case .noArguments:   return ArgumentSpecification(argumentCount: 0)
      case .key:           return ArgumentSpecification(argumentCount: 1)
      
      case .keyKey, .keyValue, .keyIndex:
        return ArgumentSpecification(argumentCount: 2)
      case .keyRange, .keyIndexValue, .keyValueValue:
        return ArgumentSpecification(argumentCount: 3)
      
      case .keyValues:
        return ArgumentSpecification(minimumArgumentCount: 2)

      case .optionalValue:   return ArgumentSpecification(arity: .minimum(0))
      case .singleValue:     return ArgumentSpecification(arity: .fix(1))
      case .valueValue:      return ArgumentSpecification(arity: .fix(2))
      case .oneOrMoreValues: return ArgumentSpecification(arity: .minimum(1))
      
      case .keys:
        return ArgumentSpecification(arity: .minimum(1),
                                     firstKey: 1, lastKey: -1)
      
      case .keyValueOptions:
        return ArgumentSpecification(minimumArgumentCount: 2)
      
      case .keyValueMap:
        return ArgumentSpecification(arity: .minimum(2),
                                     firstKey: 1, lastKey: -1, step: 2)
    }
  }
}
