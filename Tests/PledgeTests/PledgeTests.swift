//
//  PledgeTests.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 27/03/25.
//

import XCTest
@testable import Pledge

final class PledgeTests: XCTestCase {
    
    func testDefaultValueSubscription() {
        
        let observable = PLObservable<Int>(0)
        var receivedValues: [Int] = []
        let expectation = XCTestExpectation(description: "Default value subscribed")
        
        _ = observable.throttle(for: 0.1).subscribe { value in
            receivedValues.append(value)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedValues, [0], "Default value must be subscribed automatically")
    }
    
    // MARK: - Basic Observable Tests
    func testBasicObservableSubscription() {
        let observable = PLObservable<Int>(5)
        var receivedValue = 0 {
            didSet {
                print("Value set: \(receivedValue)")
            }
        }
        
        let initialExpectation = XCTestExpectation(description: "Observer should be notified with initial value")
        let updatedExpectation = XCTestExpectation(description: "Observer should be notified with updated value")
        
        _ = observable.subscribe { value in
            DispatchQueue.main.async {
                receivedValue = value
                if value == 5 {
                    initialExpectation.fulfill()
                } else if value == 10 {
                    updatedExpectation.fulfill()
                }
            }
        }
        
        wait(for: [initialExpectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, 5, "Observer should receive initial value")
        
        observable.setValue(10)
        wait(for: [updatedExpectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, 10, "Observer should receive updated value")
    }

    func testMultipleSubscribers() {
        let observable = PLObservable<String>("initial")
        var receivedUpdates: [String] = []
        
        let initialExpectation = XCTestExpectation(description: "All subscribers should receive the initial value")
        let updatedExpectation = XCTestExpectation(description: "All subscribers should receive the updated value")
        
        for _ in 1...5 {
            _ = observable.subscribe { value in
                DispatchQueue.main.async {
                    receivedUpdates.append(value)
                    
                    if receivedUpdates.filter({ $0 == "initial" }).count == 5 {
                        initialExpectation.fulfill()
                    } else if receivedUpdates.filter({ $0 == "updated" }).count == 5 {
                        updatedExpectation.fulfill()
                    }
                }
            }
        }
        
        wait(for: [initialExpectation], timeout: 1.0)
        XCTAssertEqual(receivedUpdates.count, 5)
        XCTAssertEqual(receivedUpdates, Array(repeating: "initial", count: 5))
        
        receivedUpdates.removeAll()
        
        observable.setValue("updated")
        
        wait(for: [updatedExpectation], timeout: 1.0)
        XCTAssertEqual(receivedUpdates.count, 5)
        XCTAssertEqual(receivedUpdates, Array(repeating: "updated", count: 5))
    }

    
    func testUnsubscribe() {
        let observable = PLObservable<Int>(0)
        var count1 = 0
        var count2 = 0
        
        let expectation1 = XCTestExpectation(description: "First observer should receive initial value")
        let expectation2 = XCTestExpectation(description: "Second observer should receive initial value")
        let updateExpectation = XCTestExpectation(description: "Only the second observer should receive update")
        
        let subscription1 = observable.subscribe { _ in
            count1 += 1
            if count1 == 1 { expectation1.fulfill() }
        }
        
        observable.subscribe { _ in
            count2 += 1
            if count2 == 1 { expectation2.fulfill() }
            else if count2 == 2 { updateExpectation.fulfill() }
        }
        
        wait(for: [expectation1, expectation2], timeout: 1.0)
        
        XCTAssertEqual(count1, 1, "First observer should have received the initial value")
        XCTAssertEqual(count2, 1, "Second observer should have received the initial value")
        
        // Unsubscribe first observer
        observable.unsubscribe(subscription1)
        
        // Update the value
        observable.setValue(1)
        
        wait(for: [updateExpectation], timeout: 1.0) 
        
        XCTAssertEqual(count1, 1, "Unsubscribed observer should not receive updates")
        XCTAssertEqual(count2, 2, "Subscribed observer should continue receiving updates")
    }

    func testRemoveAllSubscribers() {
        let observable = PLObservable<Int>(0)
        var count = 0
        
        _ = observable.subscribe { _ in count += 1 }
        _ = observable.subscribe { _ in count += 1 }
        
        // Both subscribers notified of initial value
        XCTAssertEqual(count, 2)
        
        observable.removeAllSubscribers()
        
        // Update value
        observable.setValue(1)
        
        // Count should not increase
        XCTAssertEqual(count, 2, "No subscribers should be notified after removeAllSubscribers")
    }
    
    // MARK: - Batch Updates Tests
    
    func testBatchUpdates() {
        let observable = PLObservable<Int>(0)
        var notificationCount = 0
        
        let expectation1 = XCTestExpectation(description: "Initial Observer triggered")
        let expectation2 = XCTestExpectation(description: "Observer triggered after batch update")
        
        _ = observable.subscribe { value in
            notificationCount += 1
            if value == 0 {
                expectation1.fulfill()
            } else if value == 3 {
                expectation2.fulfill()
            }
        }
        
        wait(for: [expectation1], timeout: 1)
        // Initial notification
        XCTAssertEqual(notificationCount, 1)
        
        // Begin batch updates
        observable.beginUpdates()
        
        // Multiple updates during batch
        observable.setValue(1)
        observable.setValue(2)
        observable.setValue(3)
        
        // No additional notifications should have occurred
        XCTAssertEqual(notificationCount, 1, "No notifications should occur during batch updates")
        
        // End batch updates
        observable.endUpdates()
        
        wait(for: [expectation2], timeout: 1)
        // Should receive just one more notification
        XCTAssertEqual(notificationCount, 2, "Only one notification should occur after batch updates")
    }
    
    // MARK: - Queue and Priority Tests
    func testDeliveryQueue() {
        let observable = PLObservable<Int>(0)
        let expectation = XCTestExpectation(description: "Delivery on specific queue")
        
        let customQueue = DispatchQueue(label: "com.test.customQueue")
        let key = DispatchSpecificKey<String>()
        customQueue.setSpecific(key: key, value: "customQueue")
        
        _ = observable.deliver(on: customQueue).subscribe { _ in
            let value = DispatchQueue.getSpecific(key: key)
            XCTAssertEqual(value, "customQueue", "Handler should be called on the custom queue")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMainQueueDelivery() {
        let observable = PLObservable<Int>(0)
        let expectation = XCTestExpectation(description: "Delivery on main queue")
        
        _ = observable.deliverOnMain().subscribe { _ in
            XCTAssertTrue(Thread.isMainThread, "Handler should be called on the main thread")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testObserverPriority() {
        let observable = PLObservable<Int>(0)
        var order: [String] = []
        
        let expectation1 = XCTestExpectation(description: "Low priority observable triggered")
        let expectation2 = XCTestExpectation(description: "Normal priority observable triggered")
        let expectation3 = XCTestExpectation(description: "High priority observable triggered")
        
        _ = observable.withPriority(.low).subscribe { _ in
            order.append("low")
            expectation1.fulfill()
        }
        
        _ = observable.withPriority(.normal).subscribe { _ in
            order.append("normal")
            expectation2.fulfill()
        }
        
        _ = observable.withPriority(.high).subscribe { _ in
            order.append("high")
            expectation3.fulfill()
        }
        
        // Clear initial notifications
        order.removeAll()
        
        // Trigger notifications
        observable.setValue(1)
        
        wait(for: [expectation1, expectation2, expectation3], timeout: 1)
        // Priorities should be respected in notification order
        XCTAssertEqual(order, ["high", "normal", "low"], "Notifications should occur in priority order")
    }
    
    // MARK: - Rate Limiting Tests
    func testThrottle() {
        let observable = PLObservable<Int>(0)
        var receivedValues: [Int] = []
        let expectation = XCTestExpectation(description: "Throttled values")
        
        _ = observable.throttle(for: 1).subscribe { value in
            receivedValues.append(value)
            print("recev: \(receivedValues)")
            // Ensure we get at least 3 valid emissions (O - Default, 1-Set value, 4 - Set after throttle
            if receivedValues.count >= 3 {
                expectation.fulfill()
            }
        }
        
        // Initial value (should be received immediately)
        observable.setValue(1)
        
        // Delay updates to ensure they fall within the throttle window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            observable.setValue(2)  // This should be throttled
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            observable.setValue(3)  // This should also be throttled
        }
        
        // This value comes after 200ms, should be received
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            observable.setValue(4)
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        // Ensuring that only allowed values are received
        XCTAssertEqual(receivedValues, [0, 1, 4], "Only non-throttled values should be received")
    }

    func testDebounce() {
        let observable = PLObservable<Int>(0)
        var receivedValues: [Int] = []
        let expectation = XCTestExpectation(description: "Debounced values")
        
        _ = observable.debounce(for: 0.1).subscribe { value in
            receivedValues.append(value)
            if value == 3 {
                expectation.fulfill()
            }
        }
        
        // Initial notification (this should always happen)
        XCTAssertEqual(receivedValues, [0])
        
        // Rapid sequence of updates within debounce window
        observable.setValue(1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            observable.setValue(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            observable.setValue(3)
        }
        
        // Wait longer than debounce period to allow last value to be emitted
        wait(for: [expectation], timeout: 0.3)
        
        // Expected: Only [0, 3] (if debounce is working correctly)
        XCTAssertEqual(receivedValues, [0, 3], "Only debounced values should be received")
    }

    // MARK: - Operator Tests
    
    func testMapOperator() {
        let observable = PLObservable<Int>(5)
        let mappedObservable = observable.map { value in "Number: \(value)" }
        
        let expectation = XCTestExpectation(description: "Updated and mapped the new value")
        
        var result = ""
        _ = mappedObservable.subscribe { value in
            result = value
            if value == "Number: 10" {
                expectation.fulfill()
            }
        }
        
        XCTAssertEqual(result, "Number: 5")
        
        observable.setValue(10)
        
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(result, "Number: 10")
    }
    
    func testCompactMapOperator() {
        // Create a safe implementation for testing
        let observable = PLObservable<Int?>(5)
        let mappedObservable = observable.compactMap()
        
        let expectation = XCTestExpectation(description: "Updated and mapped the new value")
        
        var result = 0
        mappedObservable.subscribe { value in
            result = value
            if value == 10 {
                expectation.fulfill()
            }
        }
        
        XCTAssertEqual(result, 5)
        
        observable.setValue(nil)
        XCTAssertEqual(result, 5, "Nil values should be ignored")
        
        observable.setValue(10)
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(result, 10, "Non-nil values should be emitted")
    }
    
    func testFilterOperator() {
        let observable = PLObservable<Int>(5)
        let filteredObservable = observable.filter { $0 % 2 == 0 }
        
        let expectation2 = XCTestExpectation(description: "Filtered with value 2")
        let expectation4 = XCTestExpectation(description: "Filtered with value 4")

        var receivedValues: [Int] = []
        
        _ = filteredObservable.subscribe { value in
            receivedValues.append(value)
            if value == 2 {
                expectation2.fulfill()
            } else if value == 4 {
                expectation4.fulfill()
            }
        }

        // `5` should NOT be received, so no need to assert here

        observable.setValue(2)
        wait(for: [expectation2], timeout: 1)
        XCTAssertEqual(receivedValues, [5, 2], "Only even numbers should be received")

        observable.setValue(3) // This should be filtered out
        XCTAssertEqual(receivedValues, [5, 2], "Filtered out values should not be observed")

        observable.setValue(4)
        wait(for: [expectation4], timeout: 1)
        XCTAssertEqual(receivedValues, [5, 2, 4], "Only even numbers should be received")
    }

    
    func testDistinctUntilChangedOperator() {
        let observable = PLObservable<Int>(1)
        let distinctObservable = observable.distinctUntilChanged()
        
        var receivedValues: [Int] = []
        let expectation = XCTestExpectation(description: "Should receive distinct values")
        
        distinctObservable.subscribe { value in
            receivedValues.append(value)
            
            if receivedValues == [1, 2] {
                expectation.fulfill() // Expecting only distinct values
            }
        }
        
        // Initial value should be received
        XCTAssertEqual(receivedValues, [1])
        
        // Set identical value (should NOT trigger)
        observable.setValue(1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(receivedValues, [1], "Identical values should not trigger notification")
        }
        
        // Set a new distinct value (should trigger)
        observable.setValue(2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(receivedValues, [1, 2])
        }
        
        // Set identical value again (should NOT trigger)
        observable.setValue(2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertEqual(receivedValues, [1, 2], "Identical values should not trigger notification")
        }
        
        wait(for: [expectation], timeout: 1.0)
    }

    
    // MARK: - Global Store Tests
    
    func testGlobalStore() {
        let store = PLGlobalStore.shared
        
        // Test integer observable
        let intObs = store.integer(for: "test-int", defaultValue: 5)
        var intValue = 0
        _ = intObs.subscribe { value in
            intValue = value
        }
        XCTAssertEqual(intValue, 5)
        
        // Test string observable
        let stringObs = store.string(for: "test-string", defaultValue: "hello")
        var stringValue = ""
        _ = stringObs.subscribe { value in
            stringValue = value
        }
        XCTAssertEqual(stringValue, "hello")
        
        // Test retrieval of existing observable
        let sameIntObs = store.integer(for: "test-int")
        XCTAssertEqual(sameIntObs.value, 5)
        
        // Update through one reference should update the other
        intObs.setValue(10)
        XCTAssertEqual(sameIntObs.value, 10)
        
        // Test removing observable
        store.removeObservable(for: "test-int")
        let newIntObs = store.integer(for: "test-int", defaultValue: 15)
        XCTAssertEqual(newIntObs.value, 15, "New observable should be created with default value")
        
        // Test removeAll
        store.removeAllObservables()
        let newStringObs = store.string(for: "test-string", defaultValue: "reset")
        XCTAssertEqual(newStringObs.value, "reset", "New observable should be created with default value")
    }
}
