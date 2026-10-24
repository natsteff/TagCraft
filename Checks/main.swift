import Foundation
func check(_ condition: Bool, line: UInt = #line) { precondition(condition, "Failed check at line \(line)") }
check(try FilenameCleaner.clean("some_ARTIST - some_TRACK.mp3") == "Some Artist - Some Track.mp3")
check(try FilenameCleaner.clean("a__b - c...d.MP3") == "A B - C D.mp3")
let root = URL(fileURLWithPath: "/Music")
check(try LibraryPath.destination(root: root, artist: "Édith Piaf", filename: "x.mp3").path == "/Music/E/Édith Piaf/x.mp3")
check(try LibraryPath.destination(root: root, artist: "10cc", filename: "x.mp3").path == "/Music/0-9/10cc/x.mp3")
let audio = Data([255,251,17,42,0,33])
for version in [3,4] {
    var parsed = try ID3(audio)
    parsed.version = version
    parsed.frames = [.init(id: "APIC", payload: Data([0,1,2,3]), flags: Data([0,0]))]
    let tags = Tags(title: "Héllo", artist: "Artist", album: "Album", albumArtist: "Band", year: "2009", genre: "Rock", track: "1/11")
    let saved = parsed.writing(tags, original: audio)
    let read = try ID3(saved)
    check(read.tags == tags)
    check(saved.dropFirst(read.audioOffset) == audio)
    check(read.frames.first { $0.id == "APIC" }?.payload == Data([0,1,2,3]))
}
check((try? ID3(Data([73,68,51,2,0,0,0,0,0,0]))) == nil)
print("Core checks passed: filename cleanup, library paths, ID3v2.3/v2.4 roundtrips, artwork and audio preservation, unsupported-version rejection.")

check((try? FilenameCleaner.clean("unknown.mp3")) == nil)
check(try FilenameCleaner.clean("unknown.mp3", tags: Tags(title: "a_song", artist: "some.artist")) == "Some Artist - A Song.mp3")
let parts = try FilenameCleaner.parts("AC-DC - Song - Live.mp3")
check(parts.artist == "AC-DC" && parts.title == "Song - Live")
check((try? FilenameCleaner.parts("Artist - .mp3")) == nil)
print("Standard filename, fallback, delimiter extraction and missing-field checks passed.")

for version in [3,4] {
    var parsed = try ID3(audio)
    parsed.version = version
    var expanded = Tags(title: "Song", artist: "Artist")
    for field in Tags.extraFields { expanded.extra[field.id] = "Value \(field.label)" }
    let written = parsed.writing(expanded, original: audio)
    let reread = try ID3(written)
    check(reread.tags == expanded)
    check(written.dropFirst(reread.audioOffset) == audio)
    var cleared = expanded
    cleared.extra.removeValue(forKey: "TCOM")
    check(try ID3(reread.writing(cleared, original: written)).tags == cleared)
}
print("All additional fields, including Lyrics, roundtrip and clear correctly in ID3v2.3 and v2.4.")

let existing = Tags(album: "Keep Me", genre: "Rock")
let standard = try FilenameMask(FilenameMask.masks[0]).extract("Artist - Song - Live.mp3", existing: existing)
check(standard.artist == "Artist" && standard.title == "Song - Live" && standard.album == "Keep Me")
let reversed = try FilenameMask(FilenameMask.masks[1]).extract("Song - Artist.mp3", existing: existing)
check(reversed.title == "Song" && reversed.artist == "Artist")
let numbered = try FilenameMask(FilenameMask.masks[2]).extract("03 - Artist - Song.mp3", existing: existing)
check(numbered.track == "03" && numbered.artist == "Artist" && numbered.title == "Song")
let custom = try FilenameMask("{Artist} - {Title} ({Year}) [{Disc}]").extract("Édith - Song (2001) [2].mp3", existing: existing)
check(custom.artist == "Édith" && custom.year == "2001" && custom.extra["TPOS"] == "2")
let skipped = try FilenameMask("{Skip}__{Title}__{Skip}").extract("ignore__Song__ignore.mp3", existing: existing)
check(skipped.title == "Song" && skipped.genre == "Rock")
check((try? FilenameMask("{Artist}{Title}")) == nil)
check((try? FilenameMask("{Artist} - {Artist}")) == nil)
check((try? FilenameMask("{Unknown}")) == nil)
check((try? FilenameMask("{Skip}")) == nil)
check((try? FilenameMask(FilenameMask.masks[2]).extract("bad - Artist - Song.mp3", existing: existing)) == nil)
check((try? FilenameMask(FilenameMask.masks[0]).extract("No separator.mp3", existing: existing)) == nil)
print("Preset and custom filename masks passed, including literals, ignored parts, Unicode, invalid masks and unmatched filenames.")

var renameTags = Tags(title: "Song", artist: "Artist", album: "Album", year: "2001", track: "03")
renameTags.extra["TCOM"] = "Composer"
check(try FilenameTemplate(FilenameMask.masks[0]).filename(tags: renameTags) == "Artist - Song.mp3")
check(try FilenameTemplate(FilenameMask.masks[1]).filename(tags: renameTags) == "Song - Artist.mp3")
check(try FilenameTemplate(FilenameMask.masks[2]).filename(tags: renameTags) == "03 - Artist - Song.mp3")
check(try FilenameTemplate("{Artist} - {Album} - {Title} ({Year}) [{Composer}]").filename(tags: renameTags) == "Artist - Album - Song (2001) [Composer].mp3")
check(try FilenameTemplate("{Artist}{Title}-{Artist}").filename(tags: renameTags) == "ArtistSong-Artist.mp3")
check((try? FilenameTemplate("{Skip}")) == nil)
check((try? FilenameTemplate("{Unknown}")) == nil)
check((try? FilenameTemplate("{Artist}/{Title}")) == nil)
check((try? FilenameTemplate("{Artist")) == nil)
check((try? FilenameTemplate("{Artist} - {Title}").filename(tags: Tags(artist: "Artist"))) == nil)
renameTags.artist = "Artist/Name"
check(try FilenameTemplate("{Artist} - {Title}").filename(tags: renameTags) == "Artist_Name - Song.mp3")
renameTags.title = String(repeating: "a", count: 260)
check((try? FilenameTemplate("{Title}").filename(tags: renameTags)) == nil)
print("Rename-from-tags presets and custom masks passed, including repeated variables, missing tags, unsafe paths and excessive filename length.")

let parenthetical = try FilenameMask("{Artist} - {Title} - {Skip}").extract("p o m e - Angel Wings (from President, Acoustic AI Cover - Remix) - this is garbage.mp3", existing: existing)
check(parenthetical.artist == "p o m e")
check(parenthetical.title == "Angel Wings (from President, Acoustic AI Cover")
let nested = try FilenameMask("{Artist} - {Title} - {Skip}").extract("Artist - Song [Live (Part - Two) - Mix] - junk.mp3", existing: existing)
check(nested.title == "Song [Live (Part")
let explicit = try FilenameMask("{Title} ({Year}) - {Artist}").extract("Song (2001) - Artist.mp3", existing: existing)
check(explicit.title == "Song" && explicit.year == "2001" && explicit.artist == "Artist")
print("Literal separator regression checks passed.")
let sampleStem = "p o m e - Angel Wings (from President, Acoustic AI Cover - Remix) - this is garbage"
let oldParser = try NSRegularExpression(pattern: "^(.+?) - (.+?) - (.+)$")
let oldMatch = oldParser.firstMatch(in: sampleStem, range: NSRange(location: 0, length: (sampleStem as NSString).length))!
let oldTitle = (sampleStem as NSString).substring(with: oldMatch.range(at: 2))
check(oldTitle == "Angel Wings (from President, Acoustic AI Cover")
print("Reproduced old title: \(oldTitle)")
print("Literal-mask title: \(parenthetical.title)")

let reviewMask = try FilenameMask("{Artist} - {Title} - {Skip}")
let review = reviewMask.review(sampleStem + ".mp3")
check(review.warning != nil)
check(review.ignored == ["Remix) - this is garbage"])
check(try FilenameMask("{Artist} ({Title})").extract("Artist (Song)", existing: existing).title == "Song")
check(try FilenameMask("{Artist} ({Title})").review("Artist (Song).mp3").warning == nil)
check(reviewMask.review("Artist - Song - Junk.mp3").warning == nil)
print("Literal parentheses delimiters, yellow-review diagnostics and ignored-value checks passed.")

for (group, open, close) in [("()", "(", ")"), ("{}", "{", "}"), ("[]", "[", "]")] {
    let name = "Artist - Song " + open + "Live - Remix" + close + " - Junk.mp3"
    let enabled = try FilenameMask("{Artist} - {Title} - {Skip}", ignoredGroups: [group])
    check(try enabled.extract(name, existing: existing).title == "Song " + open + "Live - Remix" + close)
    check(enabled.review(name).ignored == ["Junk"])
    check(enabled.review(name).warning == nil)
    check(try FilenameMask("{Artist} - {Title} - {Skip}").extract(name, existing: existing).title == "Song " + open + "Live")
}
let allGroups = try FilenameMask("{Artist} - {Title} - {Skip}", ignoredGroups: ["()", "{}", "[]"])
check(try allGroups.extract("Artist - Song (Live [Part - Two] - Mix) - Junk.mp3", existing: existing).title == "Song (Live [Part - Two] - Mix)")
let structural = try FilenameMask("{Artist} ({Title})", ignoredGroups: ["()"])
check(try structural.extract("Artist (Song).mp3", existing: existing).title == "Song")
check(allGroups.review("Artist - Song (Live - Junk.mp3").warning != nil)
print("Independent delimiter-group settings, nested groups, explicit mask delimiters and warning consistency passed.")

for version in [3,4] {
    var parsed = try ID3(audio)
    parsed.version = version
    parsed.frames = [
        .init(id: "COMM", payload: Data([0,101,110,103,0,65]), flags: Data([0,0])),
        .init(id: "COMM", payload: Data([0,101,110,103,0,66]), flags: Data([0,0])),
        .init(id: "APIC", payload: Data([1,2,3]), flags: Data([0,0])),
        .init(id: "PRIV", payload: Data([4,5,6]), flags: Data([0,0]))]
    let tagged = parsed.writing(Tags(title: "Keep", artist: "Remove"), original: audio)
    let read = try ID3(tagged)
    let purged = read.purging(["COMM", "TPE1"], original: tagged)
    let verified = try ID3(purged)
    check(verified.tags.title == "Keep" && verified.tags.artist.isEmpty)
    check(!verified.frames.contains { $0.id == "COMM" })
    check(verified.frames.first { $0.id == "APIC" }?.payload == Data([1,2,3]))
    check(verified.frames.first { $0.id == "PRIV" }?.payload == Data([4,5,6]))
    check(purged.dropFirst(verified.audioOffset) == audio)
    check(read.purging(Set(read.frames.map(\.id)), original: tagged) == audio)
}
var legacy = Data(repeating: 0, count: 128)
legacy.replaceSubrange(0..<3, with: Data("TAG".utf8))
legacy[3] = 65; legacy[33] = 66; legacy[97] = 67; legacy[126] = 3; legacy[127] = 17
var legacyFile = audio; legacyFile.append(legacy)
let clearedLegacy = try ID3(legacyFile).purging(["TPE1", "COMM", "TRCK", "TCON"], original: legacyFile)
check(ID3.legacyFields(clearedLegacy) == ["TIT2"])
check(clearedLegacy.prefix(audio.count) == audio)
print("Purge checks passed: duplicate frames removed, untouched tags and audio preserved, empty v2 tag removed, selected legacy v1 fields cleared.")

func sameFiles(_ first: [URL], _ second: [URL]) -> Bool { Set(first.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }) == Set(second.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }) }
let sandbox = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("TagCraft-scan-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: sandbox) }
let nestedLibrary = sandbox.appendingPathComponent("Library/A/Artist")
try FileManager.default.createDirectory(at: nestedLibrary, withIntermediateDirectories: true)
let direct = sandbox.appendingPathComponent("Direct.mp3")
let nestedTrack = nestedLibrary.appendingPathComponent("Nested.mp3")
try audio.write(to: direct); try audio.write(to: nestedTrack)
check(sameFiles(SourceFiles.mp3URLs(root: sandbox), [direct]))
check(sameFiles(SourceFiles.mp3URLs(root: sandbox, includeSubfolders: true), [direct, nestedTrack]))
check(sameFiles(SourceFiles.mp3URLs(root: nestedLibrary), [nestedTrack]))
check(!SourceFiles.includes(nestedTrack, root: sandbox))
check(SourceFiles.includes(nestedTrack, root: sandbox, includeSubfolders: true))
let moved = nestedLibrary.appendingPathComponent("Direct.mp3")
try FileManager.default.moveItem(at: direct, to: moved)
check(SourceFiles.mp3URLs(root: sandbox).isEmpty)
check(sameFiles(SourceFiles.mp3URLs(root: sandbox, includeSubfolders: true), [nestedTrack, moved]))
try FileManager.default.moveItem(at: moved, to: direct)
check(sameFiles(SourceFiles.mp3URLs(root: sandbox), [direct]))
print("Folder scope checks passed: direct files by default, all subfolders when enabled, move/refresh/undo follow selected scope.")

var rules = CleanRules()
check(try rules.clean("r.e.m. - losing_my.religion.mp3", tags: Tags()).0 == "R.E.M. - Losing My Religion.mp3")
check(try rules.clean("abba - version 2.0.mp3", tags: Tags()).0 == "ABBA - Version 2.0.mp3")
check(try rules.clean("blink-182 - the_rock.show.mp3", tags: Tags()).0 == "blink-182 - The Rock Show.mp3")
check(try rules.clean("artist - song (Live Remix).mp3", tags: Tags()).0 == "Artist - Song (Live Remix).mp3")
rules.removeSuffixes = true
check(try rules.clean("artist - song (Official Video).mp3", tags: Tags()).0 == "Artist - Song.mp3")
check(try rules.clean("artist - song (Acoustic).mp3", tags: Tags()).0 == "Artist - Song (Acoustic).mp3")
rules.removeTrackPrefix = true
check(try rules.clean("03 - artist - song.mp3", tags: Tags()).0 == "03 - Artist - Song.mp3")
rules.capitalization = false
check(try rules.clean("abba - SONG.mp3", tags: Tags()).0 == "abba - SONG.mp3")
check(LibraryTools.suggestions("Metalica", names: ["Metallica", "Muse"]) == ["Metallica"])
check(LibraryTools.suggestions("R E M", names: ["R.E.M."]) == ["R.E.M."])
let jobRoot = FileManager.default.temporaryDirectory.appendingPathComponent("TagCraft-jobs-" + UUID().uuidString)
try FileManager.default.createDirectory(at: jobRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: jobRoot) }
let jobSource = jobRoot.appendingPathComponent("one.mp3")
let jobDestination = jobRoot.appendingPathComponent("Artist - Song.mp3")
let jobData = try ID3(audio).writing(Tags(title: "Old", artist: "Artist"), original: audio)
try jobData.write(to: jobSource)
let jobStamp = FileJobs.fingerprint(jobSource)
let cancelJob = JobCancellation()
let result = FileJobs.run([.init(source: jobSource, destination: jobDestination, tags: Tags(title: "Song", artist: "Artist"), expectedSize: jobStamp.0, expectedDate: jobStamp.1)], cancellation: cancelJob) { _,_,_ in }
check(result.count == 1 && result[0].error == nil)
check(!FileManager.default.fileExists(atPath: jobSource.path))
check(try ID3(Data(contentsOf: jobDestination)).tags.title == "Song")
let hashOne = try FileJobs.hash(jobDestination, audioOnly: true, cancellation: cancelJob)
let alternate = jobRoot.appendingPathComponent("different-tags.mp3")
try ID3(audio).writing(Tags(title: "Other", artist: "Another"), original: audio).write(to: alternate)
check(try FileJobs.hash(alternate, audioOnly: true, cancellation: cancelJob) == hashOne)
check(try FileJobs.hash(alternate, audioOnly: false, cancellation: cancelJob) != FileJobs.hash(jobDestination, audioOnly: false, cancellation: cancelJob))
let snapshot = try LibraryTools.statistics(jobRoot, cancellation: cancelJob) { _,_ in }
check(snapshot.tracks == 2 && snapshot.artistCount == 2)
check(snapshot.bytes == Int64((try Data(contentsOf: alternate)).count + (try Data(contentsOf: jobDestination)).count))
check(snapshot.genres.first?.name == "Unknown")
let conflict = FileJobs.run([.init(source: alternate, destination: jobDestination)], cancellation: cancelJob) { _,_,_ in }
check(conflict.first?.error != nil)
let cancelled = JobCancellation(); cancelled.cancel()
check(FileJobs.run([.init(source: alternate, destination: jobRoot.appendingPathComponent("never.mp3"))], cancellation: cancelled) { _,_,_ in }.isEmpty)
check((try? LibraryTools.statistics(jobRoot, cancellation: cancelled) { _,_ in }) == nil)
let changed = FileJobs.run([.init(source: alternate, destination: alternate, tags: Tags(title: "Wrong"), expectedSize: 1)], cancellation: cancelJob) { _,_,_ in }
check(changed.first?.error != nil)
print("Advanced Clean rules, artist suggestions, background write/rename, duplicate audio hashes, statistics, collisions, stale previews and cancellation checks passed.")

