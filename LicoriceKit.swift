//
//  LicoriceKit.swift
//  ContactsDemo
//
//  Created by Artemiy Sobolev on 26/03/2017.
//  Copyright © 2016 mipt. All rights reserved.
//

import Foundation

public
enum Capture {
    case weak, strong
}

private
struct ObjectKeyPathHolder {
    weak var object: NSObject?
    let privateObjectCopy: NSObject?
    
    let keyPath: String
    
    init(object: NSObject, keyPath: String, capture: Capture) {
        self.object = object
        self.keyPath = keyPath
        privateObjectCopy = capture == .weak ? nil : object
    }
    
    init(tuple: (NSObject, String, Capture)) {
        self.init(object: tuple.0, keyPath: tuple.1, capture: tuple.2)
    }
}

private var associatedObjectHandle: UInt8 = 0

extension NSObject {
    
    func bind(what: NSObject, how keyPath: String, to: NSObject, of targetKeyPath: String) {
        var key = keyPath + targetKeyPath
        
        let origin: (NSObject, String, Capture) = (what, keyPath, what == self ? .weak : .strong)
        let target: (NSObject, String, Capture) = (to, targetKeyPath, to == self ? .weak : .strong)
        
        let binder = TypeLessBinder(origin: origin, target: target)
        
        let result = objc_getAssociatedObject(self, &key) as? [TypeLessBinder] ?? []
        
        objc_setAssociatedObject(self, &key, result + [binder], .OBJC_ASSOCIATION_RETAIN)
    }
}

@objc
open class TypeLessBinder: NSObject {
    
    private let targetHolder: ObjectKeyPathHolder
    private let originHolder: ObjectKeyPathHolder

    public init(origin: (NSObject, String, Capture), target: (NSObject, String, Capture)) {
        
        targetHolder = ObjectKeyPathHolder(tuple: target)
        originHolder = ObjectKeyPathHolder(tuple: origin)
        
        super.init()
        
        targetHolder.object?.addObserver(self, forKeyPath: targetHolder.keyPath, options: [.new, .initial], context: nil)
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let value = targetHolder.object?.value(forKeyPath: targetHolder.keyPath)
        originHolder.object?.setValue(value, forKeyPath: originHolder.keyPath)
    }
    
    deinit {
        targetHolder.object?.removeObserver(self, forKeyPath: targetHolder.keyPath)
    }
}

/**
 Binder writes to a property a new value of observed variable.
 Use it if you want to observe some property and write it value to your property.
 */
open class ObservationBinder<T: Any>: NSObject {
    fileprivate let setter: Setter<T>
    let token: Observer<T>
    // setter - object and path where your store observed value (Who wants to know about changes)
    // target - object and path which you observe (Who changes)
    public init(setter: (NSObject, Selector), target: (NSObject, String)) {
        self.setter = Setter(object: setter.0, keypath: setter.1)
        self.token = Observer(object: target.0, keypath: target.1)
        super.init()
        self.token.closure = { [weak self] (anyValue: T) -> Void in
            self?.setter.setValue(anyValue)
            return
        }
    }
}

/**
 Setter sets a property using a closure in proper queue
 */
private class Setter<T: Any>: NSObject {
    weak var object: AnyObject?
    var selector: Selector
    
    func setValue(_ newValue: T) {
        _ = object?.perform?(selector, with: newValue)
    }
    
    init(object: AnyObject, keypath: Selector) {
        self.object = object
        self.selector = keypath
    }
}

public class Observer<ObservedType>: NSObject {
    
    func remove() {
        object?.removeObserver(self, forKeyPath: keypath)
    }
    
    private var kvoContext: UInt8 = 1
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &kvoContext else {
            return
        }
        
        if let pk = keyPath, let result = (object as? NSObject)?.value(forKeyPath: pk) as? ObservedType {
            closure?(result)
        }
    }
    
    weak var object: NSObject?
    let objectReferenceCopy: NSObject?
    
    let keypath: String
    
    deinit {
        object?.removeObserver(self, forKeyPath: keypath)
    }
    
    public init(object: NSObject, capture: Capture = .strong, keypath: String) {
        self.object = object
        self.keypath = keypath
        self.objectReferenceCopy = capture == .strong ? object : nil
    }
    
    private var closure: ((ObservedType) -> Void)? {
        didSet {
            object?.addObserver(self, forKeyPath: keypath, options: [.initial, .new], context: &kvoContext)
        }
    }
    
    public init(object: NSObject, capture: Capture = .strong, keypath: String, closure: @escaping (ObservedType) -> Void) {
        self.object = object
        self.keypath = keypath
        self.objectReferenceCopy = capture == .strong ? object : nil
        self.closure = closure
        super.init()
        object.addObserver(self, forKeyPath: keypath, options: [.initial, .new], context: &kvoContext)
    }
}

