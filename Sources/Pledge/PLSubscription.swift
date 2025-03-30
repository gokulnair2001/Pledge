//
//  Subscription.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 24/03/25.
//

import Foundation


/// Represents a single subscription to an observable
/// This internal class manages the delivery of value updates to subscribers
internal class PLSubscription<T> {
    /// Unique identifier for the subscription
    /// Used to identify and manage subscriptions for unsubscribing
    let id: UUID
    
    /// Queue where notifications should be delivered (if any)
    /// When nil, notifications are delivered synchronously on the current thread
    let queue: DispatchQueue?
    
    /// Priority level for notification order
    /// Higher priority subscribers are notified before lower priority ones
    let priority: PLObserverPriority
    
    /// Rate limiting type to use for this subscription
    /// Controls throttling or debouncing behavior for this specific subscription
    let rateLimitingType: PLRateLimitingType
    
    /// The time of the last notification sent to this subscriber
    /// Used for throttling and debouncing calculations
    var lastNotificationTime: Date?
    
    /// Work item used for debouncing (nil when not debouncing)
    /// Stores the pending notification that will be sent after the debounce interval
    var debounceWorkItem: DispatchWorkItem?
    
    /// The closure to call when the observable value changes
    /// This is the handler provided by the subscriber
    let handler: (T) -> Void
    
    /// Creates a new subscription with the specified parameters
    /// - Parameters:
    ///   - id: Unique identifier for the subscription (defaults to a new UUID)
    ///   - queue: Queue where notifications should be delivered (nil for synchronous delivery)
    ///   - priority: Priority level for notification ordering
    ///   - rateLimitingType: Type of rate limiting to apply (throttling, debouncing, or none)
    ///   - handler: Closure to call when the observable value changes
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
    /// - Parameter value: The value to pass to the handler
    /// - Note: Dispatches to the specified queue if one was provided, otherwise executes synchronously
    func notify(with value: T) {
        if let queue = queue {
            // Asynchronously dispatch to the specified queue
            queue.async {
                self.handler(value)
            }
        } else {
            // No queue specified, execute synchronously on the current thread
            handler(value)
        }
    }
    
    /// Cancels any pending debounce notification
    /// - Note: This should be called when unsubscribing or when a new notification supersedes a pending one
    func cancelPendingDebounceNotifications() {
        // Cancel the work item if it exists
        debounceWorkItem?.cancel()
        // Clear the reference to avoid memory leaks
        debounceWorkItem = nil
    }
    
    /// Automatically cleans up resources when the subscription is deallocated
    /// This prevents memory leaks from pending work items
    deinit {
        // Clean up any pending work items when this subscription is deallocated
        cancelPendingDebounceNotifications()
    }
}
