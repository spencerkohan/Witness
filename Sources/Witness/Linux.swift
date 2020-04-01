//
//  Linux.swift
//  Witness
//
//  Created by Spencer Kohan on 3/31/20.
//



#if os(Linux)

import Glibc
import Foundation
import CLinuxUtils

typealias EventMask = UInt32

extension FSEventType {
    init(mask: EventMask) {
        var type: FSEventType = .none
        if mask & UInt32(IN_CREATE) > 0 {
            type = [type, .create]
        }
        if mask & UInt32(IN_DELETE) > 0 {
            type.insert(.delete)
        }
        if mask & UInt32(IN_MODIFY) > 0 {
            type.insert(.modify)
        }
        self = type
    }
    
    var mask: EventMask {
        var mask: EventMask = 0
        if self.contains(.create) {
            mask = mask | EventMask(IN_CREATE)
        }
        if self.contains(.modify) {
            mask = mask | EventMask(IN_MODIFY)
        }
        if self.contains(.delete) {
            mask = mask | EventMask(IN_DELETE)
        }
        return mask
    }
}


let EVENT_SIZE: Int = Int( MemoryLayout<inotify_event>.size )
    
    
typealias WatcherDescriptor = Int32

    extension String {
        func appending(pathComponent: String) -> String {
            let url = URL(fileURLWithPath: self)
            return url.appendingPathComponent(pathComponent).path
        }
    }


let syncQueue = DispatchQueue.global(qos: .background)

func sync<T>(_ block: ()->T) -> T {
    return syncQueue.sync(execute: block)
}
    
class INotifyEventStream: EventStreamProtocol {
    
    struct WatchConfig {
        let path: String
        let eventMask: EventMask
        let recursion: Recursion
    }
    
    var paths: [String] {
        return directories.values.map {
            $0.path
        }
    }

    
    var fileDescriptor: Int32 = 0
    var directories = [WatcherDescriptor: WatchConfig]()
    var eventHandler: EventHandler
    private var _listening: Bool = false
    private var listening: Bool {
        get {
            let l: Bool = syncQueue.sync {
                return self._listening
            }
            return l
        }
        set {
            syncQueue.sync {
                self._listening = newValue
            }
        }
    }
    
    let eventQueue = DispatchQueue.global(qos: .background)
    
    var eventBuffer = UnsafeMutableRawPointer.allocate(
        byteCount: (1024 * (EVENT_SIZE + 16)),
        alignment: MemoryLayout<inotify_event>.alignment)
    
    init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
        fileDescriptor = sync { inotify_init(); }
    }
    
    deinit {
        eventBuffer.deallocate()
    }
    
    func add(
        path: String,
        eventMask: EventMask,
        recursion: Recursion = .unlimited
    ) {
        let wd = sync { inotify_add_watch(fileDescriptor, path, eventMask) }
        
        directories[wd] = WatchConfig(
            path: path,
            eventMask: eventMask,
            recursion: recursion
        )
        
        let fm = FileManager.default
        
        switch recursion {
        case .none:
            return
        case .withDepth(let depth):
            guard depth > 0 else { return }
            guard let subpaths = try? fm.subpathsOfDirectory(atPath: path) else { return }
            for subpath in subpaths {
                add(path: path.appendingPathComponent(subpath), eventMask: eventMask, recursion: .withDepth(depth-1))
            }
        case .unlimited:
            guard let subpaths = try? fm.subpathsOfDirectory(atPath: path) else { return }
            for subpath in subpaths {
                add(path: path.appendingPathComponent(subpath), eventMask: eventMask, recursion: .unlimited)
            }
        }
    }
    
    func start() {
        self.listening = true
        eventQueue.async {
            var listening = self.listening
            while listening {
                let events = self.readEvents()
                if events.count > 0 {
                    self.eventHandler(events)
                }
                listening = self.listening
            }
        }
    }
    
    func stop() {
        self.listening = false
    }
    
    func readEvents() -> [FileSystemEvent] {
        var events: [FileSystemEvent] = []
        
        var length: Int = 0
        length = sync { read(self.fileDescriptor, self.eventBuffer, (1024 * (EVENT_SIZE + 16))) }
        
        if length < 0 {
            print("read error: \(length)")
        }
        
        func isDir(_ mask: EventMask) -> Bool {
            return mask & EventMask(IN_ISDIR) > 0
        }
        
        var offset = 0
        while offset < length {
            let rawPointer = eventBuffer.advanced(by: offset)
            let eventPointer = rawPointer.bindMemory(to: inotify_event.self, capacity: 1)
            
            let event = eventPointer.pointee
            let wd = event.wd
            let mask = event.mask
            let namePointer = getEventName(rawPointer)
            let stride = getEventStride(rawPointer)
        
            offset += Int(stride)

            guard let namePtr = namePointer else { continue }
            let name = String(cString: namePtr)
            guard let watchConfig = directories[wd] else { continue }
            
            let eventType = FSEventType(mask: mask)
            let path = watchConfig.path.appending(pathComponent: name)
            
            if eventType.contains(.create) && isDir(mask) {
                switch watchConfig.recursion {
                case .none:
                    break
                case .withDepth(let depth):
                    guard depth > 0 else { break }
                    add(path: path, eventMask: watchConfig.eventMask, recursion: .withDepth(depth - 1))
                case .unlimited:
                    add(path: path, eventMask: watchConfig.eventMask, recursion: .unlimited)
                }
            }
            
            if eventType.contains(.delete) && isDir(mask) {
                // TODO: implement removal
            }
            
            events.append(
                FileSystemEvent(
                    path: path,
                    type: eventType)
            )
        }
        return events
    }
}



