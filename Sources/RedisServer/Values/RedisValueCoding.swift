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

import struct Foundation.Data
import struct NIO.ByteBuffer
import struct NIO.ByteBufferAllocator
import NIOFoundationCompat

extension KeyedDecodingContainer {
  
  func decodeByteBuffer(forKey key: Key) throws -> ByteBuffer {
    let data = try decode(Data.self, forKey: key)
    return ByteBuffer(data: data)
  }
  
  func decodeByteBufferArray(forKey key: Key) throws
         -> ContiguousArray<ByteBuffer>
  {
    let datas   = try decode(Array<Data>.self, forKey: key)
    var buffers = ContiguousArray<ByteBuffer>()
    buffers.reserveCapacity(datas.count + 1)
    
    for data in datas {
      buffers.append(ByteBuffer(data: data))
    }
    return buffers
  }

  func decodeByteBufferHash(forKey key: Key) throws -> [ Data : ByteBuffer ] {
    let datas   = try decode(Dictionary<Data, Data>.self, forKey: key)
    var buffers = [ Data : ByteBuffer ]()
    buffers.reserveCapacity(datas.count + 1)
    
    for ( key, data ) in datas {
      buffers[key] = ByteBuffer(data: data)
    }
    return buffers
  }
}

extension RedisValue : Codable {
  
  enum CodingKeys: CodingKey {
    case type, value
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type      = try container.decode(String.self, forKey: .type)
    
    switch type {
      case "string":
        self = .string(try container.decodeByteBuffer(forKey: .value))
      
      case "list":
        self = .list(try container.decodeByteBufferArray(forKey: .value))
      
      case "set":
        self = .set(try container.decode(Set<Data>.self, forKey: .value))
      
      case "hash":
        self = .hash(try container.decodeByteBufferHash(forKey: .value))

      default:
        assertionFailure("unexpected dump value type: \(type)")
        throw RedisDumpError.unexpectedValueType(type)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    
    switch self {
      case .string(let value):
        try container.encode("string", forKey: .type)
        try container.encode(value,    forKey: .value)
      
      case .list(let value):
        try container.encode("list",       forKey: .type)
        try container.encode(Array(value), forKey: .value)
      
      case .set(let value):
        try container.encode("set", forKey: .type)
        try container.encode(value, forKey: .value)

      case .hash(let value):
        try container.encode("hash", forKey: .type)
        try container.encode(value,  forKey: .value)

      case .clear:
        assertionFailure("cannot dump transient .clear type")
        throw RedisDumpError.internalError
    }
  }
}
