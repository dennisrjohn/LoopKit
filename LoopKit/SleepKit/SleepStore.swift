//  SleepStore.swift
//  LoopKit
//
//  Created by Jason Calabrese on 5/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//
//  Based on
//  SleepStore.swift
//  Loop
//
//  Created by Anna Quinlan on 12/28/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.

import Foundation
import CoreData
import HealthKit
import os.log

public enum SleepStoreResult<T> {
    case success(T)
    case failure(SleepStoreError)
}

public enum SleepStoreError: Error {
    case noMatchingBedtime
    case unknownReturnConfiguration
    case noSleepDataAvailable
    case queryError(String) // String is description of error
    // The health store request returned an error
    case healthStoreError(Error)
}

public final class SleepStore {
    var healthStore: HKHealthStore

    /// The interval of carb data to keep in cache
    public let cacheLength: TimeInterval
    public let cacheStore: PersistenceController

    let sleepType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!

    private let queue = DispatchQueue(label: "com.loopkit.SleepKit.dataAccessQueue", qos: .utility)

    private let log = OSLog(category: "SleepStore")
    
    public init(
        healthStore: HKHealthStore,
        cacheStore: PersistenceController,
        cacheLength: TimeInterval
    ) {
        self.healthStore = healthStore
        self.cacheStore = cacheStore
        self.cacheLength = cacheLength
    }
    
    /// Fetches samples from HealthKit
    ///
    /// - Parameters:
    ///   - start: The earliest date of samples to retrieve
    ///   - end: The latest date of samples to retrieve, if provided
    ///   - completion: A closure called once the samples have been retrieved
    ///   - result: An array of samples, in chronological order by startDate
    private func getSleepSamples(start: Date, end: Date? = nil, completion: @escaping (_ result: SleepStoreResult<[StoredSleepEntry]>) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortDescriptors) { (query, samples, error) in
            if let error = error {
                completion(.failure(.healthStoreError(error)))
            } else {
                completion(.success((samples as? [HKCategorySample] ?? []).map { StoredSleepEntry(sample: $0) }))
            }
        }

        healthStore.execute(query)
    }

    /// Fetches samples from HealthKit, if available, or returns from cache.
    ///
    /// - Parameters:
    ///   - start: The earliest date of samples to retrieve
    ///   - end: The latest date of samples to retrieve, if provided
    ///   - completion: A closure called once the samples have been retrieved
    ///   - samples: An array of samples, in chronological order by startDate
    public func getCachedSleepSamples(start: Date, end: Date? = nil, completion: @escaping (_ samples: [StoredSleepEntry]) -> Void) {
        #if os(iOS)
        // If we're within our cache duration, skip the HealthKit query
        guard start <= earliestCacheDate else {
            self.queue.async {
                let entries = self.getCachedSleepEntries().filterDateRange(start, end)
                completion(entries)
            }
            return
        }
        #endif

        getSleepSamples(start: start, end: end) { (result) in
            switch result {
            case .success(let samples):
                completion(samples)
            case .failure:
                self.queue.async {
                    completion(self.getCachedSleepEntries().filterDateRange(start, end))
                }
            }
        }
    }
    
    // MARK: - Helpers

    /// Fetches carb entries from the cache that match the given predicate
    ///
    /// - Parameter predicate: The predicate to apply to the objects
    /// - Returns: An array of carb entries, in chronological order by startDate
    private func getCachedSleepEntries(matching predicate: NSPredicate? = nil) -> [StoredSleepEntry] {
        dispatchPrecondition(condition: .onQueue(queue))
        var entries: [StoredSleepEntry] = []

        cacheStore.managedObjectContext.performAndWait {
            let request: NSFetchRequest<CachedSleepObject> = CachedSleepObject.fetchRequest()
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]

            guard let objects = try? self.cacheStore.managedObjectContext.fetch(request) else {
                return
            }

            entries = objects.map { StoredSleepEntry(managedObject: $0) }
        }

        return entries
    }
}

extension NSManagedObjectContext {
    fileprivate func cachedSleepObjectsWithUUID(_ uuid: UUID, fetchLimit: Int? = nil) -> [CachedSleepObject] {
        let request: NSFetchRequest<CachedSleepObject> = CachedSleepObject.fetchRequest()
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        request.predicate = NSPredicate(format: "uuid == %@", uuid as NSUUID)

        return (try? fetch(request)) ?? []
    }

    fileprivate func deleteObjects<T>(matching fetchRequest: NSFetchRequest<T>) throws -> Int where T: NSManagedObject {
        let objects = try fetch(fetchRequest)

        for object in objects {
            delete(object)
        }

        if hasChanges {
            try save()
        }

        return objects.count
    }
}

// MARK: - Cache management
extension SleepStore {
    private var earliestCacheDate: Date {
        return Date(timeIntervalSinceNow: -cacheLength)
    }

    @discardableResult
    private func addCachedObject(for sample: HKCategorySample) -> Bool {
        return addCachedObject(for: StoredSleepEntry(sample: sample))
    }