//func startNotify() {
//
//    print("EVENT_SIZE: \(EVENT_SIZE)")
//
//    var length: Int = 0
//    var fd: Int32 = 0
//    var wd: Int32 = 0
//    var buff = [UInt8](repeating: 0, count: 1024 * (EVENT_SIZE + 16) )
//
//    var buffer = UnsafeMutableRawPointer.allocate(byteCount: (1024 * (EVENT_SIZE + 16)), alignment: MemoryLayout<inotify_event>.alignment)
//    defer { buffer.deallocate() }
//
//    fd = inotify_init();
//
//    print("init result: \(fd)")
//    if fd < 0 {
//        fatalError("inotify_init failed")
//    }
//
//    wd = inotify_add_watch(fd, FileManager.default.currentDirectoryPath, UInt32(IN_CREATE | IN_DELETE | IN_MODIFY) )
//
//    while true {
//
//    length = read(fd, buffer, (1024 * (EVENT_SIZE + 16)))
//
//    if length < 0 {
//        print("read error: \(length)")
//    }
//
//    print("events length: \(length)")
//
//    var offset = 0
//    while offset < length {
//
//        print("getting raw pointer at offset: \(offset)")
//        var rawPointer = buffer.advanced(by: offset)
//
//        //print("getting event pointer")
//        var eventPointer = rawPointer.bindMemory(to: inotify_event.self, capacity: 1)
//
//        //print("getting event")
//        let event = eventPointer.pointee
//
//        let name = getEventName(rawPointer)
//        let stride = getEventStride(rawPointer)
//
//        offset += Int(stride)
//
//        if event.mask & UInt32(IN_CREATE) > 0 {
//            print("File created: \(event)")
//        }
//        if event.mask & UInt32(IN_DELETE) > 0 {
//            print("file deleted: \(event)")
//        }
//        if event.mask & UInt32(IN_MODIFY) > 0 {
//            print("file modified: \(event)")
//        }
//
//        if let namePTR = name {
//            print("\t name: \(String(cString: namePTR))")
//        } else {
//            print("\t no name")
//        }
//    }
//
//    //for event in buffer {
//    //    if event.mask & UInt32(IN_CREATE) > 0 {
//    //        print("File created: \(event)")
//    //        print("\t \(String(cString: event.name))")
//    //    }
//    //    if event.mask & UInt32(IN_DELETE) > 0 {
//    //        print("file deleted: \(event)")
//    //    }
//    //    if event.mask & UInt32(IN_MODIFY) > 0 {
//    //        print("file modified: \(event)")
//    //    }
//    //}
//
//    }
//
//
//
//}

#endif
