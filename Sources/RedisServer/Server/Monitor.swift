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

import class  Foundation.NumberFormatter
import class  Foundation.NSNumber
import struct Foundation.Locale
import struct Foundation.Date

fileprivate let redisMonitorTimestampFormat : NumberFormatter = {
  let nf = NumberFormatter()
  nf.locale = Locale(identifier: "en_US")
  nf.minimumFractionDigits = 6
  nf.maximumFractionDigits = 6
  return nf
}()

internal extension RedisCommandHandler.MonitorInfo {
  
  var redisClientLogLine : String {
    let now = Date().timeIntervalSince1970
    
    var logStr = redisMonitorTimestampFormat.string(from: NSNumber(value: now))
              ?? "-"
    
    logStr += " [\(db) "
    
    if let addr = addr {
      switch addr {
        case .v4(let addr4): logStr += "\(addr4.host):\(addr.port ?? 0)"
        case .v6(let addr6):
          if addr6.host.hasPrefix(":") {
            logStr += "[\(addr6.host)]:\(addr.port ?? 0)"
          }
          else { logStr += "\(addr6.host):\(addr.port ?? 0)" }
        default:             logStr += addr.description
      }
    }
    else { logStr += "-" }
    logStr += "]"
  
    if case .array(.some(let callList)) = call {
      for v in callList {
        logStr += " "
        if      let s = v.stringValue { logStr += "\"\(s)\"" }
        else if let i = v.intValue    { logStr += String(i)  }
        else                          { logStr += " ?"       }
      }
    }
    else {
      logStr += " unexpected value type"
    }
    
    return logStr
  }
}