var preparation = WorkflowPreset()
preparation.cleanRules = CleanRules()
preparation.move = true
let workflowRoot = jobRoot.appendingPathComponent("Organized")
let raw = jobRoot.appendingPathComponent("abba - new_song (Official Video).mp3")
try ID3(audio).writing(Tags(title: "Wrong", artist: "Wrong", genre: "Keep"), original: audio).write(to: raw)
preparation.cleanRules.removeSuffixes = true
let staged = try WorkflowPlanner.preview([.init(url: raw, tags: try ID3(Data(contentsOf: raw)).tags)], preset: preparation, library: workflowRoot, cancellation: cancelJob) { _,_ in }
check(staged.count == 1 && staged[0].issue == nil)
check(staged[0].plan?.destination.path.hasSuffix("A/ABBA/ABBA - New Song.mp3") == true)
let prepared = FileJobs.run([staged[0].plan!], cancellation: cancelJob) { _,_,_ in }
check(prepared[0].error == nil)
let preparedData = try Data(contentsOf: prepared[0].destination)
let preparedTags = try ID3(preparedData)
check(preparedTags.tags.artist == "ABBA" && preparedTags.tags.title == "New Song" && preparedTags.tags.genre == "Keep")
check(preparedData.dropFirst(preparedTags.audioOffset) == audio)
var impossible = preparation; impossible.purge = true; impossible.purgeIDs = ["TPE1"]
let invalidPlan = try WorkflowPlanner.preview([.init(url: alternate, tags: try ID3(Data(contentsOf: alternate)).tags)], preset: impossible, library: workflowRoot, cancellation: cancelJob) { _,_ in }
check(invalidPlan[0].issue != nil)
let pngStub = Data([137,80,78,71,13,10,26,10,0,1,2,3])
let artSet = FileJobs.run([.init(source: alternate, destination: alternate, artwork: pngStub)], cancellation: cancelJob) { _,_,_ in }
check(artSet.first?.error == nil)
check(try ID3(Data(contentsOf: alternate)).artworkData == pngStub)
let artClear = FileJobs.run([.init(source: alternate, destination: alternate, removeArtwork: true)], cancellation: cancelJob) { _,_,_ in }
check(artClear.first?.error == nil)
check(try ID3(Data(contentsOf: alternate)).artworkData == nil)
// A rename failure after a tag write restores the original file contents.
let badParent = jobRoot.appendingPathComponent("NotAFolder")
try Data([1]).write(to: badParent)
let beforeFailure = try Data(contentsOf: alternate)
let rollback = FileJobs.run([.init(source: alternate, destination: badParent.appendingPathComponent("x.mp3"), tags: Tags(title: "Must Roll Back"))], cancellation: cancelJob) { _,_,_ in }
check(rollback.first?.error != nil)
check(try Data(contentsOf: alternate) == beforeFailure)
print("Workflow clean/extract/rename/move, invalid downstream fields, artwork replacement/removal and partial-failure rollback checks passed.")

