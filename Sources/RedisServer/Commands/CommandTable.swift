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

import Foundation
import NIO
import NIORedis

public typealias RedisCommandTable = [ RedisCommand ]

extension RedisServer {
  
  static let defaultCommandTable : RedisCommandTable = [
    // command is funny in that arity is 0
    Command(name  : "COMMAND",
            type  : .optionalValue(Commands.COMMAND), // FIXME: multivalue
            flags : [ .loading, .stale ]),
    
    Command(name  : "PING",
            type  : .optionalValue(Commands.PING),
            flags : [ .stale, .fast ]),
    Command(name  : "ECHO",
            type  : .singleValue(Commands.PING),
            flags : [ .stale, .fast ]),

    Command(name  : "QUIT",
            type  : .noArguments(Commands.QUIT),
            flags : [ .admin ]),
    Command(name  : "MONITOR",
            type  : .noArguments(Commands.MONITOR),
            flags : [ .admin ]),
    Command(name  : "SAVE",
            type  : .noArguments(Commands.SAVE),
            flags : [ .admin ]),
    Command(name  : "BGSAVE",
            type  : .noArguments(Commands.SAVE),
            flags : [ .admin ]),
    Command(name  : "LASTSAVE",
            type  : .noArguments(Commands.LASTSAVE),
            flags : [ .admin ]),
    Command(name  : "CLIENT",
            type  : .oneOrMoreValues(Commands.CLIENT),
            flags : [ .admin, .noscript ]),
    
    Command(name  : "PUBLISH",
            type  : .keyValue(Commands.PUBLISH),
            flags : [ .pubsub, .loading, .stale, .fast ]),
    Command(name  : "SUBSCRIBE",
            type  : .keys(Commands.SUBSCRIBE),
            flags : [ .pubsub, .noscript, .loading, .stale ]),
    Command(name  : "UNSUBSCRIBE",
            type  : .keys(Commands.UNSUBSCRIBE),
            flags : [ .pubsub, .noscript, .loading, .stale ]),
    Command(name  : "PSUBSCRIBE",
            type  : .oneOrMoreValues(Commands.PSUBSCRIBE),
            flags : [ .pubsub, .noscript, .loading, .stale ]),
    Command(name  : "PUNSUBSCRIBE",
            type  : .oneOrMoreValues(Commands.PUNSUBSCRIBE),
            flags : [ .pubsub, .noscript, .loading, .stale ]),
    Command(name  : "PUBSUB",
            type  : .oneOrMoreValues(Commands.PUBSUB),
            flags : [ .pubsub, .random, .loading, .stale ]),

    Command(name  : "SELECT",
            type  : .singleValue(Commands.SELECT),
            flags : [ .loading, .fast ]),
    Command(name  : "SWAPDB",
            type  : .valueValue(Commands.SWAPDB),
            flags : [ .write, .fast ]),

    // MARK: - Generic Commands

    Command(name  : "DBSIZE",
            type  : .noArguments(Commands.DBSIZE),
            flags : [ .readonly, .fast ]),
    Command(name  : "KEYS",
            type  : .singleValue(Commands.KEYS),
            flags : [ .readonly, .sortForScript ]),
    Command(name  : "DEL",
            type  : .keys(Commands.DEL),
            flags : [ .write ]),
    Command(name  : "EXISTS",
            type  : .keys(Commands.EXISTS),
            flags : [ .readonly, .fast ]),
    Command(name  : "TYPE",
            type  : .key(Commands.TYPE),
            flags : [ .readonly, .fast ]),
    Command(name  : "RENAME",
            type  : .keyKey(Commands.RENAME),
            flags : [ .write ]),
    Command(name  : "RENAMENX",
            type  : .keyKey(Commands.RENAMENX),
            flags : [ .write ]),
    
    // MARK: - Expiration Commands
    
    Command(name  : "PERSIST",
            type  : .key(Commands.PERSIST),
            flags : [ .write, .fast ]),
    Command(name  : "EXPIRE",
            type  : .keyValue(Commands.EXPIRE),
            flags : [ .write, .fast ]),
    Command(name  : "PEXPIRE",
            type  : .keyValue(Commands.EXPIRE),
            flags : [ .write, .fast ]),
    Command(name  : "EXPIREAT",
            type  : .keyValue(Commands.EXPIRE),
            flags : [ .write, .fast ]),
    Command(name  : "PEXPIREAT",
            type  : .keyValue(Commands.EXPIRE),
            flags : [ .write, .fast ]),
    Command(name  : "TTL",
            type  : .key(Commands.TTL),
            flags : [ .readonly, .fast ]),
    Command(name  : "PTTL",
            type  : .key(Commands.TTL),
            flags : [ .readonly, .fast ]),

    // MARK: - String Commands
    
    Command(name  : "SET",
            type  : .keyValueOptions(Commands.SET),
            flags : [ .write, .denyoom ]),
    Command(name  : "GETSET",
            type  : .keyValue(Commands.GETSET),
            flags : [ .write, .denyoom ]),
    Command(name  : "SETNX",
            type  : .keyValue(Commands.SETNX),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "SETEX",
            type  : .keyValueValue(Commands.SETEX),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "PSETEX",
            type  : .keyValueValue(Commands.SETEX),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "APPEND",
            type  : .keyValue(Commands.APPEND),
            flags : [ .write, .denyoom ]),
    Command(name  : "SETRANGE",
            type  : .keyIndexValue(Commands.SETRANGE),
            flags : [ .write, .denyoom ]),
    Command(name  : "GET",
            type  : .key(Commands.GET),
            flags : [ .readonly, .fast ]),
    Command(name  : "STRLEN",
            type  : .key(Commands.STRLEN),
            flags : [ .readonly, .fast ]),
    Command(name  : "GETRANGE",
            type  : .keyRange(Commands.GETRANGE),
            flags : [ .readonly ]),
    Command(name  : "SUBSTR", // same like GETRANGE
            type  : .keyRange(Commands.GETRANGE),
            flags : [ .readonly ]),
    Command(name  : "MGET",
            type  : .keys(Commands.MGET),
            flags : [ .readonly, .fast ]),
    Command(name  : "MSET",
            type  : .keyValueMap(Commands.MSET),
            flags : [ .write, .denyoom ]),
    Command(name  : "MSETNX",
            type  : .keyValueMap(Commands.MSETNX),
            flags : [ .write, .denyoom ]),

    // MARK: - Integer String Commands
    
    Command(name  : "INCR",
            type  : .key(Commands.INCR),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "DECR",
            type  : .key(Commands.DECR),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "INCRBY",
            type  : .keyValue(Commands.INCRBY),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "DECRBY",
            type  : .keyValue(Commands.DECRBY),
            flags : [ .write, .denyoom, .fast ]),

    // MARK: - List Commands
    
    Command(name  : "LLEN",
            type  : .key(Commands.LLEN),
            flags : [ .readonly, .fast ]),
    Command(name  : "LRANGE",
            type  : .keyRange(Commands.LRANGE),
            flags : [ .readonly ]),
    Command(name  : "LINDEX",
            type  : .keyIndex(Commands.LINDEX),
            flags : [ .readonly ]),
    Command(name  : "LSET",
            type  : .keyIndexValue(Commands.LSET),
            flags : [ .write, .denyoom ]),
    Command(name  : "RPUSH",
            type  : .keyValues(Commands.RPUSH),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "LPUSH",
            type  : .keyValues(Commands.LPUSH),
            flags : [ .write, .denyoom /*, .fast - not really :-) */ ]),
    Command(name  : "RPUSHX",
            type  : .keyValue(Commands.RPUSHX),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "LPUSHX",
            type  : .keyValue(Commands.LPUSHX),
            flags : [ .write, .denyoom /*, .fast - not really :-) */ ]),
    Command(name  : "RPOP",
            type  : .key(Commands.RPOP),
            flags : [ .write, .fast ]),
    Command(name  : "LPOP",
            type  : .key(Commands.LPOP),
            flags : [ .write, /*, .fast - not really :-) */ ]),
    
    // MARK: - Hash Commands
    
    Command(name  : "HLEN",
            type  : .key(Commands.HLEN),
            flags : [ .readonly, .fast ]),
    Command(name  : "HGETALL",
            type  : .key(Commands.HGETALL),
            flags : [ .readonly, .fast ]),
    Command(name  : "HGET",
            type  : .keyValue(Commands.HGET),
            flags : [ .readonly, .fast ]),
    Command(name  : "HEXISTS",
            type  : .keyValue(Commands.HEXISTS),
            flags : [ .readonly, .fast ]),
    Command(name  : "HSTRLEN",
            type  : .keyValue(Commands.HSTRLEN),
            flags : [ .readonly, .fast ]),
    Command(name  : "HKEYS",
            type  : .key(Commands.HKEYS),
            flags : [ .readonly, .sortForScript ]),
    Command(name  : "HVALS",
            type  : .key(Commands.HVALS),
            flags : [ .readonly, .sortForScript ]),
    Command(name  : "HSET",
            type  : .keyValueValue(Commands.HSET),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "HSETNX",
            type  : .keyValueValue(Commands.HSET),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "HINCRBY",
            type  : .keyValueValue(Commands.HINCRBY),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "HMSET",
            type  : .keyValues(Commands.HMSET),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "HDEL",
            type  : .keyValues(Commands.HDEL),
            flags : [ .write, .fast ]),
    Command(name  : "HMGET",
            type  : .keyValues(Commands.HMGET),
            flags : [ .readonly, .fast ]),

    // MARK: - Set Commands
    
    Command(name  : "SCARD",
            type  : .key(Commands.SCARD),
            flags : [ .readonly, .fast ]),
    Command(name  : "SMEMBERS",
            type  : .key(Commands.SMEMBERS),
            flags : [ .readonly, .fast ]),
    Command(name  : "SISMEMBER",
            type  : .keyKey(Commands.SISMEMBER),
            flags : [ .readonly, .fast ]),
    Command(name  : "SADD",
            type  : .keys(Commands.SADD),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "SREM",
            type  : .keys(Commands.SREM),
            flags : [ .write, .denyoom, .fast ]),
    Command(name  : "SDIFF",
            type  : .keys(Commands.SDIFF),
            flags : [ .readonly, .sortForScript ]),
    Command(name  : "SINTER",
            type  : .keys(Commands.SINTER),
            flags : [ .readonly, .sortForScript ]),
    Command(name  : "SUNION",
            type  : .keys(Commands.SUNION),
            flags : [ .readonly, .sortForScript ]),
    Command(name  : "SDIFFSTORE",
            type  : .keys(Commands.SDIFFSTORE),
            flags : [ .write, .denyoom ]),
    Command(name  : "SINTERSTORE",
            type  : .keys(Commands.SINTERSTORE),
            flags : [ .write, .denyoom ]),
    Command(name  : "SUNIONSTORE",
            type  : .keys(Commands.SUNIONSTORE),
            flags : [ .write, .denyoom ]),
  ]
}


// MARK: - Implementations

enum Commands {
  
  typealias CommandContext = RedisCommandContext // TODO: drop this
  typealias Context        = RedisCommandContext

}
