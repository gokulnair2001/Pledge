//
//  PLRateLimitingType.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 24/03/25.
//

import Foundation


/// Type of rate limiting to apply to notifications
public enum PLRateLimitingType {
    /// No rate limiting
    case none
    
    /// Throttle: Only allow one notification per time interval (first one passes)
    case throttle(TimeInterval)
    
    /// Debounce: Wait until updates stop for the specified interval before notifying
    case debounce(TimeInterval)
}
