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

import Dispatch
import Foundation
import NIORedis
import struct NIO.ByteBuffer

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Darwin
#else
  import Glibc
#endif

/**
 * A set of Redis Databases.
 *
 * A Redis database is just a key/value pair, where the key is a binary safe
 * "string" (aka a `Data` object).
 * In this naive implementation, access to the database is serialized using a
 * GCD queue.
 *
 * ## Indexed Databases
 *
 * Redis maintains a set of databases (dictionaries) which are referred to by
 * index.
 * Other databases can be selected using the SELECT command, and a connection
 * has one active database. New connections always use the database at index 0.
 *
 * One can use the SWAPDB command to switch the DB of connections.
 *
 * ## Notes
 *
 * - There seems to be no performance difference between using GCD `async` or
 *   an NIO.EventLoop thread via `execute`.
 * - It would be nice to keep using ByteBuffer's, but we need `Data` for the
 *   Hashable etc.
 */
final class Databases : Codable {
  
  typealias SavePoints = ContiguousArray<SavePoint>
  typealias SavePoint  = RedisServer.Configuration.SavePoint
  
  final class Context {
    
    final fileprivate let expirationQueue =
            DispatchQueue(label: "de.zeezide.nio.redisd.dbs.expiration")
    
    final fileprivate let onSavePoint : ( Database, SavePoint ) -> Void
    final fileprivate let savePoints  : SavePoints
    final internal    let lock        = RWLock()

    init<SP: Collection>(savePoints: SP,
                         onSavePoint: @escaping( Database, SavePoint ) -> Void)
               where SP.Element == SavePoint
    {
      self.savePoints  = SavePoints(savePoints)
      self.onSavePoint = onSavePoint
    }
  }
  
  final class Database : Codable {

    let context : Context
    
    var changeCountSinceLastSave = 0
    
    internal final var storage = [ Data : RedisValue ]() {
      didSet {
        changeCountSinceLastSave += 1
        checkSavePointsForCount(changeCountSinceLastSave)
      }
    }
    
    internal final var expirations = [ Data : Date ]()
    
    init(context: Context) {
      self.context = context
    }
    
    
    // MARK: - SavePoints
    
    @inline(__always)
    func checkSavePointsForCount(_ count: Int) {
      // FIXME: we should probably move this out of the database, into the
      //        dump-manager. (but that means calling a call-back, hm.).
      
      // PERF:
      // This looks a little slow, but I don't know. Using a hash on
      // the savePoint count sounds even more expensive than traversing a list
      // with (usually) few items?
      
      var useSavePoint : SavePoint?
      
      for savePoint in context.savePoints {
        if savePoint.changeCount == count {
          if let prev = useSavePoint {
            if prev.delay > savePoint.delay {
              useSavePoint = savePoint
            }
          }
          else {
            useSavePoint = savePoint
          }
        }
      }
      
      if let savePoint = useSavePoint {
        context.onSavePoint(self, savePoint)
      }
    }
    
    
    // MARK: - Accessors
    
    var count : Int {
      @inline(__always) get { return storage.count }
    }
    
    var keys : Dictionary<Data, RedisValue>.Keys {
      @inline(__always) get { return storage.keys }
    }
    
    @inline(__always)
    func removeExpiration(forKey key: Data) -> Date? {
      return expirations.removeValue(forKey: key)
    }
    
    @inline(__always)
    func removeValue(forKey key: Data) -> RedisValue? {
      expirations.removeValue(forKey: key)
      return storage.removeValue(forKey: key)
    }
    
    @inline(__always)
    func renameKey(_ oldKey: Data, to newKey: Data) -> Bool {
      let expiration = expirations[oldKey]
      
      guard let value = removeValue(forKey: oldKey) else {
        return false
      }
      
      storage[newKey] = value
      if let expiration = expiration { expirations[newKey] = expiration }
      else                           { expirations.removeValue(forKey: newKey) }
      
      return true
    }
    
