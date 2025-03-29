//
//  PLGlobalStore.swift
//  Pledge
//
//  Created by Gokul Nair on 24/03/25.
//

import Foundation


/// A global store that acts as a lightweight event bus using PLObservable
public final class PLGlobalStore {
    /// Shared singleton instance
    public static let shared = PLGlobalStore()
    
    /// Private initializer to enforce singleton pattern
    private init() {}
    
    /// Dictionary to store observables by their keys
    private var observables: [String: Any] = [:]
    
    /// Thread-safe access to observables
    /// Uses a concurrent queue with barrier flags for write operations
    private let syncQueue = DispatchQueue(label: "com.pledge.globalstore", attributes: .concurrent)
    
    /// Creates or retrieves an observable for a given key
    /// - Parameters:
    ///   - key: The unique identifier for the observable
    ///   - defaultValue: The initial value if the observable doesn't exist
    /// - Returns: A PLObservable instance for the given key
    /// - Note: Thread-safe implementation using barrier flags for write operations
    public func observable<T>(for key: String, defaultValue: T) -> PLObservable<T> {
        return syncQueue.sync(flags: .barrier) {
            // Return existing observable if one exists for this key and type
            if let existing = observables[key] as? PLObservable<T> {
                return existing
            }
            
            // Create a new observable with the default value if none exists
            let observable = PLObservable(defaultValue)
            observables[key] = observable
            return observable
        }
    }
    
    /// Removes an observable from the store
    /// - Parameter key: The key of the observable to remove
    /// - Note: Uses weak self to prevent retain cycles
    public func removeObservable(for key: String) {
        syncQueue.sync(flags: .barrier) { [weak self] () -> Void in
            self?.observables.removeValue(forKey: key)
        }
    }
    
    /// Removes all observables from the store
    /// - Note: Use with caution as this clears all observables
    public func removeAllObservables() {
        syncQueue.sync(flags: .barrier) { [weak self] () -> Void in
            self?.observables.removeAll()
        }
    }
}

// MARK: - Convenience Methods
public extension PLGlobalStore {
    /// Creates or retrieves a string observable
    /// - Parameters:
    ///   - key: The unique identifier for the observable
    ///   - defaultValue: The initial value (defaults to empty string)
    /// - Returns: A PLObservable<String> instance
    func string(for key: String, defaultValue: String = "") -> PLObservable<String> {
        return observable(for: key, defaultValue: defaultValue)
    }
    
    /// Creates or retrieves an integer observable
    /// - Parameters:
    ///   - key: The unique identifier for the observable
    ///   - defaultValue: The initial value (defaults to 0)
    /// - Returns: A PLObservable<Int> instance
    func integer(for key: String, defaultValue: Int = 0) -> PLObservable<Int> {
        return observable(for: key, defaultValue: defaultValue)
    }
    
    /// Creates or retrieves a boolean observable
    /// - Parameters:
    ///   - key: The unique identifier for the observable
    ///   - defaultValue: The initial value (defaults to false)
    /// - Returns: A PLObservable<Bool> instance
    func boolean(for key: String, defaultValue: Bool = false) -> PLObservable<Bool> {
        return observable(for: key, defaultValue: defaultValue)
    }
    
    /// Creates or retrieves a dictionary observable
    /// - Parameters:
    ///   - key: The unique identifier for the observable
    ///   - defaultValue: The initial value (defaults to empty dictionary)
    /// - Returns: A PLObservable<[String: Any]> instance
    func dictionary(for key: String, defaultValue: [String: Any] = [:]) -> PLObservable<[String: Any]> {
        return observable(for: key, defaultValue: defaultValue)
    }
    
    /// Creates or retrieves an array observable
    /// - Parameters:
    ///   - key: The unique identifier for the observable
    ///   - defaultValue: The initial value (defaults to empty array)
    /// - Returns: A PLObservable<[Any]> instance
    func array(for key: String, defaultValue: [Any] = []) -> PLObservable<[Any]> {
        return observable(for: key, defaultValue: defaultValue)
    }
} 