check(try CleanRules().clean("U.S.A. - version 2.0.mp3", tags: Tags()).0 == "U.S.A. - Version 2.0.mp3")
let lower = jobRoot.appendingPathComponent("lowercase.mp3")
let upper = jobRoot.appendingPathComponent("Lowercase.mp3")
try audio.write(to: lower)
let recased = FileJobs.run([.init(source: lower, destination: upper)], cancellation: cancelJob) { _,_,_ in }
check(recased.first?.error == nil)
check(try Data(contentsOf: upper) == audio)
let duplicateReport = try LibraryTools.duplicates(jobRoot, inputs: [alternate], cancellation: cancelJob) { _,_ in }
check(duplicateReport.scanned >= 3 && duplicateReport.matches[alternate]?.contains("Artist - Song.mp3") == true)
let completeStats = try LibraryTools.statistics(jobRoot, cancellation: cancelJob) { _,_ in }
check(completeStats.artists.reduce(0) { $0 + $1.tracks } == completeStats.tracks)
check(completeStats.genres.reduce(Int64(0)) { $0 + $1.bytes } == completeStats.bytes)
let workflowEncoded = try JSONEncoder().encode(preparation)
check(try JSONDecoder().decode(WorkflowPreset.self, from: workflowEncoded).cleanRules == preparation.cleanRules)
print("Case-only renames, preserved dotted initials, library duplicate reports, statistics totals and saved-workflow serialization checks passed.")
let beforeDiff = "artist - the_song.mp3"
let afterDiff = "Artist - The Song.mp3"
let exactDiff = CharacterDiff.segments(before: beforeDiff, after: afterDiff, proposed: true)
check(exactDiff.map(\.0).joined() == afterDiff)
check(exactDiff.filter { $0.1 }.map(\.0).joined() == "AT S")
check(CharacterDiff.segments(before: beforeDiff, after: beforeDiff, proposed: true).allSatisfy { !$0.1 })
print("Character-level preview highlighting checks passed.")
var websiteClean = CleanRules(); websiteClean.removeSuffixes = true
websiteClean.suffixes += "\nwww.example.com"
check(try websiteClean.clean("artist - song - www.example.com.mp3", tags: Tags()).0 == "Artist - Song.mp3")
check(try websiteClean.clean("artist - song - (Official Video).mp3", tags: Tags()).0 == "Artist - Song.mp3")
check(try websiteClean.clean("artist - song (Official Video) [Lyrics].mp3", tags: Tags()).0 == "Artist - Song.mp3")
print("Configured website labels and chained trailing-label cleanup checks passed.")