    subscript(_ key: Data) -> RedisValue? {
      set {
        if let v = newValue {
          storage[key] = v
        }
        else {
          _ = removeValue(forKey: key)
        }
      }
      @inline(__always)
      get {
        return storage[key]
      }
    }
    
    subscript(expiration key: Data) -> Date? {
      set {
        if let v = newValue {
          expirations[key] = v
          scheduleExpiration(v)
        }
        else {
          expirations.removeValue(forKey: key)
        }
      }
      @inline(__always) get {
        return expirations[key]
      }
    }
    
    
    // MARK: - Expiration
    
    private var scheduledTimestamp : UInt64?
    private var workItem : DispatchWorkItem?
    
    @inline(__always)
    func granularTimestampForDate(_ date: Date) -> UInt64 {
      let ti = date.timeIntervalSince1970
      guard ti > 0 else { return 0 } // protect against underflow
      
      let granularity = 100.0 // 10ms
      return UInt64(ti * granularity)
    }
    
    func runExpiration() -> Date? { // T: write-locked
      let now          = Date()
      var nextDeadline : Date? = nil
      
      for ( key, value ) in expirations {
        if value > now {
          if nextDeadline != nil {
            nextDeadline = min(nextDeadline!, value)
          }
          else {
            nextDeadline = value
          }
        }
        else {
          _ = removeValue(forKey: key)
        }
      }
      
      return nextDeadline
    }
    
    func scheduleExpiration(_ deadline: Date) { // T: write-locked
      let newTimestamp = granularTimestampForDate(deadline)
      
      if let scheduledTimestamp = scheduledTimestamp,
             scheduledTimestamp < newTimestamp
      {
        return
      }
      
      scheduledTimestamp = nil
      workItem?.cancel()
      workItem = nil
      
      workItem = DispatchWorkItem() { [weak self] in
        guard let me = self else { return }
        
        do {
          let lock = me.context.lock
          lock.lockForWriting()
          defer { lock.unlock() }

          me.scheduledTimestamp = nil
          me.workItem           = nil // hope we are arc'ed :->
          
          if let nextDeadline = me.runExpiration() {
            me.scheduleExpiration(nextDeadline)
          }
        }
      }

      let walltime = DispatchWallTime(date: deadline)
      
      scheduledTimestamp = newTimestamp
      context.expirationQueue.asyncAfter(wallDeadline: walltime,
                                         execute: workItem!)
    }
    
    
    // MARK: - Codable
    
    enum CodingKeys: CodingKey {
      case keys, expirations
    }
    
    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      storage =
        try container.decode([ Data : RedisValue ].self, forKey: .keys)
      expirations =
        try container.decode([ Data : Date ].self, forKey: .expirations)
      
      guard let context = decoder.dbContext else {
        throw RedisDumpError.missingDatabaseContext
      }
      self.context = context
    }
    
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(storage,     forKey: .keys)
      try container.encode(expirations, forKey: .expirations)
    }
  }

  final internal let maxDBs    = 16
  final internal var databases : [ Database ]
  final internal let context   : Context
  
  init(context: Context) {
    self.context = context
    
    databases = []
    for _ in 0..<maxDBs {
      databases.append(Database(context: context))
    }
  }
  
  subscript(_ idx: Int) -> Database {
    assert(idx < databases.count, "database index out of range \(idx)")
    return databases[idx]
  }
  
  init(from decoder: Decoder) throws {
    guard let ctx = decoder.dbContext else {
      throw RedisDumpError.missingDatabaseContext
    }
    self.context = ctx
    
    databases = try [ Databases.Database ](from: decoder)
    while databases.count < maxDBs {
      databases.append(Database(context: context))
    }
  }
  
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(databases)
  }
}


// MARK: - Numbers

extension Databases.Database {
  
  func intOp(_ key: Data, defaultValue: Int = 0,
             _ op: ( Int ) -> Int) throws -> Int
  {
    let result : Int
    
    if let value = self[key] {
      guard let intValue = value.intValue else {
        throw RedisError.notAnInteger
      }
      result = op(intValue)
    }
    else {
      result = op(defaultValue)
    }
    
    self[key] = RedisValue(result)
    
    return result
  }
}


