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

import NIO
import NIORedis
import Foundation

/**
 * For an overview on Redis datatypes, check out:
 *
 *   [Data types](https://redis.io/topics/data-types)
 *
 * We try to stick to `ByteBuffer`, to avoid unnecessary copies. But for stuff
 * which needs to be Hashable, we can't :-)
 *
 * NOTE: Do not confuse RedisValue's with RESPValue's. RedisValues are the
 *       values the Redis database can store.
 *       RESPValues are the value types supported by the Redis-write protocol.
 *       Those are converted into each other, but are very much distinct!
 */
enum RedisValue {
  
  /// A binary safe string.
  case string(RedisString)
  
  /// A list of strings. For use w/ LPUSH, RPUSH, LRANGE etc.
  case list  (RedisList) // FIXME: oh no ;-)
  
  /// A set of strings. For use w/ SADD, SINTER, SPOP etc
  case set   (Set<Data>)
  
  /// A map between string fields and string values.
  /// Common commands: HMSET, HGETALL, HSET, HGETALL.
  case hash  ([ Data : RedisString ])
  
  /// Helper, do not use.
  case clear
}

#if false // TODO: Redis stores integers as actual integers (PERF)
  enum RedisString {
    case buffer (ByteBuffer)
    case integer(Int64)
  }
#else
  typealias RedisString = ByteBuffer
#endif

fileprivate let sharedAllocator = ByteBufferAllocator()

extension RedisValue : RESPEncodable {
  
  init?(_ value: RESPValue) {
    switch value {
      case .simpleString(let v):      self = .string(v)
      case .bulkString(.none):        return nil
      case .bulkString(.some(let v)): self = .string(v)
      case .integer, .array, .error:  return nil
    }
  }
  
  init(_ value: Int) { // FIXME: speed, and use .int backing store
    self = .string(ByteBuffer.makeFromIntAsString(value))
  }
  
  public var intValue : Int? { // FIXME: speed, and use .int backing store
    guard case .string(let bb) = self else { return nil }
    return bb.stringAsInteger
  }

  func toRESPValue() -> RESPValue {
    switch self {
      case .string(let v):     return .bulkString(v)
      case .list  (let items): return items.toRESPValue()
      case .set   (let items): return items.toRESPValue()
      case .hash  (let hash):  return hash.toRESPValue()
      case .clear: fatalError("use of .clear case")
    }
  }
  
}

extension RedisValue {
  
  init?(string value: RESPValue) {
    guard let bb = value.byteBuffer else { return nil }
    self = .string(bb)
  }
  
  init?(list value: RESPValue) {
    guard case .array(.some(let items)) = value else { return nil }
    self.init(list: items)
  }
  
  init?<T: Collection>(list value: T) where T.Element == RESPValue {
    var list = RedisList()
    #if swift(>=4.1)
      list.reserveCapacity(value.count)
    #else
      if let count = value.count as? Int {
        list.reserveCapacity(count)
      }
    #endif
    
    for item in value {
      guard let bb = item.byteBuffer else { return nil }
      list.append(bb)
    }
    self = .list(list)
  }

}


extension Dictionary where Element == ( key: Data, value: ByteBuffer ) {

  public func toRESPValue() -> RESPValue {
    var array = ContiguousArray<RESPValue>()
    array.reserveCapacity(count * 2 + 1)
    
    for ( key, value ) in self {
      array.append(RESPValue(bulkString: key))
      array.append(.bulkString(value))
    }
    
    return .array(array)
  }

}

extension Collection where Element == Data {
  
  public func toRESPValue() -> RESPValue {
    var array = ContiguousArray<RESPValue>()
    #if swift(>=4.1)
      array.reserveCapacity(count)
    #else
      if let count = count as? Int { array.reserveCapacity(count) }
    #endif
    
    for data in self {
      array.append(RESPValue(bulkString: data))
    }
    
    return .array(array)
  }
  
}
extension Collection where Element == ByteBuffer {
  
  public func toRESPValue() -> RESPValue {
    var array = ContiguousArray<RESPValue>()
    #if swift(>=4.1)
      array.reserveCapacity(count)
    #else
      if let count = count as? Int { array.reserveCapacity(count) }
    #endif
    
    for bb in self {
      array.append(.bulkString(bb))
    }
    
    return .array(array)
  }
  
}

extension Collection where Element == RESPValue {
  
  func extractByteBuffers(reverse: Bool = false)
         -> ContiguousArray<ByteBuffer>?
  {
    if reverse { return lazy.reversed().extractByteBuffers() }
    
    var byteBuffers = ContiguousArray<ByteBuffer>()
    #if swift(>=4.1)
      byteBuffers.reserveCapacity(count)
    #else
      if let count = count as? Int { byteBuffers.reserveCapacity(count) }
    #endif
    
    for item in self {
      guard let bb = item.byteBuffer else { return nil }
      byteBuffers.append(bb)
    }
    return byteBuffers
  }
  
  func extractRedisList(reverse: Bool = false) -> RedisList? {
    if reverse { return lazy.reversed().extractRedisList() }
    
    var byteBuffers = RedisList()
    #if swift(>=4.1)
      byteBuffers.reserveCapacity(count)
    #else
      if let count = count as? Int { byteBuffers.reserveCapacity(count) }
    #endif
    
    for item in self {
      guard let bb = item.byteBuffer else { return nil }
      byteBuffers.append(bb)
    }
    return byteBuffers
  }
}


extension ByteBuffer {
  
  static func makeFromIntAsString(_ value: Int) -> ByteBuffer {
    return ByteBuffer(string: String(value))
  }
  var stringAsInteger: Int? {
    guard readableBytes > 0 else { return nil }
    
    // FIXME: faster parsing (though the backing store should be int)
    guard let s = getString(at: readerIndex, length: readableBytes) else {
      return nil
    }
    return Int(s)
  }
  
  func rangeForRedisRange(start: Int, stop: Int) -> Range<Int> {
    let count = self.readableBytes
    if count == 0 { return 0..<0 }
    
    var fromIndex = start < 0 ? (count + start) : start
    if fromIndex >= count { return 0..<0  }
    else if fromIndex < 0 { fromIndex = 0 }
    
    var toIndex = stop < 0 ? (count + stop) : stop
    if toIndex >= count { toIndex = count - 1 }
    
    if fromIndex > toIndex { return 0..<0 }
    
    toIndex += 1
    return fromIndex..<toIndex
  }
  
}

extension Collection { // TBD: where IndexDistance is Int?
  
  func rangeForRedisRange(start: Int, stop: Int) -> Range<Int> {
    #if swift(>=4.1)
      let count = self.count
    #else
      let count = self.count as! Int
    #endif
    if count == 0 { return 0..<0 }
    
    var fromIndex = start < 0 ? (count + start) : start
    if fromIndex >= count { return 0..<0  }
    else if fromIndex < 0 { fromIndex = 0 }
    
    var toIndex = stop < 0 ? (count + stop) : stop
    if toIndex >= count { toIndex = count - 1 }
    
    if fromIndex > toIndex { return 0..<0 }
    
    toIndex += 1
    return fromIndex..<toIndex
  }
  
}

extension RESPValue {
  static let ok = RESPValue(simpleString: "OK")
}
