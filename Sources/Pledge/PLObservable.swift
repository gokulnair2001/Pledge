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
    /// Consider making this public to allow direct access to the value property
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
    
    /// Unsubscribes from all operator subscriptions when deallocating
    /// This prevents memory leaks by cleaning up subscriptions created by operators
    deinit {
        guard let subscriptions = objc_getAssociatedObject(self, &AssociatedKeys.operatorSubscriptions) as? [UUID] else {
            return
        }
        
        for subscriptionId in subscriptions {
            unsubscribe(subscriptionId)
        }
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
    /// Convenience method for UI updates that must happen on the main thread
    /// - Returns: Self for chaining
    @discardableResult
    public func deliverOnMain() -> Self {
        return deliver(on: DispatchQueue.main)
    }
    
    /// Sets the priority for the next subscription
    /// Higher priority subscribers receive notifications before lower priority ones
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
    /// - Note: The observer is immediately called with the current value upon subscription
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
    /// Useful for manually triggering updates without changing the value
    public func notifyObservers() {
        let currentValue = syncQueue.sync { _value }
        notifySubscribersWithValue(currentValue)
    }
    
    /// Removes a subscriber
    /// - Parameter id: The UUID returned from the subscribe method
    /// - Note: Safe to call even if the ID doesn't exist
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
    /// Use when you need to clean up all subscriptions at once
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
    /// - Note: This is the core method for updating the observable's value
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
    /// Use for making multiple updates efficiently without triggering intermediate notifications
    public func beginUpdates() {
        syncQueue.sync(flags: .barrier) {
            isBatchUpdating = true
            hasPendingNotification = false
        }
    }
    
    /// Ends a batch update session and sends a single notification if changes occurred
    /// Should be called after beginUpdates() to resume normal notification behavior
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
    /// - Note: Subscribers are notified in priority order
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
    /// - Note: Affects only the next subscription
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
    /// - Note: Affects only the next subscription
    @discardableResult
    public func debounce(for interval: TimeInterval) -> Self {
        syncQueue.sync(flags: .barrier) {
            self.nextRateLimitingType = .debounce(interval)
        }
        return self
    }
    
    /// Wrapper method for value changes that handles debouncing and throttling logic
    /// - Parameters:
    ///   - subscription: The subscription to notify
    ///   - value: The value to notify the subscription with
    /// - Note: This should probably be private, not internal
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


// MARK: - Transform Operations
public extension PLObservable {
    
    /// Transforms the values emitted by an observable using a provided transformation function.
    /// - Parameter transform: A closure that takes a value of type T and returns a value of type U.
    /// - Returns: A new observable that emits transformed values.
    func map<U>(_ transform: @escaping (T) -> U) -> PLObservable<U> {
        // Create a new observable with the current transformed value
        let result = PLObservable<U>(transform(self.value))
        
        // Subscribe to this observable to update the result observable
        let subscription = self.subscribe { [weak result] newValue in
            result?.setValue(transform(newValue))
        }
        
        // Store the subscription ID in the result for proper cleanup
        storeSubscriptionForOperator(id: subscription, in: result)
        
        return result
    }
    
    /// Transforms values with an asynchronous operation, capturing the result when ready.
    /// - Parameter transform: A closure that takes a value of type T and asynchronously returns a value of type U.
    /// - Returns: A new observable that emits transformed values when the async operations complete.
    func flatMap<U>(_ transform: @escaping (T) -> PLObservable<U>) -> PLObservable<U> {
        // Create the result observable with the transformed value of the current value
        let sourceTransformed = transform(self.value)
        let result = PLObservable<U>(sourceTransformed.value)
        
        // 1. Subscribe to changes in this observable
        let sourceSubscription = self.subscribe { [weak result, weak sourceTransformed] newValue in
            // When source changes, we get the new transformed observable
            guard let result = result else { return }
            let newTransformed = transform(newValue)
            
            // Update internal state
            withExtendedLifetime(sourceTransformed) { _ in
                // Ensure previous sourceTransformed remains alive until here
            }
            
            // Set initial value and subscribe to the new transformed observable
            result.setValue(newTransformed.value)
            
            // We could track and manage these subscriptions, but for simplicity
            // we're letting them be reclaimed when newTransformed is deallocated
            _ = newTransformed.subscribe { [weak result] transformedValue in
                result?.setValue(transformedValue)
            }
        }
        
        // 2. Also subscribe to the initial transformed observable
        let initialTransformSubscription = sourceTransformed.subscribe { [weak result] transformedValue in
            result?.setValue(transformedValue)
        }
        
        // Store the subscription IDs for proper cleanup
        storeSubscriptionForOperator(id: sourceSubscription, in: result)
        storeSubscriptionForOperator(id: initialTransformSubscription, in: result)
        
        return result
    }
    
    /// Unwraps optional values from an observable, only emitting non-nil values.
    /// - Returns: A new observable that emits non-nil values.
    func compactMap<U>() -> PLObservable<U> where T == U? {
        // Create a new observable with the unwrapped value, if available
        let initialValue: U
        if let unwrapped = self.value {
            initialValue = unwrapped
        } else {
            // This is a bit of a hack - we need a valid initial value
            // This will throw if there's never a non-nil value
            fatalError("Cannot create compactMap observable from a nil initial value")
        }
        
        let result = PLObservable<U>(initialValue)
        
        // Subscribe to this observable to update the result observable
        let subscription = self.subscribe { [weak result] newValue in
            if let unwrapped = newValue {
                result?.setValue(unwrapped)
            }
        }
        
        storeSubscriptionForOperator(id: subscription, in: result)
        
        return result
    }
}

// MARK: - Filter Operations
public extension PLObservable {
    
    /// Creates a new observable that only emits values that satisfy the given predicate.
    /// - Parameter isIncluded: A closure that takes a value of type T and returns a Boolean indicating whether to include the value.
    /// - Returns: A new observable that only emits values that satisfy the predicate.
    func filter(_ isIncluded: @escaping (T) -> Bool) -> PLObservable<T> {
        
        let result = PLObservable<T>(self.value)
        
        // Subscribe to this observable to conditionally update the result observable
        let subscription = self.subscribe { [weak result] newValue in
            if isIncluded(newValue) {
                result?.setValue(newValue)
            }
        }
        
        storeSubscriptionForOperator(id: subscription, in: result)
        
        return result
    }
    
    /// Creates a new observable that skips the first n emissions.
    /// - Parameter count: The number of emissions to skip.
    /// - Returns: A new observable that skips the first n emissions.
    func skip(_ count: Int) -> PLObservable<T> {
        let result = PLObservable<T>(self.value)
        
        var skipped = 0
        let subscription = self.subscribe { [weak result] newValue in
            if skipped >= count {
                result?.setValue(newValue)
            } else {
                skipped += 1
            }
        }
        
        storeSubscriptionForOperator(id: subscription, in: result)
        
        return result
    }
    
    /// Creates a new observable that only emits values that are distinct from the previous value.
    /// - Parameter areEqual: A closure that takes two values of type T and returns a Boolean indicating whether they are equal.
    /// - Returns: A new observable that only emits values that are distinct from the previous value.
    func distinctUntilChanged(by areEqual: @escaping (T, T) -> Bool) -> PLObservable<T> {
        let result = PLObservable<T>(self.value)
        
        var lastValue = self.value
        let subscription = self.subscribe { [weak result] newValue in
            if !areEqual(lastValue, newValue) {
                lastValue = newValue
                result?.setValue(newValue)
            }
        }
        
        storeSubscriptionForOperator(id: subscription, in: result)
        
        return result
    }
    
    /// Creates a new observable that only emits values that are distinct from the previous value.
    /// This version uses Equatable for the comparison.
    /// - Returns: A new observable that only emits values that are distinct from the previous value.
    func distinctUntilChanged() -> PLObservable<T> where T: Equatable {
        distinctUntilChanged(by: ==)
    }
}

// MARK: - Combine Operations
public extension PLObservable {
    
    /// Merges this observable with another observable of the same type.
    /// The resulting observable emits a value whenever either source observable emits a value.
    /// - Parameter other: Another observable of the same type to merge with this one.
    /// - Returns: A new observable that emits values from both source observables.
    func merge(_ other: PLObservable<T>) -> PLObservable<T> {
        let result = PLObservable<T>(self.value)
        
        let subscription1 = self.subscribe { [weak result] newValue in
            result?.setValue(newValue)
        }
        
        let subscription2 = other.subscribe { [weak result] newValue in
            result?.setValue(newValue)
        }
        
        storeSubscriptionForOperator(id: subscription1, in: result)
        storeSubscriptionForOperator(id: subscription2, in: result)
        
        return result
    }
    
    /// Zips values from two observables, emitting pairs of values when both observables have produced a new value.
    /// - Parameter other: Another observable to zip with this one.
    /// - Returns: A new observable that emits pairs of values.
    func zip<U>(_ other: PLObservable<U>) -> PLObservable<(T, U)> {
        let result = PLObservable<(T, U)>((self.value, other.value))
        
        // These queues store values waiting to be paired
        var selfQueue: [T] = []
        var otherQueue: [U] = []
        
        // A queue to synchronize access
        let syncQueue = DispatchQueue(label: "com.pledge.zip.sync")
        
        let processQueues = { [weak result] in
            // If we have at least one value in each queue, emit a pair
            if !selfQueue.isEmpty && !otherQueue.isEmpty {
                let selfValue = selfQueue.removeFirst()
                let otherValue = otherQueue.removeFirst()
                result?.setValue((selfValue, otherValue))
            }
        }
        
        let subscription1 = self.subscribe { newValue in
            syncQueue.sync {
                selfQueue.append(newValue)
                processQueues()
            }
        }
        
        let subscription2 = other.subscribe { newValue in
            syncQueue.sync {
                otherQueue.append(newValue)
                processQueues()
            }
        }
        
        storeSubscriptionForOperator(id: subscription1, in: result)
        storeSubscriptionForOperator(id: subscription2, in: result)
        
        return result
    }
}

// MARK: - Subscription Management
private extension PLObservable {
    /// Stores the subscription ID in the associated object for proper cleanup
    /// - Parameters:
    ///   - id: The subscription ID to store
    ///   - observable: The observable to associate the subscription with
    func storeSubscriptionForOperator<U>(id: UUID, in observable: PLObservable<U>?) {
        guard let observable = observable else { return }
        
        // Use associated objects to store subscription IDs
        let subscriptions = getOperatorSubscriptions(from: observable) ?? []
        setOperatorSubscriptions(subscriptions + [id], for: observable)
    }
    
    /// Gets the operator subscriptions from an observable
    /// - Parameter observable: The observable to get subscriptions from
    /// - Returns: An array of subscription IDs
    func getOperatorSubscriptions<U>(from observable: PLObservable<U>) -> [UUID]? {
        objc_getAssociatedObject(observable, &AssociatedKeys.operatorSubscriptions) as? [UUID]
    }
    
    /// Sets the operator subscriptions for an observable
    /// - Parameters:
    ///   - subscriptions: The subscription IDs to store
    ///   - observable: The observable to associate the subscriptions with
    func setOperatorSubscriptions<U>(_ subscriptions: [UUID], for observable: PLObservable<U>) {
        objc_setAssociatedObject(
            observable,
            &AssociatedKeys.operatorSubscriptions,
            subscriptions,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

public extension PLObservable where T == Result<Any, Error> {
    
    /// Maps the success value of the observable to a new value of type U.
    /// - Parameter transform: A closure that transforms the success value.
    /// - Returns: A new observable with the transformed success value.
    func mapSuccess<U>(_ transform: @escaping (Any) -> U) -> PLObservable<Result<U, Error>> {
        return self.map { result in
            switch result {
            case .success(let value):
                return .success(transform(value))
            case .failure(let error):
                return .failure(error)
            }
        }
    }
    
    /// Maps the error value of the observable to a new error of type E.
    /// - Parameter transform: A closure that transforms the error value.
    /// - Returns: A new observable with the transformed error value.
    func mapError<E>(_ transform: @escaping (Error) -> E) -> PLObservable<Result<Any, E>> {
        return self.map { result in
            switch result {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                return .failure(transform(error))
            }
        }
    }
    
    /// Flat maps the success value of the observable to a new observable.
    /// - Parameter transform: A closure that transforms the success value into a new observable.
    /// - Returns: A new observable that is the result of flat mapping the success value.
    func flatMapSuccess<U>(_ transform: @escaping (Any) -> PLObservable<Result<U, Error>>) -> PLObservable<Result<U, Error>> {
        return self.flatMap { result -> PLObservable<Result<U, Error>> in
            switch result {
            case .success(let value):
                return transform(value)
            case .failure(let error):
                return PLObservable<Result<U, Error>>(.failure(error))
            }
        }
    }
    
    /// Creates a new observable with a success value of type U.
    /// - Parameter value: The value to be wrapped in a success result.
    /// - Returns: A new observable with the given success value.
    static func success<U, E: Error>(_ value: U) -> PLObservable<Result<U, E>> {
        return PLObservable<Result<U, E>>(.success(value))
    }
    
    /// Creates a new observable with a failure value of type E.
    /// - Parameter error: The error to be wrapped in a failure result.
    /// - Returns: A new observable with the given failure value.
    static func failure<U, E: Error>(_ error: E) -> PLObservable<Result<U, E>> {
        return PLObservable<Result<U, E>>(.failure(error))
    }
    
}


// Keys for associated objects
/// Storage for associated object keys - consider making these private
private struct AssociatedKeys {
    static var operatorSubscriptions: UInt8 = 0
}
