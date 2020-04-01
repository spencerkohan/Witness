//
//  Witness.swift
//  Witness
//
//  Created by Niels de Hoog on 23/09/15.
//  Copyright © 2015 Invisible Pixel. All rights reserved.
//

import Foundation

public enum Recursion {
    case none
    case withDepth(Int)
    case unlimited
}

public struct FSEventType: OptionSet {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    public static let none: FSEventType = FSEventType(rawValue: 0)
    public static let create: FSEventType = FSEventType(rawValue: 1)
    public static let delete: FSEventType = FSEventType(rawValue: 1 << 1)
    public static let modify: FSEventType = FSEventType(rawValue: 1 << 2)
    public static let all: FSEventType = [.create, .delete, .modify]
}

public struct FileSystemEvent {
    let path: String
    let type: FSEventType
}

public typealias EventHandler = ([FileSystemEvent])->()


protocol EventStreamProtocol {
    var paths: [String] { get }
}

public struct Witness {
    var paths: [String] {
        return stream.paths
    }
    
    #if os(Linux)
        private let stream: INotifyEventStream
    #elseif os(macOS)
        private let stream: MacOSEventStream
    #endif
    
    public init(paths: [String],
                eventTypes: FSEventType = .all,
                latency: TimeInterval = 1.0,
                recursion: Recursion = .unlimited,
                changeHandler: @escaping EventHandler) {

        #if os(Linux)
            self.stream = INotifyEventStream(eventHandler: changeHandler)
            for path in paths {
                self.stream.add(path: path, eventMask: eventTypes.mask, recursion: recursion)
            }
            stream.start()
        #elseif os(macOS)
        self.stream = MacOSEventStream(paths: paths, flags: .None, latency: latency, changeHandler: { events in
            let mapped = events.map {
                FileSystemEvent(path: $0.path, type: FSEventType($0.flags))
            }
            changeHandler(mapped)
        })
        #endif
    }
    
//    public init(paths: [String], streamType: StreamType, eventTypes: FSEventType = .all, latency: TimeInterval = 1.0, deviceToWatch: dev_t,  changeHandler: @escaping FileEventHandler) {
//        self.stream = MacOSEventStream(paths: paths, type: streamType, flags: flags, latency: latency, deviceToWatch: deviceToWatch, changeHandler: changeHandler)
//    }
    
    public func flush() {
        #if os(Linux)
            // not implemented
        #elseif os(macOS)
            self.stream.flush()
        #endif
    }
    
    public func flushAsync() {
        #if os(Linux)
            // not implemented
        #elseif os(macOS)
            self.stream.flushAsync()
        #endif
    }
}

