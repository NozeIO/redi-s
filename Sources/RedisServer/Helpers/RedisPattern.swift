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

/**
 * A very incomplete implementation of the Pattern that can be used in the
 * `KEYS` command.
 *
 * This one only does:
 * - match all: `*`
 * - prefix, suffix, infix: `*str`, `str*`, `*str*`
 * - exact match: `str`
 */
enum RedisPattern : Hashable {
  
  case matchAll
  case prefix(Data)
  case suffix(Data)
  case infix(Data)
  case exact(Data)
  
  init?(_ s: ByteBuffer) {
    guard let p = RedisPattern.parse(s) else { return nil }
    self = p
  }
  
  func match(_ data: Data) -> Bool {
    switch self {
      case .matchAll:         return true
      case .exact (let match): return data == match
      case .prefix(let match): return data.hasPrefix(match)
      case .suffix(let match): return data.hasSuffix(match)
      case .infix (let match): return data.contains (match)
    }
  }
  
  #if swift(>=4.1)
  #else
    var hashValue: Int { // lolz
      switch self {
        case .matchAll:         return 1337
        case .exact (let match): return match.hashValue
        case .prefix(let match): return match.hashValue
        case .suffix(let match): return match.hashValue
        case .infix (let match): return match.hashValue
      }
    }
    
    static func ==(lhs: RedisPattern, rhs: RedisPattern) -> Bool {
      switch ( lhs, rhs ) {
        case ( .matchAll, .matchAll ): return true
        case ( .exact (let lhs), .exact (let rhs) ): return lhs == rhs
        case ( .prefix(let lhs), .prefix(let rhs) ): return lhs == rhs
        case ( .suffix(let lhs), .suffix(let rhs) ): return lhs == rhs
        case ( .infix (let lhs), .infix (let rhs) ): return lhs == rhs
        default: return false
      }
    }
  #endif

  private static func parse(_ s: ByteBuffer) -> RedisPattern? {
    return s.withUnsafeReadableBytes { bptr in
      let cStar      : UInt8 = 42 // *
      let cBackslash : UInt8 = 92 // \
      let cCaret     : UInt8 = 94 // ^
      let cQMark     : UInt8 = 63 // ?
      let cLBrack    : UInt8 = 91 // [
      
      if bptr.count == 0 { return .exact(Data()) }
      if bptr.count == 1 && bptr[0] == cStar { return .matchAll }
      
      var hasLeadingStar  = false
      var hasTrailingStar = false
      var i = 0
      let count = bptr.count
      
      while i < count {
        if bptr[i] == cBackslash { i += 2; continue }
        
        switch bptr[i] {
          case cCaret, cQMark, cLBrack: // no support for kewl stuff
            return nil
          
          case cStar:
            if      i == 0                { hasLeadingStar  = true }
            else if i == (bptr.count - 1) { hasTrailingStar = true }
            else                          { return nil }
          
          default: break
        }
        i += 1
      }
      
      switch ( hasLeadingStar, hasTrailingStar ) {
        case ( false, false ):
          return .exact(s.getData(at: s.readerIndex, length: count)!)
        
        case ( true, false ):
          return .suffix(s.getData(at: s.readerIndex + 1, length: count - 1)!)
        
        case ( false, true ):
          return .prefix(s.getData(at: s.readerIndex, length: count - 1)!)
        
        case ( true, true ):
          return .infix(s.getData(at: s.readerIndex + 1, length: count - 2)!)
      }
    }
  }

}

extension Data {
  
  var bytesStr : String {
    return self.map { String($0) }.joined(separator: " ")
  }
  
  func hasPrefix(_ other: Data) -> Bool {
    return starts(with: other)
  }
  
  func hasSuffix(_ other: Data) -> Bool {
    guard count >= other.count else { return false }
    return other.starts(with: suffix(other.count))
  }
  
  func contains(_ other: Data) -> Bool {
    return range(of: other) != nil
  }
  
}
