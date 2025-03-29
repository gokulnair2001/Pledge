//
//  PledgeTests.swift
//  Pledge
//
//  Created by Gokul Nair(Work) on 27/03/25.
//

import XCTest
@testable import Pledge

final class PledgeTests: XCTestCase {
    
    
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
    
   
}
