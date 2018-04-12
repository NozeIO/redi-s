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

import RedisServer
import Foundation

extension RedisServer.Configuration.SavePoint {
  
  /**
   * Parse config format:
   *   save 900 1     - after 900 sec (15 min) if at least 1 key changed
   *   save 300 10    - after 300 sec (5 min) if at least 10 keys changed
   *   save 60 10000  - after 60 sec if at least 10000 keys changed
   */
  init?(_ s: String) {
    guard !s.isEmpty else { return nil }
    
    let ts = s.trimmingCharacters(in: CharacterSet.whitespaces)
    
    #if swift(>=4.1)
      let comps = ts.components(separatedBy: CharacterSet.whitespaces)
                    .compactMap { $0.isEmpty ? nil : $0 }
    #else
      let comps = ts.components(separatedBy: CharacterSet.whitespaces)
                    .flatMap { $0.isEmpty ? nil : $0 }
    #endif
    
    guard comps.count == 2 else { return nil }
    
    guard let intervalInMS = Int(comps[0]), let count = Int(comps[1]) else {
      return nil
    }
    
    self.init(delay: TimeInterval(intervalInMS) / 1000.0,
              changeCount: count)
  }
  
}

