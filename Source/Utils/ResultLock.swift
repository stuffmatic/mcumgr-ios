/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

class ResultLock {
    
    private var semaphore: DispatchSemaphore
    var isOpen: Bool = false
    var error: Error?
    
    init(isOpen: Bool) {
        self.isOpen = isOpen
        self.semaphore = DispatchSemaphore(value: 0)
    }
    
    /// Block the current thread until the condition is opened.
    ///
    /// If the condition is already opened, return immediately
    func block() -> LockResult {
        if !isOpen {
            semaphore.wait()
        }
        if error != nil {
            return .error(error!)
        } else {
            return .success
        }
    }
    
    /// Block the current thread until the condition is opened or until timeout.
    ///
    /// If the condition is opened, return immediately
    func block(timeout: DispatchTime) -> LockResult {
        let dispatchTimeoutResult: DispatchTimeoutResult
        if !isOpen {
            dispatchTimeoutResult = semaphore.wait(timeout: timeout)
        } else {
            dispatchTimeoutResult = .success
        }
        
        if dispatchTimeoutResult == .timedOut {
            return .timeout
        } else if error != nil {
            return .error(error!)
        } else {
            return .success
        }
    }
    
    /// Open the condition, and release all threads that are blocked
    ///
    /// Any threads that later approach block() will not block unless close() is called.
    func open(_ error: Error? = nil) {
        objc_sync_enter(self)
        self.error = error
        if !isOpen {
            isOpen = true
            semaphore.signal()
        }
        objc_sync_exit(self)
    }
    
    /// Reset the condtion to the closed state
    func close() {
        objc_sync_enter(self)
        error = nil
        semaphore = DispatchSemaphore(value: 0)
        isOpen = false
        objc_sync_exit(self)
    }
}

enum LockResult {
    case timeout
    case success
    case error(Error)
}