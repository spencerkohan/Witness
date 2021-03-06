//
//  WitnessTests.swift
//  WitnessTests
//
//  Created by Niels de Hoog on 23/09/15.
//  Copyright © 2015 Invisible Pixel. All rights reserved.
//

import XCTest
@testable import Witness
import Dispatch

class WitnessTests: XCTestCase {
    static let expectationTimeout = 2.0
    static let latency: TimeInterval = 0.1
    
    let fileManager = FileManager()
    var witness: Witness?
  
    var temporaryDirectory: String {
        return NSTemporaryDirectory()
    }
    
    var testsDirectory: String {
        return (temporaryDirectory as NSString).appendingPathComponent("WitnessTests")
    }
    
    var filePath: String {
        return (testsDirectory as NSString).appendingPathComponent("file.txt")
    }
    
    override func setUp() {
        print("Setting up...")
        super.setUp()
        
        // create tests directory
        print("create tests directory at path: \(testsDirectory)")
        print("file path: \(filePath)")
        try? fileManager.removeItem(atPath: testsDirectory)
        try! fileManager.createDirectory(atPath: testsDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    override func tearDown() {
        witness?.flush()
        witness = nil
        
        do {
            // remove tests directory
            try fileManager.removeItem(atPath: testsDirectory)
        }
        catch {}
        
        super.tearDown()
    }
    
//    func waitForPendingEvents() {
//        print("wait for pending changes...")
//
//        var didArrive = false
//        witness = Witness(paths: [testsDirectory], flags: [.NoDefer, .WatchRoot], latency: WitnessTests.latency) { events in
//            print("pending changes arrived")
//            didArrive = true
//        }
//
//        while !didArrive {
//            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, true);
//        }
//    }
    
    //    func waitForPendingEvents() {
    //        print("wait for pending changes...")
    //
    //        var didArrive = false
    //        witness = Witness(paths: [testsDirectory], flags: [.NoDefer, .WatchRoot], latency: WitnessTests.latency) { events in
    //            print("pending changes arrived")
    //            didArrive = true
    //        }
    //
    //        while !didArrive {
    //            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, true);
    //        }
    //    }
    
    func delay(_ interval: TimeInterval, block: @escaping () -> ()) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + interval, execute: block)
    }
    
    func testThatFileCreationIsObserved() {
        var expectation: XCTestExpectation? = self.expectation(description: "File creation should trigger event")
//        witness = Witness(paths: [testsDirectory], flags: .FileEvents) { events in
        let witness = Witness(paths: [testsDirectory], watchOptions: .all) { events in
            print("Events: \(events)")
            for event in events {
                if event.path.hasSuffix(self.filePath), event.type.contains(.updated)  {
//                    DispatchQueue.main.sync {
                        expectation?.fulfill()
                        expectation = nil
//                    }
                }
            }
        }
        fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
        waitForExpectations(timeout: WitnessTests.expectationTimeout, handler: nil)
    }
//
    func testThatFileRemovalIsObserved() {
        let expectation = self.expectation(description: "File removal should trigger event")
        fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
//        waitForPendingEvents()
        let witness = Witness(paths: [testsDirectory], watchOptions: .all) { events in
            for event in events {
                if event.path.hasSuffix(self.filePath), event.type.contains(.deleted) {
                    expectation.fulfill()
                }
            }
        }
        try! fileManager.removeItem(atPath: filePath)
        waitForExpectations(timeout: WitnessTests.expectationTimeout, handler: nil)
    }

    func testThatFileChangesAreObserved() {
        let expectation = self.expectation(description: "File changes should trigger event")
        fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
//        waitForPendingEvents()
        witness = Witness(paths: [testsDirectory], eventTypes: .updated) { events in
            for event in events {
                if event.path.hasSuffix(self.filePath), event.type.contains(.updated)  {
                    expectation.fulfill()
                }
            }
        }
        try! "Hello changes".write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
        
        let dirContents = try? FileManager.default.contentsOfDirectory(atPath: testsDirectory)
        
        print(dirContents ?? [])
        
        waitForExpectations(timeout: WitnessTests.expectationTimeout, handler: nil)
    }
    
//    func testThatRootDirectoryIsNotObserved() {
//        let expectation = self.expectation(description: "Removing root directory should not trigger event if .WatchRoot flag is not set")
//        var didReceiveEvent = false
//        witness = Witness(paths: [testsDirectory], flags: .NoDefer) { events in
//            didReceiveEvent = true
//        }
//
//        delay(WitnessTests.latency * 2) {
//            if didReceiveEvent == false {
//                expectation.fulfill()
//            }
//        }
//
//        try! fileManager.removeItem(atPath: testsDirectory)
//        waitForExpectations(timeout: WitnessTests.expectationTimeout, handler: nil)
//    }
    
//    func testThatRootDirectoryIsObserved() {
//        let expectation = self.expectation(description: "Removing root directory should trigger event if .WatchRoot flag is set")
//        witness = Witness(paths: [testsDirectory], flags: .WatchRoot) { events in
//            expectation.fulfill()
//        }
//        try! fileManager.removeItem(atPath: testsDirectory)
//        waitForExpectations(timeout: WitnessTests.expectationTimeout, handler: nil)
//    }

}
