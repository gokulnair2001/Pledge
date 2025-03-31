
![PledgeBanner](https://github.com/user-attachments/assets/f1faaf4f-d6ee-4560-956d-b09b5c9c4aef)

# Pledge 
A thoughtfully designed reactive programming framework.

Pledge is a lightweight, thread-safe reactive programming framework for Swift that simplifies state management, event propagation and balances power with simplicity in your applications. While other frameworks force you to learn complex concepts and operators, Pledge focuses on solving the real problems developers face daily:

## Overview

Pledge provides a clean, flexible way to implement the observer pattern in Swift applications. It enables you to create observable values that notify subscribers of changes, with powerful features like:

- Thread-safe implementation
- Priority-based notifications
- Customizable delivery queues
- Batch updates
- Rate limiting (throttling and debouncing)
- Functional operators (map, filter, etc.)
- Global state management

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/gokulnair2001/Pledge.git", from: "1.0.0")
]
```

## Core Components

### PLObservable

`PLObservable` is the heart of Pledge, representing a thread-safe container for a value that can be observed for changes.

```swift
// Create an observable string
let messageObservable = PLObservable("Hello")

// Subscribe to changes
let subscription = messageObservable.subscribe { newMessage in
    print("Message changed to: \(newMessage)")
}

// Update the value
messageObservable.setValue("Hello World")
```

### PLGlobalStore

`PLGlobalStore` provides a centralized repository for observables, acting as a lightweight state management solution.

```swift
// Access shared instance
let store = PLGlobalStore.shared

// Get or create an observable
let userNameObservable = store.string(for: "userName", defaultValue: "Guest")

// Subscribe to changes
userNameObservable.subscribe { name in
    print("User name is now: \(name)")
}

// Update from anywhere in your app
PLGlobalStore.shared.string(for: "userName").setValue("John")
```

## How Observables Work

![HOW](https://github.com/user-attachments/assets/c395d778-3c09-4219-a03a-fa98753b33ca)

The diagram above illustrates the flow of data in Pledge:

1. An observable holds a value and maintains a list of subscribers
2. When the value changes, all subscribers are notified in priority order
3. Subscribers can perform transformers and specify delivery queues for thread-safety
4. Optional rate limiting can control notification frequency

## API Reference

### PLObservable

#### Creating an Observable

```swift
// Initialize with a value
let counter = PLObservable(0)
let isEnabled = PLObservable(true)
let userData = PLObservable(["name": "Guest", "role": "User"])
```

#### Subscribing to Changes

```swift
// Basic subscription
let subscription = observable.subscribe { newValue in
    print("Value changed to: \(newValue)")
}

// Unsubscribe when no longer needed
observable.unsubscribe(subscription)

// Remove all subscribers
observable.removeAllSubscribers()
```

#### Controlling Delivery

```swift
// Deliver on a specific queue
observable.deliver(on: myCustomQueue).subscribe { value in
    // This closure runs on myCustomQueue
}

// Deliver on the main queue
observable.deliverOnMain().subscribe { value in
    // This closure runs on the main queue
}

// Set subscription priority
observable.withPriority(.high).subscribe { value in
    // High priority subscribers are notified first
}
```

#### Modifying Values

```swift
// Set a new value and notify subscribers
observable.setValue(newValue)

// Set a value without notification
observable.setValue(newValue, notify: false)

// Trigger notification with current value
observable.notifyObservers()
```

#### Batch Updates

```swift
// Begin batch updates
observable.beginUpdates()

// Make multiple changes
observable.setValue(1)
observable.setValue(2)
observable.setValue(3)

// End batch updates - only sends one notification
observable.endUpdates()
```

#### Rate Limiting

```swift
// Throttle: limit to one notification per 0.5 seconds
observable.throttle(for: 0.5).subscribe { value in
    // Called at most once per 0.5 seconds
}

// Debounce: wait until updates pause for 0.3 seconds
observable.debounce(for: 0.3).subscribe { value in
    // Called after 0.3 seconds of no updates
}
```

### Operators

#### Transformation

```swift
// Map values to a different type
let stringCounter = counter.map { "Count: \($0)" }

// Flat-map to another observable
let userDetails = userIdObservable.flatMap { userId in
    return fetchUserDetails(userId)
}

// Unwrap optional values
let optionalValue = PLObservable<String?>("test")
let unwrapped = optionalValue.compactMap()
```

#### Filtering

```swift
// Only emit values that pass a predicate
let evenNumbers = counter.filter { $0 % 2 == 0 }

// Skip the first N emissions
let skipFirst = counter.skip(2)

// Only emit when value changes
let distinct = values.distinctUntilChanged()
```

#### Combining

```swift
// Merge two observables of the same type
let allEvents = userEvents.merge(systemEvents)

// Combine latest values from two observables
let credentials = username.zip(password)
```

### PLGlobalStore

```swift
// Get/create typed observables
let counter = PLGlobalStore.shared.integer(for: "counter")
let userName = PLGlobalStore.shared.string(for: "userName")
let settings = PLGlobalStore.shared.dictionary(for: "settings")
let items = PLGlobalStore.shared.array(for: "items")
let isEnabled = PLGlobalStore.shared.boolean(for: "isEnabled")

// Remove specific observable
PLGlobalStore.shared.removeObservable(for: "counter")

// Clear all observables
PLGlobalStore.shared.removeAllObservables()
```

## Usage Examples

### Form Validation

```swift
let username = PLObservable("")
let password = PLObservable("")
let isFormValid = PLObservable(false)

// Create derived state
let isUsernameValid = username.map { $0.count >= 3 }
let isPasswordValid = password.map { $0.count >= 8 }

// Combine validations
isUsernameValid.subscribe { usernameValid in
    isPasswordValid.subscribe { passwordValid in
        isFormValid.setValue(usernameValid && passwordValid)
    }
}

// React to form validity
isFormValid.subscribe { valid in
    submitButton.isEnabled = valid
}
```

### Network State Management

```swift
enum NetworkState {
    case idle, loading, success(Data), error(Error)
}

let networkState = PLObservable<NetworkState>(.idle)

// Handle different states
networkState.subscribe { state in
    switch state {
    case .idle:
        // Hide indicators
    case .loading:
        // Show loading spinner
    case .success(let data):
        // Update UI with data
    case .error(let error):
        // Show error message
    }
}

// Function to load data
func fetchData() {
    networkState.setValue(.loading)
    
    apiClient.fetchData { result in
        switch result {
        case .success(let data):
            networkState.setValue(.success(data))
        case .failure(let error):
            networkState.setValue(.error(error))
        }
    }
}
```

### Throttled Search

```swift
let searchQuery = PLObservable("")

// Throttle to avoid excessive API calls
searchQuery.throttle(for: 0.3).subscribe { query in
    if !query.isEmpty {
        performSearch(query)
    }
}
```

## License

Pledge is available under the MIT license. See the LICENSE [file](https://github.com/gokulnair2001/Pledge?tab=MIT-1-ov-file#readme) for more info.
