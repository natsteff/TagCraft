import Foundation
import SQLite3

enum SQLValue {
    case null, integer(Int64), real(Double), text(String), blob(Data)
    var string: String { if case .text(let value) = self { return value }; return "" }
    var int: Int64 { if case .integer(let value) = self { return value }; return 0 }
    var double: Double? {
        switch self { case .real(let value): return value; case .integer(let value): return Double(value); default: return nil }
    }
    var data: Data? { if case .blob(let value) = self { return value }; return nil }
    var optionalString: String? { if case .text(let value) = self { return value }; return nil }
    static func optional(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }
    static func optional(_ value: Double?) -> SQLValue { value.map(SQLValue.real) ?? .null }
    static func optional(_ value: Int?) -> SQLValue { value.map { .integer(Int64($0)) } ?? .null }
}
final class SQLiteConnection {
    private(set) var handle: OpaquePointer?
    init(_ url: URL) throws {
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else { let message = error(); if let handle { sqlite3_close_v2(handle) }; handle = nil; throw message }
        sqlite3_busy_timeout(handle, 5_000)
        sqlite3_create_function_v2(handle, "tagcraft_trim", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, count, arguments in
            guard count == 1, let argument = arguments?[0], let bytes = sqlite3_value_text(argument) else { sqlite3_result_null(context); return }
            let value = String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_value_bytes(argument))), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            value.withCString { sqlite3_result_text(context, $0, Int32(value.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }, nil, nil, nil)
        do {
            try execute("PRAGMA foreign_keys=ON;")
        } catch { if let handle { sqlite3_close_v2(handle) }; handle = nil; throw error }
    }
    deinit { if let handle { sqlite3_close_v2(handle) } }
    func error() -> TagError { TagError(message: "Statistics database: " + (handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database")) }
    func execute(_ sql: String) throws { guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() } }
    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var pointer: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &pointer, nil) == SQLITE_OK, let pointer else { throw error() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1), result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(pointer, position)
            case .integer(let number): result = sqlite3_bind_int64(pointer, position, number)
            case .real(let number): result = sqlite3_bind_double(pointer, position, number)
            case .text(let string): result = string.withCString { sqlite3_bind_text(pointer, position, $0, Int32(string.utf8.count), transient) }
            case .blob(let data): result = data.withUnsafeBytes { sqlite3_bind_blob(pointer, position, $0.baseAddress, Int32($0.count), transient) }
            }
            if result != SQLITE_OK { sqlite3_finalize(pointer); throw error() }
        }
        return pointer
    }
    func run(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
    }
    func rows(_ sql: String, _ values: [SQLValue] = [], _ visit: ([SQLValue]) throws -> Void) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw error() }
            let row = (0..<sqlite3_column_count(statement)).map { column -> SQLValue in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT:
                    guard let bytes = sqlite3_column_text(statement, column) else { return .text("") }
                    return .text(String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    return .blob(sqlite3_column_blob(statement, column).map { Data(bytes: $0, count: count) } ?? Data())
                default: return .null
                }
            }
            try visit(row)
        }
    }
    func first(_ sql: String, _ values: [SQLValue] = []) throws -> [SQLValue]? {
        var result: [SQLValue]?
        try rows(sql, values) { if result == nil { result = $0 } }
        return result
    }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        if sqlite3_get_autocommit(handle) == 0 { return try body() }
        try execute("BEGIN IMMEDIATE")
        do { let value = try body(); try execute("COMMIT"); return value }
        catch { try? execute("ROLLBACK"); throw error }
    }
    var insertedID: Int64 { sqlite3_last_insert_rowid(handle) }
    func withCancellation<T>(_ cancel: JobCancellation, _ body: () throws -> T) throws -> T {
        let context = Unmanaged.passUnretained(cancel).toOpaque()
        sqlite3_progress_handler(handle, 1_000, { raw in
            guard let raw else { return 0 }
            return Unmanaged<JobCancellation>.fromOpaque(raw).takeUnretainedValue().isCancelled ? 1 : 0
        }, context)
        defer { sqlite3_progress_handler(handle, 0, nil, nil) }
        try cancel.check(); return try body()
    }
    func closeForPublication() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;")
        if let handle { guard sqlite3_close(handle) == SQLITE_OK else { throw error() } }
        handle = nil
    }
}
