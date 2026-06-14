import Foundation
import CoreData

/// CoreData-backed cache for synced lyrics, keyed by `Track.id`
/// (Section 7.5 cache strategy).
///
/// The model is built programmatically (no `.xcdatamodeld`) so the package
/// has no Xcode-only build steps. A single `CachedLyrics` entity stores the
/// raw LRC text, its source (LRCLIB vs. user-imported), and a timestamp used
/// for the 30-day eviction policy.
final class LyricsCache {
    enum Source: String {
        case lrclib
        case userImported
    }

    private let container: NSPersistentContainer

    /// - Parameter inMemory: when `true`, backs the store with `/dev/null`
    ///   (a fresh, throwaway SQLite store) instead of the on-disk cache file.
    ///   Used by unit tests so they don't touch the user's real cache.
    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(name: "IslandSoundLyrics", managedObjectModel: Self.makeModel())
        let description = NSPersistentStoreDescription(url: inMemory ? URL(fileURLWithPath: "/dev/null") : Self.storeURL)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error {
                print("[LyricsCache] failed to load persistent store: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    // MARK: - Public API

    /// Returns cached raw LRC text for `trackId`, or `nil` on a cache miss.
    /// User-imported lyrics take priority over LRCLIB-fetched ones, but
    /// since each `trackId` has at most one row (last-write-wins on
    /// `store`), a plain lookup is sufficient.
    func fetch(trackId: String) async -> String? {
        let context = container.newBackgroundContext()
        return await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedLyrics")
            request.predicate = NSPredicate(format: "trackId == %@", trackId)
            request.fetchLimit = 1
            let object = try? context.fetch(request).first
            return object?.value(forKey: "rawLRC") as? String
        }
    }

    /// Stores (or replaces) the cached LRC text for `trackId`.
    func store(trackId: String, raw: String, source: Source) async {
        let context = container.newBackgroundContext()
        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedLyrics")
            request.predicate = NSPredicate(format: "trackId == %@", trackId)
            request.fetchLimit = 1

            let object: NSManagedObject
            if let existing = try? context.fetch(request).first {
                object = existing
            } else {
                object = NSEntityDescription.insertNewObject(forEntityName: "CachedLyrics", into: context)
            }

            object.setValue(trackId, forKey: "trackId")
            object.setValue(raw, forKey: "rawLRC")
            object.setValue(source.rawValue, forKey: "source")
            object.setValue(Date(), forKey: "cachedAt")

            try? context.save()
        }
    }

    /// Deletes entries older than 30 days, but only once the on-disk store
    /// exceeds 50MB (Section 7.5 cache eviction rule). Safe to call on every
    /// launch.
    func purgeExpiredEntries() {
        let context = container.newBackgroundContext()
        context.perform {
            let attributes = try? FileManager.default.attributesOfItem(atPath: Self.storeURL.path)
            guard let size = attributes?[.size] as? Int, size > 50 * 1024 * 1024 else { return }

            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedLyrics")
            request.predicate = NSPredicate(format: "cachedAt < %@", cutoff as NSDate)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            _ = try? context.execute(deleteRequest)
            try? context.save()
        }
    }

    // MARK: - Storage location

    private static var storeURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandSound", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("LyricsCache.sqlite")
    }

    // MARK: - Programmatic model

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let entity = NSEntityDescription()
        entity.name = "CachedLyrics"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let trackId = NSAttributeDescription()
        trackId.name = "trackId"
        trackId.attributeType = .stringAttributeType
        trackId.isOptional = false

        let rawLRC = NSAttributeDescription()
        rawLRC.name = "rawLRC"
        rawLRC.attributeType = .stringAttributeType
        rawLRC.isOptional = false

        let source = NSAttributeDescription()
        source.name = "source"
        source.attributeType = .stringAttributeType
        source.isOptional = false

        let cachedAt = NSAttributeDescription()
        cachedAt.name = "cachedAt"
        cachedAt.attributeType = .dateAttributeType
        cachedAt.isOptional = false

        entity.properties = [trackId, rawLRC, source, cachedAt]
        model.entities = [entity]
        return model
    }
}
