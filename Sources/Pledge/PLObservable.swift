//
//  PLObservable.swift
//  Pledge
//
//  Created by Gokul Nair on 22/03/25.
//

import Foundation


/// A thread-safe observable container that notifies subscribers when its value changes.
/// Supports batch updates, thread-specific delivery, and priority-ordered notifications.
public class PLObservable<T> {
    
    /// Stores all active subscriptions
    private var subscribers: [PLSubscription<T>] = []
    
    /// Temporary storage for the queue to be used for the next subscription
    private var deliveryQueue: DispatchQueue? = nil
    
    /// Temporary storage for the priority to be used for the next subscription
    private var nextSubscriptionPriority: PLObserverPriority = .normal
    
    /// Temporary storage for rate limiting type (throttle/debounce)
    private var nextRateLimitingType: PLRateLimitingType = .none
    
    /// Concurrent queue used for thread-safe access with barriers for write operations
    private let syncQueue = DispatchQueue(label: "com.swobservable.sync", attributes: .concurrent)
    
    /// Indicates whether batch update mode is active
    private var isBatchUpdating: Bool = false
    
    /// Tracks whether changes have occurred during batch updates that require notification
    private var hasPendingNotification: Bool = false
    
    /// Controls whether subscribers should be notified of changes
    private var shouldNotifySubscribers: Bool = true
    
    /// Thread-safe backing storage for the value
    private var _value: T
    
    /// The observable value. Reading is thread-safe, writing triggers notifications by default.
    private(set) var value: T {
        get {
            // Thread-safe read access
            return syncQueue.sync { _value }
        }
        set {
            // Delegate to setValue for consistent behavior
            setValue(newValue, notify: true)
        }
    }
    
    /// Initializes a new observable with the given initial value
    /// - Parameter value: The initial value to store
    public init(_ value: T) {
        self._value = value
    }
    
    /// Specifies a custom dispatch queue for the next subscription
    /// - Parameter queue: The queue to deliver updates on
    /// - Returns: Self for chaining
    @discardableResult
    public func deliver(on queue: DispatchQueue) -> Self {
        syncQueue.sync(flags: .barrier) {
            self.deliveryQueue = queue
        }
        return self
    }
    
    /// Specifies that the next subscription should receive updates on the main queue
    /// - Returns: Self for chaining
    @discardableResult
    public func deliverOnMain() -> Self {
        return deliver(on: DispatchQueue.main)
    }
    
    /// Sets the priority for the next subscription
    /// - Parameter priority: The priority level for the next subscription
    /// - Returns: Self for chaining
    @discardableResult
    public func withPriority(_ priority: PLObserverPriority) -> Self {
        syncQueue.sync(flags: .barrier) {
            self.nextSubscriptionPriority = priority
        }
        return self
    }
    
    /// Subscribes to value changes
    /// - Parameter observer: Closure to call with the current value and when changes occur
    /// - Returns: A token that can be used to unsubscribe later
    @discardableResult
    public func subscribe(_ observer: @escaping (T) -> Void) -> UUID {
        return syncQueue.sync {
            // Create a new subscription
            let subscription = PLSubscription<T>(
                queue: deliveryQueue,
                priority: nextSubscriptionPriority,
                rateLimitingType: nextRateLimitingType,
                handler: observer
            )
            
            // Add to subscribers list
            subscribers.append(subscription)
            
            // Get current value
            let currentValue = _value
            
            // Notify immediately - but don't apply rate limiting for the initial value
            subscription.notify(with: currentValue)
            
            // Reset temporary subscription settings
            deliveryQueue = nil
            nextSubscriptionPriority = .normal
            nextRateLimitingType = .none
            
            return subscription.id
        }
    }
    
    /// Notifies all registered observers with the current value
    public func notifyObservers() {
        let currentValue = syncQueue.sync { _value }
        notifySubscribersWithValue(currentValue)
    }
    
    /// Removes a subscriber
    /// - Parameter id: The UUID returned from the subscribe method
    public func unsubscribe(_ id: UUID) {
        syncQueue.sync(flags: .barrier) {
            if let index = subscribers.firstIndex(where: { $0.id == id }) {
                // Cancel any pending notifications before removing
                subscribers[index].cancelPendingDebounceNotifications()
                subscribers.remove(at: index)
            }
        }
    }
    
    /// Removes all subscribers
    public func removeAllSubscribers() {
        syncQueue.sync(flags: .barrier) {
            // Cancel pending notifications for all subscribers
            for subscriber in subscribers {
                subscriber.cancelPendingDebounceNotifications()
            }
            subscribers.removeAll()
        }
    }
    
