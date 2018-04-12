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

extension DispatchWallTime {
  
  init(date: Date) {
    // TBD: is this sound? hm.
    let ti    = date.timeIntervalSince1970
    let secs  = Int(ti)
    let nsecs = Int((ti - TimeInterval(secs)) * 1_000_000_000)
    self.init(timespec: timespec(tv_sec: secs, tv_nsec: nsecs))
  }
  
}

final class RWLock {
  
  private var lock = pthread_rwlock_t()
  
  public init() {
    pthread_rwlock_init(&lock, nil)
  }
  deinit {
    pthread_rwlock_destroy(&lock)
  }
  
  @inline(__always)
  func lockForReading() {
    pthread_rwlock_rdlock(&lock)
  }
  
  @inline(__always)
  func lockForWriting() {
    pthread_rwlock_wrlock(&lock)
  }

  @inline(__always)
  func unlock() {
    pthread_rwlock_unlock(&lock)
  }

}
