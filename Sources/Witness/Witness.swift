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

public struct FSEventType: OptionSet, CustomDebugStringConvertible {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    public static let none: FSEventType = FSEventType(rawValue: 0)
    public static let created: FSEventType = FSEventType(rawValue: 1)
    public static let deleted: FSEventType = FSEventType(rawValue: 1 << 1)
    public static let modify: FSEventType = FSEventType(rawValue: 1 << 2)
    public static let movedTo: FSEventType = FSEventType(rawValue: 1 << 3)
    public static let movedFrom: FSEventType = FSEventType(rawValue: 1 << 4)
    public static let updated: FSEventType = FSEventType(rawValue: 1 << 5)
    public static let all: FSEventType = [.created, .deleted, .modify, .movedTo, .movedFrom, .updated]
    
    public var debugDescription: String {
        
        var components = [String]()
        
        if self.contains(.created) {
            components.append("create")
        }
        if self.contains(.deleted) {
            components.append("delete")
        }
        if self.contains(.modify) {
            components.append("modify")
        }
        if self.contains(.movedTo) {
            components.append("movedTo")
        }
        if self.contains(.movedFrom) {
            components.append("movedFrom")
        }
        if self.contains(.updated) {
            components.append("update")
        }
        if components.count == 0 {
            return "[none]"
        }
        return "[\(components.joined(separator: ", "))]"
        
    }
    
}

public struct WatchOption: OptionSet {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    public static let none: WatchOption = WatchOption(rawValue: 0)
    public static let file: WatchOption = WatchOption(rawValue: 1)
    public static let directory: WatchOption = WatchOption(rawValue: 1 << 1)
    public static let all: WatchOption = [.file, .directory]
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
                watchOptions: WatchOption = .all,
                latency: TimeInterval = 1.0,
                recursion: Recursion = .unlimited,
                changeHandler: @escaping EventHandler) {

        #if os(Linux)
            self.stream = INotifyEventStream(options: watchOptions, eventHandler: changeHandler)
            for path in paths {
                self.stream.add(path: path, eventMask: eventTypes.mask, recursion: recursion)
            }
            stream.start()
        #elseif os(macOS)
        
        var flags: EventStreamCreateFlags = .None
        if watchOptions.contains(.file) {
            flags.insert(.FileEvents)
        }
        
        self.stream = MacOSEventStream(paths: paths, flags: flags, latency: latency, changeHandler: { events in
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