    /// Updates the value and optionally notifies subscribers
    /// - Parameters:
    ///   - newValue: The new value to set
    ///   - notify: Whether to notify subscribers about this change
    public func setValue(_ newValue: T, notify: Bool = true) {
        syncQueue.sync(flags: .barrier) {
            // Update notification preference
            shouldNotifySubscribers = notify
            
            // Update the backing variable
            _value = newValue
            
            // Handle notification based on batch state and notification preference
            if isBatchUpdating && shouldNotifySubscribers {
                // In batch mode, mark that a notification will be needed when batch ends
                hasPendingNotification = true
            }
            else if !isBatchUpdating && shouldNotifySubscribers {
                // Not in batch mode and notifications enabled, notify immediately
                let valueToNotify = _value
                
                // Dispatch asynchronously to avoid blocking
                DispatchQueue.global().async {
                    self.notifySubscribersWithValue(valueToNotify)
                }
            }
            // In all other cases (notify=false), do nothing
        }
    }
    
    /// Begins a batch update session, temporarily suspending notifications
    public func beginUpdates() {
        syncQueue.sync(flags: .barrier) {
            isBatchUpdating = true
            hasPendingNotification = false
        }
    }
    
    /// Ends a batch update session and sends a single notification if changes occurred
    public func endUpdates() {
        syncQueue.sync(flags: .barrier) {
            isBatchUpdating = false
            if hasPendingNotification {
                hasPendingNotification = false
                let currentValue = _value
                
                // Dispatch notification asynchronously
                DispatchQueue.global().async {
                    self.notifySubscribersWithValue(currentValue)
                }
            }
        }
    }
    
    /// Notifies all subscribers with a specific value
    /// - Parameter valueToNotify: The value to send to subscribers
    private func notifySubscribersWithValue(_ valueToNotify: T) {
        syncQueue.sync {
            // Sort subscribers by priority and create a copy to avoid race conditions
            let sortedSubscribers = subscribers.sorted { $0.priority < $1.priority }
            
            // Notify each subscriber with rate limiting
            for subscription in sortedSubscribers {
                handleRateLimitedNotification(for: subscription, with: valueToNotify)
            }
        }
    }
    
    /// Throttles notifications to at most one per specified time interval.
    /// Only the first update in the interval passes through.
    ///
    /// - Parameter interval: The minimum time interval between notifications
    /// - Returns: Self for chaining
    @discardableResult
    public func throttle(for interval: TimeInterval) -> Self {
        syncQueue.sync(flags: .barrier) {
            self.nextRateLimitingType = .throttle(interval)
        }
        return self
    }
    
    /// Debounces notifications, waiting until updates pause for the specified time interval.
    /// Only sends a notification after the "quiet period" has elapsed.
    ///
    /// - Parameter interval: The time to wait after the last update before notifying
    /// - Returns: Self for chaining
    @discardableResult
    public func debounce(for interval: TimeInterval) -> Self {
        syncQueue.sync(flags: .barrier) {
            self.nextRateLimitingType = .debounce(interval)
        }
        return self
    }
    
    /// Wrapper method for value changes that handles debouncing and throttling logic
    internal func handleRateLimitedNotification(for subscription: PLSubscription<T>, with value: T) {
        switch subscription.rateLimitingType {
        case .none:
            // No rate limiting, notify directly
            subscription.notify(with: value)
            
        case .throttle(let interval):
            // Throttle: Only notify if enough time has passed since the last notification
            let now = Date()
            if let lastUpdate = subscription.lastNotificationTime, now.timeIntervalSince(lastUpdate) < interval {
                // Too soon, skip this notification
                return
            }
            
            // Update the last notification time and notify
            subscription.lastNotificationTime = now
            subscription.notify(with: value)
            
        case .debounce(let interval):
            // Debounce: Cancel any pending notification and schedule a new one
            
            // Cancel existing timer if there is one
            subscription.debounceWorkItem?.cancel()
            
            // Create a new work item for delayed execution
            let workItem = DispatchWorkItem {
                
                // Update the last notification time
                subscription.lastNotificationTime = Date()
                
                // Notify the subscriber
                subscription.notify(with: value)
                
                // Clear the work item reference
                subscription.debounceWorkItem = nil
            }
            
            // Store the work item
            subscription.debounceWorkItem = workItem
            
            // Schedule the notification after the interval
            DispatchQueue.global().asyncAfter(deadline: .now() + interval, execute: workItem)
        }
    }
}