let savedSession = WorkspaceSession(workspace: "/Music/Incoming", library: "/Volumes/Library", recentWorkspaces: ["/Music/Incoming", "/Downloads"])
let sessionFile = jobRoot.appendingPathComponent("workspace-session.json")
try JSONEncoder().encode(savedSession).write(to: sessionFile, options: .atomic)
let restoredSession = try JSONDecoder().decode(WorkspaceSession.self, from: Data(contentsOf: sessionFile))
check(savedSession == restoredSession)
let clearedRecents = WorkspaceSession(workspace: restoredSession.workspace, library: restoredSession.library, recentWorkspaces: [])
check(try JSONDecoder().decode(WorkspaceSession.self, from: JSONEncoder().encode(clearedRecents)).recentWorkspaces.isEmpty)
check(clearedRecents.workspace == savedSession.workspace && clearedRecents.library == savedSession.library)
print("Version-independent workspace session roundtrip and clearing recents without clearing current workspace checks passed.")

var rawRules = CleanRules()
check(try rawRules.clean("raw_title_only.mp3", tags: Tags(title: "Do Not Use", artist: "Do Not Use")).0 == "Raw Title Only.mp3")
check(try rawRules.clean("03_artist_name-song_title.mp3", tags: Tags()).0 == "03 - Artist Name - Song Title.mp3")
check(try rawRules.clean("title-artist.mp3", tags: Tags()).0 == "Title - Artist.mp3")
check(try rawRules.clean("blink-182-song.mp3", tags: Tags()).0 == "blink-182 - Song.mp3")
check(try rawRules.clean("AC-DC - song.mp3", tags: Tags()).0 == "AC-DC - Song.mp3")
print("Raw Clean preserves field order, ignores tags, supports title-only files and normalizes delimiters with protected artist hyphens.")

