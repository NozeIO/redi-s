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

import struct NIO.ByteBuffer
import enum   NIORedis.RESPValue

typealias RedisList = ContiguousArray<RedisString>

/// Amount of additional storage to alloc when pushing elements
fileprivate let RedisExtraListCapacity = 128

fileprivate extension ContiguousArray {
  
  @inline(__always)
  mutating func redisReserveExtraCapacity(_ newCount: Int) {
    if capacity >= (count + newCount) { return }
    
    let reserveCount : Int
    switch count + newCount { // rather arbitrary
      case 0...100:      reserveCount = 128
      case 101...1000:   reserveCount = 2048
      case 1001...16384: reserveCount = 16384
      default:
        #if true // this keeps the performance from degrading
          reserveCount = (count + newCount) * 2
        #else
          reserveCount = count + newCount + 2048
        #endif
    }
    reserveCapacity(reserveCount)
  }

}
fileprivate extension Array {
  
  @inline(__always)
  mutating func redisReserveExtraCapacity(_ newCount: Int) {
    if capacity >= (count + newCount) { return }
    reserveCapacity(count + newCount + RedisExtraListCapacity)
  }
  
}


extension RedisValue {
  // this is of course all non-sense, it should be a proper list
  
  mutating func lset(_ value: ByteBuffer, at idx: Int) -> Bool {
    guard case .list(var list) = self else { return false }
    
    self = .clear
    list[idx] = value
    self = .list(list)
    return true
  }
  
  mutating func lpop() -> ByteBuffer? {
    guard case .list(var list) = self else { return nil }
    guard !list.isEmpty               else { return nil }
    
    self = .clear
    let bb = list.remove(at: 0)
    self = .list(list)
    return bb
  }
  mutating func rpop() -> ByteBuffer? {
    guard case .list(var list) = self else { return nil }
    self = .clear
    let bb = list.popLast()
    self = .list(list)
    return bb
  }

  @discardableResult
  mutating func rpush(_ value: ByteBuffer) -> Int? {
    guard case .list(var list) = self else { return nil }
    self = .clear
    list.redisReserveExtraCapacity(1)
    list.append(value)
    self = .list(list)
    return list.count
  }
  
  @discardableResult
  mutating func rpush<T: Collection>(_ items: T) -> Int?
                where T.Element == ByteBuffer
  {
    guard case .list(var list) = self else { return nil }
    self = .clear
    
    #if swift(>=4.1)
      let newCount = items.count
    #else
      let newCount = (items.count as? Int) ?? 1
    #endif
    list.redisReserveExtraCapacity(newCount)

    list.append(contentsOf: items)
    self = .list(list)
    return list.count
  }
  
  @discardableResult
  mutating func rpush(_ items: RedisList) -> Int? {
    guard case .list(var list) = self else { return nil }
    self = .clear
    
    let newCount = items.count
    list.redisReserveExtraCapacity(newCount)
    
    list.append(contentsOf: items)
    self = .list(list)
    return list.count
  }
  
  @discardableResult
  mutating func lpush(_ value: ByteBuffer) -> Int? {
    guard case .list(var list) = self else { return nil }
    self = .clear
    list.redisReserveExtraCapacity(1)
    list.insert(value, at: 0)
    self = .list(list)
    return list.count
  }

  @discardableResult
  mutating func lpush(_ reversedItems: RedisList) -> Int? {
    guard case .list(let list) = self else { return nil }
    self = .clear
    var newList = RedisList()
    newList.reserveCapacity(reversedItems.count + list.count)
    newList.append(contentsOf: reversedItems)
    newList.append(contentsOf: list)
    self = .list(newList)
    return newList.count
  }

}
