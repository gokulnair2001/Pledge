//
//  PLObserverPriority.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 24/03/25.
//

import Foundation


/// Defines the priority level for observers
public enum PLObserverPriority: Int, Comparable {
    /// Critical priority - notified first (logging, validation)
    case high = 0
    
    /// Standard priority - notified after high priority (default)
    case normal = 500
    
    /// Low priority - notified last (non-critical updates)
    case low = 1000
    
    /// Allow sorting by priority
    public static func < (lhs: PLObserverPriority, rhs: PLObserverPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
