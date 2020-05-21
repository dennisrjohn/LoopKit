//
//  CachedSleepObject+CoreDataClass.swift
//  LoopKit
//
//  Created by Jason Calabrese on 5/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreData
import HealthKit


class CachedSleepObject: NSManagedObject {
    var startDate: Date! {
        get {
            willAccessValue(forKey: "startDate")
            defer { didAccessValue(forKey: "startDate") }
            return primitiveStartDate! as Date
        }
        set {
            willChangeValue(forKey: "startDate")
            defer { didChangeValue(forKey: "startDate") }
            primitiveStartDate = newValue as NSDate
        }
    }

    var endDate: Date! {
        get {
            willAccessValue(forKey: "endDate")
            defer { didAccessValue(forKey: "endDate") }
            return primitiveEndDate! as Date
        }
        set {
            willChangeValue(forKey: "endDate")
            defer { didChangeValue(forKey: "endDate") }
            primitiveEndDate = newValue as NSDate
        }
    }
}

extension CachedSleepObject {
    func update(from entry: StoredSleepEntry) {
        uuid = entry.sampleUUID
        syncIdentifier = entry.syncIdentifier
        syncVersion = Int32(clamping: entry.syncVersion)
        startDate = entry.startDate
        endDate = entry.endDate
        value = Int32(clamping: entry.value)
    }
}