    @discardableResult
    private func addCachedObject(for entry: StoredSleepEntry) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))

        var created = false

        cacheStore.managedObjectContext.performAndWait {
            guard self.cacheStore.managedObjectContext.cachedSleepObjectsWithUUID(entry.sampleUUID, fetchLimit: 1).count == 0 else {
                return
            }

            let object = CachedSleepObject(context: self.cacheStore.managedObjectContext)
            object.update(from: entry)

            self.cacheStore.save()
            created = true
        }

        return created
    }

    private func replaceCachedObject(for oldEntry: StoredSleepEntry, with newEntry: StoredSleepEntry) {
        dispatchPrecondition(condition: .onQueue(queue))

        cacheStore.managedObjectContext.performAndWait {
            for object in self.cacheStore.managedObjectContext.cachedSleepObjectsWithUUID(oldEntry.sampleUUID) {
                object.update(from: newEntry)
            }

            self.cacheStore.save()
        }
    }

    @discardableResult
    private func deleteCachedObject(for sample: HKDeletedObject) -> Bool {
        return deleteCachedObject(forSampleUUID: sample.uuid)
    }

    @discardableResult
    private func deleteCachedObject(for entry: StoredSleepEntry) -> Bool {
        return deleteCachedObject(forSampleUUID: entry.sampleUUID)
    }

    @discardableResult
    private func deleteCachedObjects(for uuids: [UUID], batchSize: Int = 500) -> Int {
        dispatchPrecondition(condition: .onQueue(queue))

        var deleted = 0

        cacheStore.managedObjectContext.performAndWait {
            for batch in uuids.chunked(into: batchSize) {
                let predicate = NSPredicate(format: "uuid IN %@", batch.map { $0 as NSUUID })
                if let count = try? cacheStore.managedObjectContext.purgeObjects(of: CachedSleepObject.self, matching: predicate) {
                    deleted += count
                }
            }
        }
        return deleted
    }

    @discardableResult
    private func deleteCachedObject(forSampleUUID uuid: UUID) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))

        var deleted = false

        cacheStore.managedObjectContext.performAndWait {
            for object in self.cacheStore.managedObjectContext.cachedSleepObjectsWithUUID(uuid) {
                self.cacheStore.managedObjectContext.delete(object)
                deleted = true
            }

            self.cacheStore.save()
        }

        return deleted
    }

    // MARK: - Helpers

    /// Fetches carb entries from the cache that match the given predicate
    ///
    /// - Parameter predicate: The predicate to apply to the objects
    /// - Returns: An array of carb entries, in chronological order by startDate
    private func getCachedCarbEntries(matching predicate: NSPredicate? = nil) -> [StoredCarbEntry] {
        dispatchPrecondition(condition: .onQueue(queue))
        var entries: [StoredCarbEntry] = []

        cacheStore.managedObjectContext.performAndWait {
            let request: NSFetchRequest<CachedCarbObject> = CachedCarbObject.fetchRequest()
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]

            guard let objects = try? self.cacheStore.managedObjectContext.fetch(request) else {
                return
            }

            entries = objects.map { StoredCarbEntry(managedObject: $0) }
        }

        return entries
    }
}

public typealias HourAndMinute = (hour: Int, minute: Int)

extension SleepStore {
    func getAverageSleepStartTime(sampleLimit: Int = 30, _ completion: @escaping (_ result: SleepStoreResult<(HourAndMinute)>) -> Void) {
        let inBedPredicate = HKQuery.predicateForCategorySamples(
            with: .equalTo,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue
        )
        
        let asleepPredicate = HKQuery.predicateForCategorySamples(
            with: .equalTo,
            value: HKCategoryValueSleepAnalysis.asleep.rawValue
        )
        
        getAverageSleepStartTime(matching: inBedPredicate, sampleLimit: sampleLimit) {
            (result) in
            switch result {
            case .success(_):
                completion(result)
            case .failure(let error):
                switch error {
                case SleepStoreError.noSleepDataAvailable:
                    // if there were no .inBed samples, check if there are any .asleep samples that could be used to estimate bedtime
                    self.getAverageSleepStartTime(matching: asleepPredicate, sampleLimit: sampleLimit, completion)
                default:
                    // otherwise, call completion
                    completion(result)
                }
            }
            
        }
    }

    fileprivate func getAverageSleepStartTime(matching predicate: NSPredicate, sampleLimit: Int, _ completion: @escaping (_ result: SleepStoreResult<HourAndMinute>) -> Void) {
        let sleepType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!
        
        // get more-recent values first
        let sortByDate = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: sampleLimit, sortDescriptors: [sortByDate]) { (query, samples, error) in

            if let error = error {
                self.log.error("Error fetching sleep data: %{public}@", String(describing: error))
                completion(.failure(SleepStoreError.queryError(error.localizedDescription)))
            } else if let samples = samples as? [HKCategorySample] {
                guard !samples.isEmpty else {
                    completion(.failure(SleepStoreError.noSleepDataAvailable))
                    return
                }
                
                // find the average hour and minute components from the sleep start times
                let average = samples.reduce(0, {
                    if let metadata = $1.metadata, let timezone = metadata[HKMetadataKeyTimeZone] {
                        return $0 + $1.startDate.timeOfDayInSeconds(sampleTimeZone:  NSTimeZone(name: timezone as! String)! as TimeZone)
                    } else {
                        // default to the current timezone if the sample does not contain one in its metadata
                        return $0 + $1.startDate.timeOfDayInSeconds(sampleTimeZone: Calendar.current.timeZone)
                    }
                }) / samples.count
                
                let averageHour = average / 3600
                let averageMinute = average % 3600 / 60

                completion(.success((hour: averageHour, minute: averageMinute)))
            } else {
                completion(.failure(SleepStoreError.unknownReturnConfiguration))
            }
        }
        healthStore.execute(query)
    }
}

extension Date {
    fileprivate func timeOfDayInSeconds(sampleTimeZone: TimeZone) -> Int {
        var calendar = Calendar.current
        calendar.timeZone = sampleTimeZone
        
        let dateComponents = calendar.dateComponents([.hour, .minute, .second], from: self)
        let dateSeconds = dateComponents.hour! * 3600 + dateComponents.minute! * 60 + dateComponents.second!

        return dateSeconds
    }
}
