//
//  PledgeTests.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 25/03/25.
//

import XCTest
@testable import Pledge

final class PledgeTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - PLObservable Tests
    
    func testBasicObservableValue() {
        // Test the basic functionality of setting and getting a value
        let observable = PLObservable("initial")
        XCTAssertEqual(observable.value, "initial")
        
        observable.setValue("updated")
        XCTAssertEqual(observable.value, "updated")
    }
    
    func testObservableNotification() {
        // Test that subscribers are notified when the value changes
        let observable = PLObservable(0)
        
        let expectation = XCTestExpectation(description: "Observer should be notified")
        var receivedValue: Int?
        
        _ = observable.subscribe { value in
            receivedValue = value
            expectation.fulfill()
        }
        
        observable.setValue(42)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedValue, 42)
    }
    
    func testMultipleObservers() {
        // Test that multiple observers are all notified
        let observable = PLObservable("test")
        
        let expectation1 = XCTestExpectation(description: "First observer notified")
        let expectation2 = XCTestExpectation(description: "Second observer notified")
        
        var firstValue: String?
        var secondValue: String?
        
        _ = observable.subscribe { value in
            firstValue = value
            expectation1.fulfill()
        }
        
        _ = observable.subscribe { value in
            secondValue = value
            expectation2.fulfill()
        }
        
        observable.setValue("updated")
        
        wait(for: [expectation1, expectation2], timeout: 1.0)
        XCTAssertEqual(firstValue, "updated")
        XCTAssertEqual(secondValue, "updated")
    }
    
    func testUnsubscribe() {
        // Test that unsubscribing prevents further notifications
        let observable = PLObservable(0)
        
        var callCount = 0
        let subscriptionId = observable.subscribe { _ in
            callCount += 1
        }
        
        observable.setValue(1)
        XCTAssertEqual(callCount, 1, "Observer should be called once")
        
        observable.unsubscribe(subscriptionId)
        observable.setValue(1)
        XCTAssertEqual(callCount, 1, "Observer should not be called after unsubscribing")
    }
    
    func testRemoveAllSubscribers() {
        // Test that removing all subscribers works
        let observable = PLObservable(0)
        
        var callCount1 = 0
        var callCount2 = 0
        
        _ = observable.subscribe { _ in callCount1 += 1 }
        _ = observable.subscribe { _ in callCount2 += 1 }
        
        observable.setValue(1)
        XCTAssertEqual(callCount1, 1)
        XCTAssertEqual(callCount2, 1)
        
        observable.removeAllSubscribers()
        
        observable.setValue(2)
        XCTAssertEqual(callCount1, 1, "No more notifications should be received")
        XCTAssertEqual(callCount2, 1, "No more notifications should be received")
    }
    
    func testBatchUpdates() {
        // Test that batch updates properly delay notifications
        let observable = PLObservable(0)
        
        var callCount = 0
        _ = observable.subscribe { _ in callCount += 1 }
        
        // First outside batch mode
        observable.setValue(1)
        XCTAssertEqual(callCount, 1, "Should notify immediately outside batch mode")
        
        // Now in batch mode
        observable.beginUpdates()
        observable.setValue(2)
        observable.setValue(3)
        observable.setValue(4)
        XCTAssertEqual(callCount, 1, "Should not notify during batch updates")
        
        observable.endUpdates()
        XCTAssertEqual(callCount, 2, "Should notify once after batch updates end")
        XCTAssertEqual(observable.value, 4, "Final value should be correct")
    }
    
    func testPriorityOrdering() {
        // Test that subscribers are notified in priority order
        let observable = PLObservable("test")
        
        var callOrder: [String] = []
        
        _ = observable.withPriority(.low).subscribe { _ in
            callOrder.append("low")
        }
        
        _ = observable.withPriority(.normal).subscribe { _ in
            callOrder.append("normal")
        }
        
        _ = observable.withPriority(.high).subscribe { _ in
            callOrder.append("high")
        }
        
        // Wait for all notifications to complete
        let expectation = XCTestExpectation(description: "All notifications complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        
        observable.setValue("updated")
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(callOrder, ["high", "normal", "low"], "Notifications should be in priority order")
    }
    
    func testThreadSafety() {
        // Test thread safety with concurrent access
        let observable = PLObservable(0)
        let expectation = XCTestExpectation(description: "All updates complete")
        expectation.expectedFulfillmentCount = 2
        
        // Subscriber to verify final value
        var finalValue = 0
        _ = observable.subscribe { value in
            finalValue = value
        }
        
        // Create a lot of concurrent writes
        let iterations = 100
        
        DispatchQueue.global().async {
            for i in 0..<iterations {
                observable.setValue(i)
            }
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            for i in iterations..<(iterations*2) {
                observable.setValue(i)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(observable.value, finalValue, "Observable value should be consistent")
        XCTAssertGreaterThanOrEqual(finalValue, iterations, "Final value should be from the last batch")
    }
    
    func testDeliveryQueue() {
        // Test that values are delivered on the specified queue
        let observable = PLObservable("test")
        let expectation = XCTestExpectation(description: "Delivered on main queue")
        
        _ = observable.deliverOnMain().subscribe { _ in
            XCTAssertTrue(Thread.isMainThread, "Should be delivered on main thread")
            expectation.fulfill()
        }
        
        // Dispatch update from background queue
        DispatchQueue.global().async {
            observable.setValue("updated")
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testThrottling() {
        // Test throttling of updates
        let observable = PLObservable(0)
        let expectation = XCTestExpectation(description: "Throttled updates")
        
        var callCount = 0
        _ = observable.throttle(for: 0.2).subscribe { _ in
            callCount += 1
            if callCount == 2 {
                expectation.fulfill()
            }
        }
        
        // Rapid updates that should be throttled
        observable.setValue(1)
        observable.setValue(2)
        observable.setValue(3)
        
        // Wait and send another update that should go through
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            observable.setValue(4)
        }
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(callCount, 2, "Should receive only first and throttled update")
    }
    
    func testDebouncing() {
        // Test debouncing of updates
        let observable = PLObservable(0)
        let expectation = XCTestExpectation(description: "Debounced updates")
        
        var receivedValues: [Int] = []
        _ = observable.debounce(for: 0.2).subscribe { value in
            receivedValues.append(value)
            if receivedValues.count == 2 {
                expectation.fulfill()
            }
        }
        
        // Initial update
        observable.setValue(1)
        
        // Rapid updates that should be debounced
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            observable.setValue(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            observable.setValue(3)
        }
        
        // Second batch after waiting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            observable.setValue(4)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            observable.setValue(5)
        }
        
        wait(for: [expectation], timeout: 1.5)
        XCTAssertEqual(receivedValues.count, 2, "Should receive only the last value from each batch")
        XCTAssertEqual(receivedValues[0], 3, "Should receive last value from first batch")
        XCTAssertEqual(receivedValues[1], 5, "Should receive last value from second batch")
    }
    
    // MARK: - PLGlobalStore Tests
    
    func testGlobalStoreBasics() {
        // Test basic functionality of the global store
        let store = PLGlobalStore.shared
        
        // Clean up from any previous tests
        store.removeAllObservables()
        
        // Test creating and retrieving observables
        let stringObs = store.string(for: "testString", defaultValue: "initial")
        XCTAssertEqual(stringObs.value, "initial")
        
        let intObs = store.integer(for: "testInt")
        XCTAssertEqual(intObs.value, 0)
        
        // Update and verify
        stringObs.setValue("updated")
        XCTAssertEqual(store.string(for: "testString").value, "updated")
        
        // Verify same instance is returned
        let sameString = store.string(for: "testString")
        XCTAssertEqual(sameString.value, "updated")
        
        // Change through one reference and verify in the other
        sameString.setValue("changed again")
        XCTAssertEqual(stringObs.value, "changed again")
    }
    
    func testGlobalStoreRemove() {
        // Test removing observables from the store
        let store = PLGlobalStore.shared
        
        // Clean up
        store.removeAllObservables()
        
        // Create observables
        let boolObs = store.boolean(for: "testBool", defaultValue: true)
        XCTAssertEqual(boolObs.value, true)
        
        // Remove specific observable
        store.removeObservable(for: "testBool")
        
        // Check that it creates a new one with default value
        let newBoolObs = store.boolean(for: "testBool")
        XCTAssertEqual(newBoolObs.value, false, "Should create new observable with default value")
    }
    
    func testGlobalStoreTypeSafety() {
        // Test type safety of the global store
        let store = PLGlobalStore.shared
        
        // Clean up
        store.removeAllObservables()
        
        // Create an integer observable
        let intObs = store.integer(for: "test", defaultValue: 42)
        
        // Try to retrieve as string - should create new observable
        let stringObs = store.string(for: "test")
        XCTAssertEqual(stringObs.value, "", "Should have default string value")
        
        // Original should be unchanged
        XCTAssertEqual(intObs.value, 42, "Original observable should be unchanged")
        
        // Change through the int observable
        intObs.setValue(100)
        
        // The string should still have its own value
        XCTAssertEqual(stringObs.value, "", "String observable should have its own value")
    }
    
    func testGlobalStoreConcurrency() {
        // Test concurrent access to the global store
        let store = PLGlobalStore.shared
        store.removeAllObservables()
        
        let expectation = XCTestExpectation(description: "All concurrent operations complete")
        expectation.expectedFulfillmentCount = 2
        
        DispatchQueue.global().async {
            for i in 0..<100 {
                let key = "key\(i)"
                let obs = store.integer(for: key, defaultValue: i)
                XCTAssertEqual(obs.value, i)
            }
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            for i in 100..<200 {
                let key = "key\(i)"
                let obs = store.string(for: key, defaultValue: "value\(i)")
                XCTAssertEqual(obs.value, "value\(i)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testGlobalStoreEventBus() {
        // Test using the global store as an event bus
        let store = PLGlobalStore.shared
        store.removeAllObservables()
        
        // Define events
        let userLoggedIn = store.boolean(for: "events.userLoggedIn")
        let dataRefreshed = store.boolean(for: "events.dataRefreshed")
        
        // Set up listeners
        let loginExpectation = XCTestExpectation(description: "Login event received")
        let refreshExpectation = XCTestExpectation(description: "Refresh event received")
        
        _ = userLoggedIn.subscribe { isLoggedIn in
            if isLoggedIn {
                loginExpectation.fulfill()
            }
        }
        
        _ = dataRefreshed.subscribe { isRefreshed in
            if isRefreshed {
                refreshExpectation.fulfill()
            }
        }
        
        // Trigger events
        userLoggedIn.setValue(true)
        dataRefreshed.setValue(true)
        
        wait(for: [loginExpectation, refreshExpectation], timeout: 1.0)
    }
}