let magicRoot = jobRoot.appendingPathComponent("Magic")
try FileManager.default.createDirectory(at: magicRoot, withIntermediateDirectories: true)
func magicInput(_ filename: String, _ tags: Tags = Tags()) throws -> PreparationInput {
    let url = magicRoot.appendingPathComponent(filename)
    try ID3(audio).writing(tags, original: audio).write(to: url)
    return .init(url: url, tags: tags)
}
var intelligenceRules = CleanRules()
intelligenceRules.exceptions += "\nVNV Nation"
let cleanMagic = try magicInput("01_VNV.NATION-control_(official_video)_1080p.mp3")
let magicResult = try MagicAnalyzer.analyze([cleanMagic], rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(magicResult.count == 1)
check(magicResult[0].proposed.artist == "VNV Nation" && magicResult[0].proposed.title == "Control")
check(magicResult[0].proposed.track == "01")
check(magicResult[0].destination?.lastPathComponent == "VNV Nation - Control.mp3")
let reversedMagic = try magicInput("Control - VNV Nation.mp3")
let reverseResult = try MagicAnalyzer.analyze([reversedMagic], rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(reverseResult[0].proposed.artist == "VNV Nation" && reverseResult[0].proposed.title == "Control")
check(reverseResult[0].highConfidence && reverseResult[0].included)
let unknownMagic = try magicInput("Xylophonia - Zorblatt.mp3")
let uncertain = try MagicAnalyzer.analyze([unknownMagic], rules: intelligenceRules, libraryArtists: [], cancellation: cancelJob) { _,_ in }
check(!uncertain[0].highConfidence && !uncertain[0].included)
check(uncertain[0].alternatives.count >= 2)
let conflictMagic = try magicInput("VNV Nation - Control.mp3", Tags(title: "Different", artist: "Other Artist"))
let conflictMagicResult = try MagicAnalyzer.analyze([conflictMagic], rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(!conflictMagicResult[0].included && !conflictMagicResult[0].warnings.isEmpty)
let liveMagic = try magicInput("VNV Nation - Control (Live - Acoustic).mp3")
let liveResult = try MagicAnalyzer.analyze([liveMagic], rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(liveResult[0].proposed.title == "Control (Live - Acoustic)")
let abbreviationMagic = try magicInput("DJ - Something.mp3")
let weakAbbreviation = try MagicAnalyzer.analyze([abbreviationMagic], rules: intelligenceRules, libraryArtists: [], cancellation: cancelJob) { _,_ in }
check(!weakAbbreviation[0].included)
check((try? MagicAnalyzer.analyze([cleanMagic], rules: intelligenceRules, libraryArtists: [], cancellation: cancelled) { _,_ in }) == nil)
print("Intelligent Magic checks passed: cleanup, track inference, reverse layouts, library/exception spelling, alternatives, uncertainty, tag conflicts, recording labels, abbreviation caution and cancellation.")

let artOne = try magicInput("Artwork One.mp3", Tags(title: "One", artist: "Artist"))
let artTwo = try magicInput("Artwork Two.mp3", Tags(title: "Two", artist: "Artist"))
check(ArtworkSummary.read([artOne.url, artTwo.url]).data == nil)
let batchArtResult = FileJobs.run([artOne.url, artTwo.url].map { FilePlan(source: $0, destination: $0, artwork: pngStub) }, cancellation: cancelJob) { _,_,_ in }
check(batchArtResult.count == 2 && batchArtResult.allSatisfy { $0.error == nil })
check(ArtworkSummary.read([artOne.url, artTwo.url]).data == pngStub)
check(try ID3(Data(contentsOf: artOne.url)).tags.title == "One")
check(try ID3(Data(contentsOf: artTwo.url)).tags.title == "Two")
_ = FileJobs.run([.init(source: artTwo.url, destination: artTwo.url, removeArtwork: true)], cancellation: cancelJob) { _,_,_ in }
check(ArtworkSummary.read([artOne.url, artTwo.url]).kind.contains("Mixed"))
check(ArtworkSummary.read([]).count == 0)
print("Batch artwork checks passed: shared/absent/mixed summaries, multi-file image replacement and preserving each file's tags.")

var noOpWorkflow = WorkflowPreset()
noOpWorkflow.clean = false; noOpWorkflow.extract = false; noOpWorkflow.rename = false; noOpWorkflow.move = false
noOpWorkflow.purge = true; noOpWorkflow.purgeIDs = ["POPM"]
let noOpPreview = try WorkflowPlanner.preview([artOne], preset: noOpWorkflow, library: nil, cancellation: cancelJob) { _,_ in }
check(noOpPreview[0].plan == nil && noOpPreview[0].issue == "No change needed.")
noOpWorkflow.move = true
let movingPreview = try WorkflowPlanner.preview([artOne], preset: noOpWorkflow, library: workflowRoot, cancellation: cancelJob) { _,_ in }
check(movingPreview[0].statusText == "Will move")
print("Workflow no-op and move-only status checks passed.")

let correctMagic = try magicInput("VNV Nation - Standing.mp3", Tags(title: "Standing", artist: "VNV Nation"))
let correctResult = try MagicAnalyzer.analyze([correctMagic], rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(!correctResult[0].hasChanges && !correctResult[0].included)
let contextFolder = magicRoot.appendingPathComponent("VNV Nation/Empires/CD2")
try FileManager.default.createDirectory(at: contextFolder, withIntermediateDirectories: true)
var contextual: [PreparationInput] = []
for name in ["01 - Standing.mp3", "02 - Control.mp3"] {
    let url = contextFolder.appendingPathComponent(name)
    try ID3(audio).writing(Tags(), original: audio).write(to: url)
    contextual.append(.init(url: url, tags: Tags()))
}
let contextualResult = try MagicAnalyzer.analyze(contextual, rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(contextualResult[0].proposed.artist == "VNV Nation")
check(contextualResult[0].proposed.album == "Empires" && contextualResult[0].proposed.extra["TPOS"] == "2")
check(contextualResult[0].proposed.title == "Standing" && contextualResult[0].proposed.track == "01")
check(!contextualResult[0].included && contextualResult[0].reasons.contains { $0.contains("consecutive") })
check(!MusicContext.usefulFolder("Downloads") && !MusicContext.usefulFolder("2024"))
let versionInput = try magicInput("VNV Nation - Standing - Extended Mix.mp3")
let versionResult = try MagicAnalyzer.analyze([versionInput], rules: intelligenceRules, libraryArtists: ["VNV Nation"], cancellation: cancelJob) { _,_ in }
check(versionResult[0].alternatives.contains { $0.title == "Standing (Extended Mix)" })
let featuredInput = try magicInput("Artist feat. Guest - Song.mp3")
let featuredResult = try MagicAnalyzer.analyze([featuredInput], rules: intelligenceRules, libraryArtists: [], cancellation: cancelJob) { _,_ in }
check(featuredResult[0].alternatives.contains { $0.title.localizedCaseInsensitiveContains("feat. Guest") })
check(!featuredResult[0].included)
check(MixedTagValues.value("Title", in: [Tags(title: "One"), Tags(title: "Two")]).mixed)
check(MixedTagValues.value("Artist", in: [Tags(artist: "Same"), Tags(artist: "Same")]).value == "Same")
let badQuality = TagQuality.findings(path: "/test.mp3", tags: Tags(title: " Song ", artist: "Artist", year: "3020", track: "7/3"), artwork: false)
check(badQuality.contains { $0.field == "Year" } && badQuality.contains { $0.field == "Track" })
check(badQuality.contains { $0.field == "Title" && $0.suggestion == "Song" && $0.original == " Song " })
check(badQuality.contains { $0.field == "Artwork" })
let healthRecords = [LibraryRecord(path: "/Album/one.mp3", bytes: 10, tags: Tags(title: "One", artist: "VNV Nation", album: "Empires", albumArtist: "VNV Nation"), hasArtwork: true), LibraryRecord(path: "/Album/two.mp3", bytes: 20, tags: Tags(title: "Two", artist: "vnv nation", album: "Empires"), hasArtwork: false)]
check(TagQuality.consistency(healthRecords).contains { $0.field == "Artist" && $0.suggestion != nil })
check(TagQuality.consistency(healthRecords).contains { $0.field == "Album Artist" })
let healthSnapshot = LibraryScanner.summarize(URL(fileURLWithPath: "/Library"), records: healthRecords, includeAudio: false)
check(healthSnapshot.tracks == 2 && healthSnapshot.bytes == 30 && healthSnapshot.findings?.contains { $0.field == "Artwork" } == true)
check(CSVReport.encode([["A, B", "quote\"", "two\nlines"]]) == "\"A, B\",\"quote\"\"\",\"two\nlines\"\r\n")
check(CSVReport.inventory(healthSnapshot).count == 3)
let snapshotRoundTrip = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(healthSnapshot))
check(snapshotRoundTrip.records?.count == 2 && snapshotRoundTrip.findings?.count == healthSnapshot.findings?.count)

// Multiple-picture edits preserve back covers unless explicitly replaced/removed.
func pictureFrame(_ type: UInt8, _ data: Data) -> ID3.Frame {
    var payload = Data([0]); payload.append(Data("image/png".utf8)); payload.append(contentsOf: [0,type,0]); payload.append(data)
    return .init(id: "APIC", payload: payload, flags: Data([0,0]))
}
var multiID3 = try ID3(audio)
multiID3.frames = [pictureFrame(4, Data([7,8,9])), pictureFrame(3, pngStub)]
try multiID3.writing(Tags(title: "Keep"), original: audio).write(to: artOne.url)
check(try ID3(Data(contentsOf: artOne.url)).artworkData == pngStub)
_ = FileJobs.run([.init(source: artOne.url, destination: artOne.url, artwork: Data([9,8,7]))], cancellation: cancelJob) { _,_,_ in }
let preservedPictures = EmbeddedPicture.read(try ID3(Data(contentsOf: artOne.url)))
check(preservedPictures.count == 2 && preservedPictures.contains { $0.type == 4 && $0.data == Data([7,8,9]) })
_ = FileJobs.run([.init(source: artOne.url, destination: artOne.url, artwork: pngStub, replaceAllArtwork: true)], cancellation: cancelJob) { _,_,_ in }
check(EmbeddedPicture.read(try ID3(Data(contentsOf: artOne.url))).count == 1)
let masterPNG = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/BrandOriginal.png"))
check(try ArtworkImage.prepare(masterPNG, maxEdge: 0) == masterPNG)
let resizedArtwork = try ArtworkImage.prepare(masterPNG, maxEdge: 600)
check(ArtworkImage.details(resizedArtwork).contains("600 × 600"))
check((try? ArtworkImage.prepare(Data([1,2,3]), maxEdge: 600)) == nil)
print("Magic no-op/context/versions/features, mixed tags, quality suggestions, health, CSV, multiple artwork preservation and image resize checks passed.")

let firstScan = try await LibraryScanner.scan(magicRoot, previous: nil, reuse: true, includeAudio: false, cancellation: cancelJob) { _ in }
let reusedScan = try await LibraryScanner.scan(magicRoot, previous: firstScan, reuse: true, includeAudio: false, cancellation: cancelJob) { _ in }
check(reusedScan.reusedRecords == reusedScan.tracks && reusedScan.tracks == firstScan.tracks)
let changedURL = correctMagic.url
try ID3(audio).writing(Tags(title: "Changed", artist: "VNV Nation"), original: audio).write(to: changedURL)
let changedScan = try await LibraryScanner.scan(magicRoot, previous: reusedScan, reuse: true, includeAudio: false, cancellation: cancelJob) { _ in }
check(changedScan.reusedRecords == changedScan.tracks - 1)
check(changedScan.records?.first { URL(fileURLWithPath: $0.path).standardizedFileURL == changedURL.standardizedFileURL }?.tags.title == "Changed")
try FileManager.default.removeItem(at: changedURL)
let removedScan = try await LibraryScanner.scan(magicRoot, previous: changedScan, reuse: true, includeAudio: false, cancellation: cancelJob) { _ in }
check(removedScan.tracks == changedScan.tracks - 1)
let fullScan = try await LibraryScanner.scan(magicRoot, previous: removedScan, reuse: false, includeAudio: false, cancellation: cancelJob) { _ in }
check(fullScan.reusedRecords == 0)
check((try? await LibraryScanner.scan(magicRoot, previous: fullScan, reuse: true, includeAudio: false, cancellation: cancelled) { _ in }) == nil)
print("Manual statistics scanner checks passed: cached reuse, changed/deleted files, forced reread, snapshot serialization and cancellation.")

let audioLibrary = jobRoot.appendingPathComponent("Audio Scan")
try FileManager.default.createDirectory(at: audioLibrary, withIntermediateDirectories: true)
let audioFixture = URL(fileURLWithPath: "work/audio-fixture.mp3")
if FileManager.default.fileExists(atPath: audioFixture.path) {
    try FileManager.default.copyItem(at: audioFixture, to: audioLibrary.appendingPathComponent("Silence.mp3"))
    let audioScan = try await LibraryScanner.scan(audioLibrary, previous: nil, reuse: true, includeAudio: true, cancellation: cancelJob) { _ in }
    check((audioScan.durationSeconds ?? 0) > 0 && audioScan.records?.first?.audioRead == true)
    let audioReused = try await LibraryScanner.scan(audioLibrary, previous: audioScan, reuse: true, includeAudio: true, cancellation: cancelJob) { _ in }
    check(audioReused.reusedRecords == 1 && audioReused.durationSeconds == audioScan.durationSeconds)
    check(audioReused.bitrates?.first?.tracks == 1)
    print("Audio statistics scan and cached audio reuse checks passed.")
}
let oldSnapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(LibrarySnapshot(root: "/Old", updated: Date())))
check(oldSnapshot.records == nil && oldSnapshot.findings == nil)

try await SQLiteChecks.run()

// Placement rules must be identical for preview and execution destinations.
var structure = LibraryStructure()
structure.useLetterFolders = false
structure.defaultPlacement = .albums
structure.useIndividualFolder = true
structure.individualFolderName = "- Singles"
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", album: "Album", structure: structure).path == "/Music/Artist/Album/x.mp3")
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure).path == "/Music/Artist/- Singles/x.mp3")
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", album: "Album", structure: structure, placement: .individual).path == "/Music/Artist/- Singles/x.mp3")
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", album: "Album", structure: structure, placement: .direct).path == "/Music/Artist/x.mp3")
structure.useIndividualFolder = false
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure).path == "/Music/Artist/x.mp3")
structure.useIndividualFolder = true
for invalid in ["", "..", "a/b", "a:b", "a\\b"] {
    structure.individualFolderName = invalid
    check((try? LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure, placement: .individual)) == nil)
}
structure.individualFolderName = "Singles"
structure.useLetterFolders = true
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure, placement: .individual).path == "/Music/A/Artist/Singles/x.mp3")
check(try JSONDecoder().decode(LibraryStructure.self, from: JSONEncoder().encode(structure)) == structure)
print("Library structure checks passed: letter folders, albums, missing-album fallback, custom individual-track names, overrides and invalid paths.")

