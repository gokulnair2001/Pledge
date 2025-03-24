//
//  Subscription.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 24/03/25.
//

import Foundation


/// Represents a single subscription to an observable
internal class PLSubscription<T> {
    /// Unique identifier for the subscription
    let id: UUID
    
    /// Queue where notifications should be delivered (if any)
    let queue: DispatchQueue?
    
    /// Priority level for notification order
    let priority: PLObserverPriority
    
    /// Rate limiting type to use for this subscription
    let rateLimitingType: PLRateLimitingType
    
    /// The time of the last notification sent to this subscriber
    var lastNotificationTime: Date?
    
    /// Work item used for debouncing (nil when not debouncing)
    var debounceWorkItem: DispatchWorkItem?
    
    /// The closure to call when the observable value changes
    let handler: (T) -> Void
    
    /// Creates a new subscription with the specified parameters
    init(id: UUID = UUID(),
         queue: DispatchQueue? = nil,
         priority: PLObserverPriority = .normal,
         rateLimitingType: PLRateLimitingType = .none,
         handler: @escaping (T) -> Void) {
        self.id = id
        self.queue = queue
        self.priority = priority
        self.rateLimitingType = rateLimitingType
        self.handler = handler
    }
    
    /// Executes this subscription's handler with the given value
    func notify(with value: T) {
        if let queue = queue {
            queue.async {
                self.handler(value)
            }
        } else {
            handler(value)
        }
    }
    
    /// Cancels any pending debounce notification
    func cancelPendingDebounceNotifications() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }
    
    deinit {
        // Clean up any pending work items when this subscription is deallocated
        cancelPendingDebounceNotifications()
    }
}
