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

public protocol RedisLogger {
  
  typealias LogLevel = RedisLogLevel

  func primaryLog(_ logLevel: LogLevel, _ msgfunc: () -> String,
                  _ values: [ Any? ] )
}

public extension RedisLogger {
  
  @inlinable
  func error(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Error, msg, values)
  }
  @inlinable
  func warn (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Warn, msg, values)
  }
  @inlinable
  func log  (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Log, msg, values)
  }
  @inlinable
  func info (_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Info, msg, values)
  }
  @inlinable
  func trace(_ msg: @autoclosure () -> String, _ values: Any?...) {
    primaryLog(.Trace, msg, values)
  }
}

public enum RedisLogLevel : Int8 {
  case Error
  case Warn
  case Log
  case Info
  case Trace
  
  var logStamp : String {
    switch self {
      case .Error: return "!"
      case .Warn:  return "#"
      case .Info:  return "-"
      case .Trace: return "."
      case .Log:   return "*"
    }
  }
  
  var logPrefix : String {
    switch self {
      case .Error: return "ERROR: "
      case .Warn:  return "WARN:  "
      case .Info:  return "INFO:  "
      case .Trace: return "Trace: "
      case .Log:   return ""
    }
  }
}


// MARK: - Simple Default Logger

import struct Foundation.Date
import class Foundation.DateFormatter

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Darwin
#else
  import Glibc
#endif

fileprivate let redisLogDateFmt : DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "dd MMM HH:mm:ss.SSS"
  return formatter
}()

private let pid = getpid()

public struct RedisPrintLogger : RedisLogger {
  
  public let logLevel : LogLevel
  
  @inlinable
  public init(logLevel: LogLevel = .Log) {
    self.logLevel = logLevel
  }
  
  public func primaryLog(_ logLevel : LogLevel,
                         _ msgfunc  : () -> String,
                         _ values   : [ Any? ] )
  {
    guard logLevel.rawValue <= self.logLevel.rawValue else { return }
    
    let now = Date()
    
    let prefix =
          "\(pid):M \(redisLogDateFmt.string(from: now)) \(logLevel.logStamp) "
    let s = msgfunc()
    
    if values.isEmpty {
      print("\(prefix)\(s)")
    }
    else {
      var ms = ""
      appendValues(values, to: &ms)
      print("\(prefix)\(s)\(ms)")
    }
  }
  
  func appendValues(_ values: [ Any? ], to ms: inout String) {
    for v in values {
      ms += " "
      
      if      let v = v as? CustomStringConvertible { ms += v.description }
      else if let v = v as? String                  { ms += v }
      else if let v = v                             { ms += "\(v)" }
      else                                          { ms += "<nil>" }
    }
  }
}