// MARK: - Lists

internal extension Databases.Database {
  
  func lset(key: Data, index: Int, value bb: ByteBuffer) throws {
    guard let value = self[key]        else { throw RedisError.noSuchKey }
    guard case .list(let list) = value else { throw RedisError.wrongType }
    
    let count  = list.count
    let cindex = index < 0 ? (count + index) : index
    guard cindex >= 0 && cindex < count else {
      throw RedisError.indexOutOfRange
    }
    
    // FIXME: use in-place mutation
    _ = self[key]!.lset(bb, at: cindex)
  }
  
  @inline(__always)
  func listPop(key: Data, left : Bool) throws -> ByteBuffer? {
    guard var value = self[key] else { return nil }
    guard case .list = value    else { throw RedisError.wrongType }
    
    let v = left ? value.lpop() : value.rpop()
    self[key] = value
    return v
  }
  
  @inline(__always)
  func listCount(key: Data) throws -> Int {
    guard let value = self[key]        else { return 0 }
    guard case .list(let list) = value else { throw RedisError.wrongType }
    return list.count
  }
  
  @inline(__always)
  func listPush(key             : Data,
                values          : RedisList,
                left            : Bool,
                createIfMissing : Bool = true) throws -> Int
  {
    let count : Int
    
    if var list = self.storage.removeValue(forKey: key) { // you wonder? ;-)
      let pc = left ? list.lpush(values)
                    : list.rpush(values)
      guard let pc2 = pc else { throw RedisError.wrongType }
      self.storage[key] = list
      count = pc2
    }
    else {
      if createIfMissing {
        self[key] = .list(values)
        count = values.count
      }
      else {
        count = 0
      }
    }
    
    return count
  }
  
  @inline(__always)
  func listPush(key             : Data,
                value           : RedisString,
                left            : Bool,
                createIfMissing : Bool = true) throws -> Int
  {
    let count : Int
    
    if var list = self.storage.removeValue(forKey: key) { // you wonder? ;-)
      let pc = left ? list.lpush(value)
                    : list.rpush(value)
      guard let pc2 = pc else { throw RedisError.wrongType }
      self.storage[key] = list
      count = pc2
    }
    else {
      if createIfMissing {
        var list = RedisList()
        list.append(value)
        self[key] = .list(list)
        count = 1
      }
      else {
        count = 0
      }
    }
    
    return count
  }
}


// MARK: - Sets

extension Databases.Database {
  
  func sadd(_ key: Data, members: ArraySlice<Data>) throws -> Int {
    let count : Int
    
    if let value = self[key] {
      guard case .set(var set) = value else { throw RedisError.wrongType }
      
      var addCount = 0
      for member in members {
        guard !set.contains(member) else { continue }
        set.insert(member)
        addCount += 1
      }
      if addCount > 0 { self[key] = .set(set) }
      count = addCount
    }
    else {
      let set = Set(members)
      self[key] = .set(set)
      count = set.count
    }
    
    return count
  }
  
  func srem(_ key: Data, members: ArraySlice<Data>) throws -> Int {
    guard let value = self[key] else { return 0 }
    
    guard case .set(var set) = value else { throw RedisError.wrongType }
    
    var delCount = 0
    for member in members {
      if set.remove(member) != nil {
        delCount += 1
      }
    }
    if delCount > 0 { self[key] = .set(set) }

    return delCount
  }
  
  func setOp(_ baseKey: Data, against keys: ArraySlice<Data>,
             _ op: (inout Set<Data>, Set<Data>) -> Void)
         throws -> Set<Data>
  {
    guard let value = self[baseKey] else { return Set() }
    guard case .set(var result) = value else { throw RedisError.wrongType }
    
    for key in keys {
      guard let value = self[key] else { continue }
      guard case .set(let set)  = value else { throw RedisError.wrongType }
      op(&result, set)
    }

    return result
  }
  
}
