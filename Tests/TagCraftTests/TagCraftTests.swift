import XCTest
@testable import TagCraft
final class TagCraftTests: XCTestCase {
    func testClean() throws {
        XCTAssertEqual(try FilenameCleaner.clean("some_ARTIST - some_TRACK.mp3"), "Some Artist - Some Track.mp3")
        XCTAssertEqual(try FilenameCleaner.clean("a__b - c...d.MP3"), "A B - C D.mp3")
    }
    func testLibrary() throws {
        let root = URL(fileURLWithPath: "/Music")
        XCTAssertEqual(try LibraryPath.destination(root: root, artist: "Édith Piaf", filename: "x.mp3").path, "/Music/E/Édith Piaf/x.mp3")
        XCTAssertEqual(try LibraryPath.destination(root: root, artist: "10cc", filename: "x.mp3").path, "/Music/0-9/10cc/x.mp3")
        XCTAssertThrowsError(try LibraryPath.destination(root: root, artist: " ", filename: "x.mp3"))
    }
    func testTagRoundtripPreservesAudioAndArtwork() throws {
        let audio = Data([255,251,17,42,0,33])
        var parsed = try ID3(audio)
        parsed.frames = [.init(id: "APIC", payload: Data([0,1,2,3]), flags: Data([0,0]))]
        let tags = Tags(title: "Héllo", artist: "Artist", album: "Album", albumArtist: "Band", year: "2009", genre: "Rock", track: "1/11")
        let saved = parsed.writing(tags, original: audio)
        let read = try ID3(saved)
        XCTAssertEqual(read.tags, tags)
        XCTAssertEqual(saved.dropFirst(read.audioOffset), audio)
        XCTAssertEqual(read.frames.first { $0.id == "APIC" }?.payload, Data([0,1,2,3]))
    }
    func testRejectUnsupported() {
        XCTAssertThrowsError(try ID3(Data([73,68,51,2,0,0,0,0,0,0])))
        XCTAssertThrowsError(try ID3(Data([73,68,51,3,0,128,0,0,0,0])))
    }
}
