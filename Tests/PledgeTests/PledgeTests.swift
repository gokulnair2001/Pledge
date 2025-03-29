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

}