// Album and untagged-track placement are independent defaults.
structure.useLetterFolders = false
structure.defaultPlacement = .direct
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", album: "Album", structure: structure).path == "/Music/Artist/x.mp3")
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure).path == "/Music/Artist/Singles/x.mp3")
structure.defaultPlacement = .albums
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", album: "Album", structure: structure).path == "/Music/Artist/Album/x.mp3")
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure).path == "/Music/Artist/Singles/x.mp3")
structure.useIndividualFolder = false
check(try LibraryPath.destination(root: root, artist: "Artist", filename: "x.mp3", structure: structure).path == "/Music/Artist/x.mp3")
print("Independent album/individual-track default placement checks passed.")

var namingRules = CleanRules()
namingRules.exceptions = "DJ\nVNV Nation\nP!nk"
check(TagQuality.preferredArtist(["Dj Earworm": 20, "DJ Earworm": 1], rules: namingRules) == "DJ Earworm")
check(TagQuality.preferredArtist(["vnv nation": 20, "Vnv Nation": 1], rules: namingRules) == "VNV Nation")
check(TagQuality.preferredArtist(["Pnk": 20, "P!nk": 1], rules: namingRules) == "P!nk")
check(TagQuality.preferredArtist(["Adjective": 2, "ADJECTIVE": 1], rules: namingRules) == "Adjective")
check(TagQuality.preferredArtist(["O-Zone": 1, "O Zone": 2], rules: namingRules) == "O Zone")
let namingRecords = [LibraryRecord(path: "/a.mp3", bytes: 1, tags: Tags(artist: "DJ Earworm"), hasArtwork: false), LibraryRecord(path: "/b.mp3", bytes: 1, tags: Tags(artist: "Dj Earworm"), hasArtwork: false)]
let namingFindings = TagQuality.consistency(namingRecords, rules: namingRules)
check(namingFindings.count == 1 && namingFindings[0].path == "/b.mp3" && namingFindings[0].suggestion == "DJ Earworm" && namingFindings[0].reason == "Artist naming variations")
check(TagQuality.consistency([namingRecords[1]], rules: namingRules).isEmpty)
print("Artist naming exception precedence, boundaries, variation scope and fallback checks passed.")

let linkTest = FileManager.default.temporaryDirectory.appendingPathComponent("TagCraft-links-" + UUID().uuidString)
try FileManager.default.createDirectory(at: linkTest, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: linkTest) }
let linkLibrary = linkTest.appendingPathComponent("Library")
let linkOutside = linkTest.appendingPathComponent("Outside")
try FileManager.default.createDirectory(at: linkLibrary.appendingPathComponent("A"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: linkOutside, withIntermediateDirectories: true)
let linkedArtist = linkLibrary.appendingPathComponent("A/Artist")
try FileManager.default.createSymbolicLink(at: linkedArtist, withDestinationURL: linkOutside)
check(SymbolicLinks.isLink(linkedArtist))
check((try? LibraryPath.destination(root: linkLibrary, artist: "Artist", filename: "x.mp3")) == nil)
let linkSource = linkTest.appendingPathComponent("source.mp3")
try audio.write(to: linkSource)
let blockedMove = FileJobs.run([FilePlan(source: linkSource, destination: linkedArtist.appendingPathComponent("x.mp3"))], cancellation: JobCancellation()) { _,_,_ in }
check(blockedMove.first?.error?.contains("Symbolic links") == true)
check(try Data(contentsOf: linkSource) == audio)
check(!FileManager.default.fileExists(atPath: linkOutside.appendingPathComponent("x.mp3").path))
let linkedFile = linkLibrary.appendingPathComponent("linked.mp3")
try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: linkSource)
let danglingFile = linkLibrary.appendingPathComponent("dangling.mp3")
try FileManager.default.createSymbolicLink(at: danglingFile, withDestinationURL: linkTest.appendingPathComponent("missing.mp3"))
var skippedLinks = 0
check(SourceFiles.mp3URLs(root: linkLibrary, includeSubfolders: true, skippedLink: { skippedLinks += 1 }).isEmpty)
check(skippedLinks == 3)
let blockedWrite = FileJobs.run([FilePlan(source: linkedFile, destination: linkedFile, tags: Tags(title: "Changed"))], cancellation: JobCancellation()) { _,_,_ in }
check(blockedWrite.first?.error?.contains("Symbolic links") == true)
check(try Data(contentsOf: linkSource) == audio)
let plainLibrary = linkTest.appendingPathComponent("Plain")
try FileManager.default.createDirectory(at: plainLibrary, withIntermediateDirectories: true)
let originallySafe = try LibraryPath.destination(root: plainLibrary, artist: "Artist", filename: "x.mp3")
try FileManager.default.createDirectory(at: plainLibrary.appendingPathComponent("A"), withIntermediateDirectories: true)
try FileManager.default.createSymbolicLink(at: plainLibrary.appendingPathComponent("A/Artist"), withDestinationURL: linkOutside)
check(FileJobs.run([FilePlan(source: linkSource, destination: originallySafe)], cancellation: JobCancellation()) { _,_,_ in }.first?.error != nil)
check(try Data(contentsOf: linkSource) == audio)
print("Symbolic-link regression checks passed: preview refusal, apply-time recheck, linked/dangling files, directory traversal and unchanged external targets.")

