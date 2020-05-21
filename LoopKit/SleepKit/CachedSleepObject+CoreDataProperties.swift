//
//  CachedSleepObject+CoreDataProperties.swift
//  LoopKit
//
//  Created by Jason Calabrese on 5/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import CoreData


extension CachedSleepObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CachedSleepObject> {
        return NSFetchRequest<CachedSleepObject>(entityName: "CachedSleepObject")
    }

    @NSManaged public var value: Int32
    @NSManaged public var primitiveStartDate: NSDate?
    @NSManaged public var primitiveEndDate: NSDate?
    @NSManaged public var uuid: UUID?
    @NSManaged public var syncIdentifier: String?
    @NSManaged public var syncVersion: Int32

}
