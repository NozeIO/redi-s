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

protocol DumpManager {

  func saveDump(of databases: Databases, to url: URL, asynchronously: Bool)
         throws

  func loadDumpIfAvailable(url: URL, configuration: RedisServer.Configuration)
         -> Databases

  func getLastSave(_ cb: @escaping ( Date, TimeInterval ) -> Void)
}


// MARK: - Hackish, slow and wasteful store

import Dispatch
import Foundation

extension CodingUserInfoKey {
  static let dbContext =
               CodingUserInfoKey(rawValue: "de.zeezide.nio.redis.dbs.context")!
}

extension Decoder {
  
  var dbContext : Databases.Context? {
    return userInfo[CodingUserInfoKey.dbContext] as? Databases.Context
  }
  
}


enum RedisDumpError : Swift.Error {
  case missingDatabaseContext
  case internalError
  case unexpectedValueType(String)
}

class SimpleJSONDumpManager : DumpManager {
  
  let Q      = DispatchQueue(label: "de.zeezide.nio.redisd.dump")
  let logger : RedisLogger
  
  weak var server : RedisServer? // FIXME: this is not great, cleanup

  private var lastSave         = Date.distantPast
  private var lastSaveDuration : TimeInterval = 0
  
  private var scheduledDate : Date?
  private var workItem      : DispatchWorkItem?

  init(server : RedisServer) {
    self.server = server
    self.logger = server.logger
  }
  
  
  // MARK: - Database Triggered Saves
  
  func _scheduleSave(in ti: TimeInterval) { // Q: own
    let now      = Date()
    let deadline = now.addingTimeInterval(ti)
    
    if let oldDate = scheduledDate, oldDate < deadline { return }
    
    scheduledDate = nil
    workItem?.cancel()
    workItem = nil
    
    workItem = DispatchWorkItem() { [weak self] in
      guard let me = self else { return }
      me.scheduledDate = nil
      me.workItem      = nil // hope we are arc'ed :->
      
      if let server = me.server, let dbs = server.databases {
        do {
          // reset counter
          do {
            let dbContext = dbs.context
            dbContext.lock.lockForWriting()
            defer { dbContext.lock.unlock() }
            
            for db in dbs.databases {
              db.changeCountSinceLastSave = 0
            }
          }
          
          let ( lastSave, diff ) = try me._saveDump(of: dbs, to: server.dumpURL)
          me.lastSave         = lastSave
          me.lastSaveDuration = diff
        }
        catch {
          me.logger.error("scheduled save failed:", error)
        }
      }
    }
    
    let walltime = DispatchWallTime(date: deadline)
    
    scheduledDate = deadline
    Q.asyncAfter(wallDeadline: walltime, execute: workItem!)
  }
  
  
  // MARK: - Command Triggered Operations

  func getLastSave(_ cb: @escaping ( Date, TimeInterval ) -> Void) {
    Q.async {
      cb(self.lastSave, self.lastSaveDuration)
    }
  }
  
  func saveDump(of databases: Databases, to url: URL, asynchronously: Bool)
         throws
  {
    if !asynchronously {
      let ( lastSave, diff ) = try self._saveDump(of: databases, to: url)
      Q.async {
        self.lastSave         = lastSave
        self.lastSaveDuration = diff
      }
    }
    else {
      Q.async {
        do {
          let ( lastSave, diff ) = try self._saveDump(of: databases, to: url)
          self.lastSave         = lastSave
          self.lastSaveDuration = diff
        }
        catch {
          self.logger.error("asynchronous save failed:", error)
        }
      }
    }
  }
  
  func _saveDump(of databases: Databases, to url: URL) throws
         -> ( Date, TimeInterval )
  {
    let start = Date()
    
    do {
      let encoder = JSONEncoder()
      let data    = try encoder.encode(databases)
      try data.write(to: url, options: .atomic)
    }
    
    let done = Date()
    return ( done, done.timeIntervalSince(start) )
  }
  
  func makeFreshDatabases(with context: Databases.Context)
         -> Databases
  {
    return Databases(context: context)

  }
  
  func loadDumpIfAvailable(url: URL, configuration: RedisServer.Configuration)
         -> Databases
  {
    let start = Date()
    
    // FIXME: The dump manager should manage the dumping and counting. The
    //        DB should just report changes.
    let dbContext =
      Databases.Context(savePoints: configuration.savePoints ?? [],
                        onSavePoint: { [weak self] db, savePoint in
                          guard let me = self else { return }
                          // Careful: running in DB thread
                          me.Q.async {
                            me._scheduleSave(in: savePoint.delay)
                          }
                        })
    
    let fm = FileManager()
    
    guard let data = fm.contents(atPath: url.path), data.count > 2 else {
      return makeFreshDatabases(with: dbContext)
    }
    
    let decoder = JSONDecoder()
    decoder.userInfo[CodingUserInfoKey.dbContext] = dbContext
    
    let dbs : Databases
    do {
      dbs = try decoder.decode(Databases.self, from: data)
    }
    catch {
      logger.error("failed to decode dump:", url.path, error)
      return makeFreshDatabases(with: dbContext)
    }
    
    let diff  = Date().timeIntervalSince(start)
    let diffs = timeDiffFormatter.string(from: NSNumber(value: diff)) ?? "-"
    logger.log("DB loaded from disk: \(diffs) seconds")
    
    do {
      let lock = dbs.context.lock
      lock.lockForWriting()
      defer { lock.unlock() }
      
      for db in dbs.databases {
        db.scheduleExpiration(Date())
      }
    }
    
    return dbs
  }
  
}

fileprivate let timeDiffFormatter : NumberFormatter = {
  let nf = NumberFormatter()
  nf.locale = Locale(identifier: "en_US")
  nf.minimumIntegerDigits  = 1
  nf.minimumFractionDigits = 3
  nf.maximumFractionDigits = 3
  return nf
}()
