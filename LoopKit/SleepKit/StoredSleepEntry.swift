//
//  StoredSleepEntry.swift
//  LoopKit
//
//  Created by Jason Calabrese on 5/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//
import HealthKit
import CoreData

private let unit = HKUnit.gram()

public struct StoredSleepEntry : TimelineValue {

    public let sampleUUID: UUID

    // MARK: - HealthKit Sync Support

    public let syncIdentifier: String?
    public let syncVersion: Int

    // MARK: - SampleValue

    public let startDate: Date
    public let endDate: Date
    public let value: Int

    init(sample: HKCategorySample) {
        self.init(
            sampleUUID: sample.uuid,
            syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
            syncVersion: sample.metadata?[HKMetadataKeySyncVersion] as? Int ?? 1,
            startDate: sample.startDate,
            endDate: sample.endDate,
            value: sample.value
        )
    }

    public init(
        sampleUUID: UUID,
        syncIdentifier: String?,
        syncVersion: Int,
        startDate: Date,
        endDate: Date,
        value: Int
    ) {
        self.sampleUUID = sampleUUID
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
    }
}


extension StoredSleepEntry: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sampleUUID)
    }
}

extension StoredSleepEntry: Equatable {
    public static func ==(lhs: StoredSleepEntry, rhs: StoredSleepEntry) -> Bool {
        return lhs.sampleUUID == rhs.sampleUUID
    }
}

extension StoredSleepEntry: Comparable {
    public static func <(lhs: StoredSleepEntry, rhs: StoredSleepEntry) -> Bool {
        return lhs.startDate < rhs.startDate
    }
}


extension StoredSleepEntry {
    init(managedObject: CachedSleepObject) {
        self.init(
            sampleUUID: managedObject.uuid!,
            syncIdentifier: managedObject.syncIdentifier,
            syncVersion: Int(managedObject.syncVersion),
            startDate: managedObject.startDate,
            endDate: managedObject.endDate,
            value: Int(managedObject.value)
        )
    }
}
