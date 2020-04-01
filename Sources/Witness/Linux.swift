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

extension EventMask {
    func contains(_ mask: Int32) -> Bool {
        return self & EventMask(mask) > 0
    }
}

extension FSEventType {
    init(mask: EventMask) {
        var type: FSEventType = .none
        if mask & UInt32(IN_CREATE) > 0 {
            type = [type, .created]
            type.insert(.updated)
        }
        if mask & UInt32(IN_DELETE) > 0 {
            type.insert(.deleted)
        }
        if mask & UInt32(IN_MODIFY) > 0 {
            type.insert(.modify)
            type.insert(.updated)
        }
        if mask & UInt32(IN_MOVED_TO) > 0 {
            type.insert(.movedTo)
            type.insert(.updated)
        }
        if mask & UInt32(IN_MOVED_FROM) > 0 {
            type.insert(.movedFrom)
        }
        self = type
    }
    
    var mask: EventMask {
        var mask: EventMask = 0
        if self.contains(.created) {
            mask = mask | EventMask(IN_CREATE)
        }
        if self.contains(.modify) {
            mask = mask | EventMask(IN_MODIFY)
        }
        if self.contains(.deleted) {
            mask = mask | EventMask(IN_DELETE)
        }
        if self.contains(.movedTo) {
            mask = mask | EventMask(IN_MOVED_TO)
        }
        if self.contains(.movedFrom) {
            mask = mask | EventMask(IN_MOVED_FROM)
        }
        if self.contains(.updated) {
            mask = mask | EventMask(IN_MOVED_TO)
            mask = mask | EventMask(IN_MODIFY)
            mask = mask | EventMask(IN_CREATE)
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

    let options: WatchOption
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
    
    init(options: WatchOption, eventHandler: @escaping EventHandler) {
        self.options = options
        self.eventHandler = eventHandler
        fileDescriptor = sync { inotify_init(); }
    }
    
    deinit {
        eventBuffer.deallocate()
        for wd in directories.keys {
            inotify_rm_watch(fileDescriptor, wd)
        }
        close(fileDescriptor)
        
    }
    
    func add(
        path: String,
        eventMask: EventMask,
        recursion: Recursion = .unlimited
    ) {
        let wd = sync { inotify_add_watch(fileDescriptor, path, eventMask | EventMask(IN_MOVED_TO) | EventMask(IN_MOVED_FROM)) }
        
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
    
    func remove(_ wd: WatcherDescriptor) {
        
        
//        let fm = FileManager.default
        guard let _ = directories[wd] else { return }
        inotify_rm_watch(fileDescriptor, wd)
        directories[wd] = nil
        
//        let path = config.path
//
//        guard let subpaths = try? fm.subpathsOfDirectory(atPath: path) else { return }
//        let wds = directories.filter { wd, config }
//        for subpath in subpaths {
//            add(path: path.appendingPathComponent(subpath), eventMask: eventMask, recursion: .withDepth(depth-1))
//        }
//
         
        
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
        
        print("Reading events...")
        
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
            
            if eventType.contains(.created) && isDir(mask) {
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
            
            if eventType.contains(.deleted) && isDir(mask) {
                remove(wd)
            }
            

            print("Event: \(path)")
            print("\teventType: \(eventType)")
            print("\tmask: \(mask)")
            
//            var isDir = mask.contains(IN_ISDIR)
            if isDir(mask) && !options.contains(.directory) {
                print("> Ignoring...")
                continue
            }
            if !isDir(mask) && !options.contains(.file) {
                print("> Ignoring...")
                continue
            }
            if eventType == .none {
                print("> Ignoring: eventType == .none")
                continue
            }
            
            if watchConfig.eventMask & mask == 0 {
                print("> Ignoring: watchConfig.mask & mask == 0")
                continue
            }
            
            print("> Appending...")
            
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