check(UpdateVersion("0.6.1-alpha", build: 1)! > UpdateVersion("0.6.0-alpha", build: 99)!)
check(UpdateVersion("v0.6.0-alpha", build: 2)! > UpdateVersion("0.6.0-alpha", build: 1)!)
check(UpdateVersion("0.6.0")! > UpdateVersion("0.6.0-beta", build: 100)!)
check(UpdateVersion("0.6.0-beta")! > UpdateVersion("0.6.0-alpha", build: 100)!)
check(UpdateVersion("") == nil && UpdateVersion("0..1") == nil && UpdateVersion("0.6.0-unknown") == nil)
func updateFixture(_ tag: String, build: Int = 1, draft: Bool = false, prerelease: Bool = true, architecture: String = "arm64", host: String = "github.com") throws -> GitHubUpdateRelease {
    let object: [String: Any] = ["tag_name": tag, "name": "TagCraft " + tag, "body": "Version (Build \(build))", "draft": draft, "prerelease": prerelease,
        "html_url": "https://\(host)/natsteff/TagCraft/releases/tag/\(tag)",
        "assets": [["name": "TagCraft-macOS-\(architecture).dmg", "state": "uploaded", "browser_download_url": "https://\(host)/natsteff/TagCraft/releases/download/\(tag)/TagCraft-macOS-\(architecture).dmg"]]]
    return try JSONDecoder().decode(GitHubUpdateRelease.self, from: JSONSerialization.data(withJSONObject: object))
}
let alphaUpdate = try updateFixture("v0.6.1-alpha", build: 2)
let stableUpdate = try updateFixture("v0.6.0", prerelease: false)
let draftUpdate = try updateFixture("v9.0.0-alpha", draft: true)
let foreignUpdate = try updateFixture("v8.0.0-alpha", host: "example.com")
check(UpdateChecker.newest([stableUpdate, alphaUpdate, draftUpdate, foreignUpdate], includePrereleases: true)?.tag_name == alphaUpdate.tag_name)
check(UpdateChecker.newest([stableUpdate, alphaUpdate], includePrereleases: false)?.tag_name == stableUpdate.tag_name)
check(alphaUpdate.build == 2 && alphaUpdate.download(architecture: "arm64") != nil && alphaUpdate.download(architecture: "x86_64") == nil)
check(try updateFixture("v0.6.1-alpha", architecture: "universal").download(architecture: "x86_64") != nil)
check(foreignUpdate.download(architecture: "arm64") == nil)

