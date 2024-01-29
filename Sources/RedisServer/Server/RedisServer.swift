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

import class  Dispatch.DispatchQueue
import struct Foundation.URL
import struct Foundation.TimeInterval
import class  Foundation.FileManager
import class  Foundation.JSONDecoder
import class  NIOConcurrencyHelpers.Atomic
import enum   NIORedis.RESPValue
import NIO

public let DefaultRedisPort = 6379

open class RedisServer {
  
  public typealias Command = RedisCommand
  
  open class Configuration {
    
    public struct SavePoint {
      public let delay       : TimeInterval
      public let changeCount : Int
      
      public init(delay: TimeInterval, changeCount: Int) {
        self.delay       = delay
        self.changeCount = changeCount
      }
    }
    
    open var host           : String? = nil // "127.0.0.1"
    open var port           : Int     = DefaultRedisPort
    
    open var alwaysShowLog  : Bool    = true
    
    open var dbFilename     : String  = "dump.json"
    open var savePoints     : [ SavePoint ]? = nil
    
    open var eventLoopGroup : EventLoopGroup? = nil
    
    open var commands : RedisCommandTable = RedisServer.defaultCommandTable
    open var logger   : RedisLogger       = RedisPrintLogger(logLevel: .Log)
    
    public init() {}
  }
  
  public let configuration : Configuration
  public let group         : EventLoopGroup
  public let logger        : RedisLogger
  public let commandTable  : RedisCommandTable
  public let dumpURL       : URL
  
  let commandMap  : [ String : Command ]
  var dumpManager : DumpManager! // oh my. init-mess
  var databases   : Databases?
  
  let Q           = DispatchQueue(label: "de.zeezide.nio.redisd.clients")
  let clientID    = Atomic<Int>(value: 0)
  var clients     = [ ObjectIdentifier : RedisCommandHandler ]()
  var monitors    = Atomic<Int>(value: 0)
  let pubSub      : PubSub
  
  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
    
    self.group        = configuration.eventLoopGroup
                     ?? MultiThreadedEventLoopGroup(numberOfThreads: 2)
    self.commandTable = configuration.commands
    self.logger       = configuration.logger
    self.dumpURL      = URL(fileURLWithPath: configuration.dbFilename)
    
    pubSub    = PubSub(Q: Q)
    
    commandMap = Dictionary(grouping: commandTable,
                            by: { $0.name.uppercased() })
                   .mapValues({ $0.first! })
    
    self.dumpManager = SimpleJSONDumpManager(server: self)
  }
  
  
  public func stopOnSigInt() {
    logger.warn("Received SIGINT scheduling shutdown...")
    
    Q.async { // Safe? Unsafe. No idea. Probably not :-)
      // TODO: I think the proper trick is to use a pipe here.
      if let dbs = self.databases {
        do {
          self.logger.warn("User requested shutdown...")
          try self.dumpManager.saveDump(of: dbs, to: self.dumpURL,
                                        asynchronously: false)
        }
        catch {
          self.logger.error("failed to save database:", error)
        }
      }
      self.logger.warn("Redis is now ready to exit, bye bye...")
      exit(0)
    }
  }
  
  var serverChannel : Channel?
  
  open func listenAndWait() {
    listen()
    
    do {
      try serverChannel?.closeFuture.wait() // no close, no exit
    }
    catch {
      logger.error("failed to wait on server:", error)
    }
  }
  
  open func listen() {
    let bootstrap = makeBootstrap()
    
    do {
      logStartupOnPort(configuration.port)
      
      loadDumpIfAvailable()
      
      let address : SocketAddress
      
      if let host = configuration.host {
        address = try SocketAddress
          .makeAddressResolvingHost(host, port: configuration.port)
      }
      else {
        var addr = sockaddr_in()
        addr.sin_port = in_port_t(configuration.port).bigEndian
        address = SocketAddress(addr, host: "*")
      }

      serverChannel = try bootstrap.bind(to: address)
                                   .wait()
      
      if let addr = serverChannel?.localAddress {
        logSetupOnAddress(addr)
      }
      else {
        logger.warn("server reported no local addres?")
      }
    }
    catch let error as NIO.IOError {
      logger.error("failed to start server, errno:", error.errnoCode, "\n",
                   error.localizedDescription)
    }
    catch {
      logger.error("failed to start server:", type(of:error), error)
    }
  }
  
  func logStartupOnPort(_ port: Int) {
    if configuration.alwaysShowLog {
      let title = "Redi/S \(MemoryLayout<Int>.size * 8) bit"
      let line1 = "Port: \(port)"
      let line2 = "PID: \(getpid())"

      let logo = """
                  ____          _ _    ______
                  |  _ \\ ___  __| (_)  / / ___|    \(title)
                  | |_) / _ \\/ _` | | / /\\___ \\
                  |  _ <  __/ (_| | |/ /  ___) |   \(line1)
                  |_| \\_\\___|\\__,_|_/_/  |____/    \(line2)\n
                 """
      print(logo)
    }

  }
  func logSetupOnAddress(_ address: SocketAddress) {
    logger.log("Ready to accept connections")
    if !configuration.alwaysShowLog {
      logger.warn("Redi/S running on:", address)
    }
  }
  
  
  // MARK: - Load Database Dump
  
  func loadDumpIfAvailable() {
    defer { logger.warn("Server initialized") }

    databases = dumpManager.loadDumpIfAvailable(url: dumpURL,
                                                configuration: configuration)
  }

  
  // MARK: - Client Registry
  
  func _registerClient(_ client: RedisCommandHandler) { // Q!
    clients[ObjectIdentifier(client)] = client
  }
  
  func _unregisterClient(_ client: RedisCommandHandler) { // Q!
    let oid = ObjectIdentifier(client)
    clients.removeValue(forKey: oid)
    if client.isMonitoring.load() { _ = monitors.add(-1) }
  }
  
  
  // MARK: - Monitors
  
  func notifyMonitors(info: RedisCommandHandler.MonitorInfo) {
    // 1522931848.230484 [0 127.0.0.1:60376] "SET" "a" "10"
    
    let logPacket : RESPValue = {
      let logStr = info.redisClientLogLine
      let bb     = ByteBuffer(string: logStr)
      return RESPValue.simpleString(bb)
    }()
    
    Q.async {
      for ( _, client ) in self.clients {
        guard client.isMonitoring.load()   else { continue }
        guard let channel = client.channel else { continue }
        channel.writeAndFlush(logPacket, promise: nil)
      }
    }
  }
  
  
  // MARK: - Bootstrap

  open func makeBootstrap() -> ServerBootstrap {
    let clientID = self.clientID
    
    let reuseAddrOpt = ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET),
                                             SO_REUSEADDR)
    let bootstrap = ServerBootstrap(group: group)
      // Specify backlog and enable SO_REUSEADDR for the server itself
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(reuseAddrOpt, value: 1)
      
      // Set the handlers that are applied to the accepted Channels
      .childChannelInitializer { channel in
        channel.pipeline
          .addHandler(BackPressureHandler() /* Oh well :-) */,
                      name: "com.apple.nio.backpressure")
          .flatMap {
            let cid     = clientID.add(1)
            let handler = RedisCommandHandler(id: cid, server: self)
            
            self.Q.async {
              self._registerClient(handler)
            }
            
            return channel.pipeline
              .addHandler(handler, name:"de.zeezide.nio.redis.server.client")
          }
      }
      
      // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
      .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY),
                          value: 1)
      .childChannelOption(reuseAddrOpt, value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
    
    return bootstrap
  }
  
}
