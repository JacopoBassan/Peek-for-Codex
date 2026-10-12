import CryptoKit
import Foundation

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "PeekUpdateVerification", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    try require(CommandLine.arguments.count == 5, "Expected app, feed, archive and exact download URL.")
    let app = URL(fileURLWithPath: CommandLine.arguments[1])
    let plistData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
    guard let publicString = plist["SUPublicEDKey"] as? String,
          let publicData = Data(base64Encoded: publicString) else {
        throw NSError(domain: "PeekUpdateVerification", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Missing update public key."])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
    let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let text = String(decoding: feed, as: UTF8.self)
    let expression = try NSRegularExpression(pattern: "<!-- sparkle-signatures:\\nedSignature: ([A-Za-z0-9+/=]+)\\nlength: ([0-9]+)\\n-->\\s*$")
    guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let signatureRange = Range(match.range(at: 1), in: text),
          let lengthRange = Range(match.range(at: 2), in: text),
          let signature = Data(base64Encoded: String(text[signatureRange])),
          let length = Int(text[lengthRange]),
          let comment = feed.range(of: Data("<!-- sparkle-signatures:".utf8)) else {
        throw NSError(domain: "PeekUpdateVerification", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Missing signed feed metadata."])
    }
    try require(length == comment.lowerBound, "Feed signature does not cover all update information.")
    try require(key.isValidSignature(signature, for: feed.prefix(length)), "Feed signature does not match the app's public key.")
    let document = try XMLDocument(data: feed)
    let items = try document.nodes(forXPath: "/rss/channel/item")
    try require(items.count == 1, "Expected one release in the generated feed.")
    let item = items[0] as! XMLElement
    let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    let version = item.elements(forLocalName: "version", uri: namespace).first?.stringValue
    try require(version == plist["CFBundleVersion"] as? String, "Feed build number does not match the app.")
    guard let enclosure = item.elements(forName: "enclosure").first,
          let encoded = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
          let archiveSignature = Data(base64Encoded: encoded) else {
        throw NSError(domain: "PeekUpdateVerification", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Missing archive signature."])
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    try require(enclosure.attribute(forName: "length")?.stringValue == String(archive.count), "Archive length does not match the feed.")
    try require(enclosure.attribute(forName: "url")?.stringValue == CommandLine.arguments[4], "Archive URL does not match the release tag.")
    try require(key.isValidSignature(archiveSignature, for: archive), "Archive signature does not match the app's public key.")
    print("Feed and archive signatures match the app's public key and build \(version ?? "").")
} catch {
    fputs("Update verification failed: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