final class UpdateTestProtocol: URLProtocol {
    static var status = 200
    static var responseData = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        check(request.url?.host == "api.github.com")
        check(request.value(forHTTPHeaderField: "Authorization") == nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
let updateConfiguration = URLSessionConfiguration.ephemeral
updateConfiguration.protocolClasses = [UpdateTestProtocol.self]
let updateSession = URLSession(configuration: updateConfiguration)
UpdateTestProtocol.responseData = try JSONSerialization.data(withJSONObject: [["tag_name": "v0.6.0-alpha", "name": "TagCraft", "body": "Build 1", "html_url": "https://github.com/natsteff/TagCraft/releases/tag/v0.6.0-alpha", "draft": false, "prerelease": true, "assets": []]])
check(try await UpdateChecker.check(includePrereleases: true, session: updateSession).build == 1)
UpdateTestProtocol.status = 403
check((try? await UpdateChecker.check(includePrereleases: true, session: updateSession)) == nil)
UpdateTestProtocol.status = 200; UpdateTestProtocol.responseData = Data("invalid JSON".utf8)
check((try? await UpdateChecker.check(includePrereleases: true, session: updateSession)) == nil)
updateSession.invalidateAndCancel()
print("Update checks passed: alpha releases, version/build reset, channels, asset architecture, URL validation, public request, rate limiting and malformed responses.")

var legacyPrefixRules = CleanRules()
legacyPrefixRules.removeTrackPrefix = true
let decodedPrefixRules = try JSONDecoder().decode(CleanRules.self, from: JSONEncoder().encode(legacyPrefixRules))
check(try decodedPrefixRules.clean("07 - artist - song.mp3", tags: Tags()).0 == "07 - Artist - Song.mp3")
check(try decodedPrefixRules.clean("07 - artist - song.mp3", tags: Tags()).1.allSatisfy { !$0.contains("Remove numbered") })
print("Clean preserves track prefixes even when legacy saved rules requested removal.")

let termsSuite = "TagCraft-Terms-Test-" + UUID().uuidString
let termsDefaults = UserDefaults(suiteName: termsSuite)!
defer { termsDefaults.removePersistentDomain(forName: termsSuite) }
termsDefaults.set("keep", forKey: "unrelatedSetting")
termsDefaults.set(LicenseTerms.version, forKey: "acceptedLicenseTermsVersion")
termsDefaults.set("0.6.0:7", forKey: "acceptedLicenseAppRelease")
termsDefaults.set(Date(), forKey: "licenseTermsAcceptedAt")
check(!LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.6.0:7"))
check(termsDefaults.object(forKey: "usageNoticeAcknowledgedAt") == nil)
let acceptedDate = Date(timeIntervalSince1970: 1234567)
LicenseAcceptance.acknowledge(defaults: termsDefaults, release: "0.6.0:7", at: acceptedDate)
check(LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.6.0:7"))
check(termsDefaults.object(forKey: "usageNoticeAcknowledgedAt") as? Date == acceptedDate)
check(!LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.6.0:8"))
check(!LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.7.0:1"))
termsDefaults.set("changed", forKey: "acknowledgedUsageNoticeHash")
check(!LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.6.0:7"))
LicenseAcceptance.acknowledge(defaults: termsDefaults, release: "0.6.0:7")
termsDefaults.set("old", forKey: "acknowledgedUsageNoticeVersion")
check(!LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.6.0:7"))
LicenseAcceptance.acknowledge(defaults: termsDefaults, release: "0.6.0:7")
termsDefaults.set("old", forKey: "acknowledgedUsageNoticeSupplementVersion")
check(!LicenseAcceptance.isAcknowledged(defaults: termsDefaults, release: "0.6.0:7"))
check(termsDefaults.string(forKey: "unrelatedSetting") == "keep")
check(LicenseTerms.text.contains("TAGCRAFT MUSIC LIBRARIAN") && !LicenseTerms.text.contains("SHELF ELF LIBRARIAN"))
print("Notice acknowledgment checks passed: explicit local records, version/build/hash/supplement changes, timestamps and unrelated preference preservation.")

// Explicit bulk intent: empty/mixed inputs cannot turn unrelated edits into deletion.
var firstBulk = Tags(title: "First title", artist: "Shared", year: "2000", track: "1")
var secondBulk = Tags(title: "Second title", artist: "Shared", year: "2000", track: "2")
firstBulk.extra["USLT"] = "First lyrics\nSecond line"
secondBulk.extra["USLT"] = "Different lyrics"
check(MixedTagValues.value("Title", in: [firstBulk, secondBulk]).mixed)
check(!MixedTagValues.value("Artist", in: [firstBulk, secondBulk]).mixed)
var bulkDraft = Tags(artist: "Updated", year: "2006")
let safePatch = TagEditPatch(draft: bulkDraft, checked: ["Title", "Artist", "Year", "Lyrics"], cleared: [])
let firstChanged = safePatch.applying(to: firstBulk), secondChanged = safePatch.applying(to: secondBulk)
check(firstChanged.title == "First title" && secondChanged.title == "Second title")
check(firstChanged.track == "1" && secondChanged.track == "2")
check(firstChanged.extra["USLT"] == firstBulk.extra["USLT"] && secondChanged.extra["USLT"] == secondBulk.extra["USLT"])
check(firstChanged.artist == "Updated" && firstChanged.year == "2006")
let removeTitle = TagEditPatch(draft: bulkDraft, checked: ["Title"], cleared: ["Title"]).applying(to: firstBulk)
check(removeTitle.title.isEmpty && removeTitle.artist == firstBulk.artist && removeTitle.extra == firstBulk.extra)
check(TagEditPatch(draft: bulkDraft, checked: [], cleared: ["Title"]).applying(to: firstBulk) == firstBulk)
for lyricsVersion in [3,4] {
    let lyricsAudio = Data(repeating: 0x55, count: 4096)
    var lyricsSeed = try ID3(lyricsAudio); lyricsSeed.version = lyricsVersion
    let originalLyrics = "\nFirst line — café 🎵\nSecond line\n"
    var lyricsTags = Tags(title: "Keep title", artist: "Keep artist"); lyricsTags.extra["USLT"] = originalLyrics
    let lyricsFile = lyricsSeed.writing(lyricsTags, original: lyricsAudio)
    var lyricsParsed = try ID3(lyricsFile)
    check(lyricsParsed.tags.extra["USLT"] == originalLyrics)
    check(lyricsFile.suffix(lyricsAudio.count) == lyricsAudio)
    let alternate = ID3.Frame(id: "USLT", payload: LyricsFrame(language: "fra", descriptor: "translation", text: "Autre texte").payload(version: lyricsVersion), flags: Data([0,0]))
    let synchronized = ID3.Frame(id: "SYLT", payload: Data([0,1,2,3,4]), flags: Data([0,0]))
    lyricsParsed.frames.append(alternate); lyricsParsed.frames.append(synchronized)
    let multiFile = lyricsParsed.writing(lyricsParsed.tags, original: lyricsFile)
    let multiParsed = try ID3(multiFile)
    var unrelatedEdit = multiParsed.tags; unrelatedEdit.year = "2026"
    let unchangedLyricsFile = multiParsed.writing(unrelatedEdit, original: multiFile)
    let unchangedLyrics = try ID3(unchangedLyricsFile)
    check(unchangedLyrics.frames.filter { $0.id == "USLT" }.map(\.payload) == multiParsed.frames.filter { $0.id == "USLT" }.map(\.payload))
    var editedLyrics = multiParsed.tags; editedLyrics.extra["USLT"] = "Replacement\nMultiline"
    let editedLyricsFile = multiParsed.writing(editedLyrics, original: multiFile)
    let editedParsed = try ID3(editedLyricsFile)
    check(editedParsed.tags.extra["USLT"] == "Replacement\nMultiline")
    check(editedParsed.frames.last(where: { $0.id == "USLT" })?.payload == alternate.payload)
    editedLyrics.set("Lyrics", "")
    let clearedLyricsFile = multiParsed.writing(editedLyrics, original: multiFile)
    let clearedLyrics = try ID3(clearedLyricsFile)
    check(!clearedLyrics.frames.contains { $0.id == "USLT" })
    check(clearedLyrics.frames.first(where: { $0.id == "SYLT" })?.payload == synchronized.payload)
    check(clearedLyrics.tags.title == "Keep title" && clearedLyrics.tags.artist == "Keep artist")
    check(clearedLyricsFile.suffix(lyricsAudio.count) == lyricsAudio)
}
let latinLyrics = try LyricsFrame.decode(Data([0]) + Data("eng".utf8) + Data([0]) + Data("Latin lyrics\nNext line".utf8))
check(latinLyrics.language == "eng" && latinLyrics.descriptor.isEmpty && latinLyrics.text == "Latin lyrics\nNext line")
var rejectedLyrics = false
do { _ = try LyricsFrame.decode(Data([3,101,110,103,65,66])) } catch { rejectedLyrics = true }
check(rejectedLyrics)
print("Bulk edit and Lyrics checks passed: blank/mixed preservation, explicit field clearing, v2.3/v2.4 Unicode multiline lyrics, alternate language/raw-frame preservation and audio invariance.")

// Display settings are independent preferences, never tag mutations.
let visibilityGroups = TagVisibility.groups(inspector: ["Artist", "Year", "Lyrics"])
check(visibilityGroups.shown == ["Artist", "Lyrics", "Year"])
check(Set(visibilityGroups.shown).isDisjoint(with: Set(visibilityGroups.hidden)))
check(Set(visibilityGroups.shown + visibilityGroups.hidden) == Set(TagEditPatch.fields))
check(visibilityGroups.hidden == visibilityGroups.hidden.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
let inversePurge = TagVisibility.inspectorFields(fromPurge: ["Artist", "Year / Recording Date", "Lyrics (plain and synchronized)"])
check(!inversePurge.contains("Artist") && !inversePurge.contains("Year") && !inversePurge.contains("Lyrics"))
check(inversePurge.contains("Title") && inversePurge.contains("Lyricist"))
check(TagVisibility.inspectorFields(fromPurge: []) == Set(TagVisibility.tags))
check(TagVisibility.inspectorFields(fromPurge: Set(PurgeField.fields.map(\.id))).isEmpty)
let displaySuite = "TagCraft-Display-Test-" + UUID().uuidString
let displayDefaults = UserDefaults(suiteName: displaySuite)!
defer { displayDefaults.removePersistentDomain(forName: displaySuite) }
check(TagVisibility.load("inspector", defaults: displayDefaults, fallback: Set(TagVisibility.tags), allowed: Set(TagVisibility.tags)) == Set(TagVisibility.tags))
displayDefaults.set([String](), forKey: "inspector")
check(TagVisibility.load("inspector", defaults: displayDefaults, fallback: Set(TagVisibility.tags), allowed: Set(TagVisibility.tags)).isEmpty)
displayDefaults.set(["Lyrics", "Artist", "Unknown"], forKey: "columns")
check(TagVisibility.load("columns", defaults: displayDefaults, fallback: TagVisibility.defaultColumns, allowed: TagVisibility.columnChoices) == ["Lyrics", "Artist"])
check(displayDefaults.stringArray(forKey: "inspector") == [])
print("Display configuration checks passed: complete alphabetic groups, frame-mapped Purge inverse, independent settings and persistent Select None.")
