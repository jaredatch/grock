// Check that the appcast entry for a release ZIP has the ZIP's length and a
// Sparkle signature that the public key inside the app accepts. Reads no
// private key, so a wrong signing key fails here instead of on every Mac.
// usage: xcrun swift script/verify_update.swift appcast.xml Grock-X.Y.Z-arm64.zip Grock.app
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Update verification failed: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: verify_update.swift APPCAST ZIP APP") }
let zip = URL(fileURLWithPath: args[2])
let info = URL(fileURLWithPath: args[3]).appendingPathComponent("Contents/Info.plist")
do {
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any]
    guard let encodedKey = plist?["SUPublicEDKey"] as? String, let key = Data(base64Encoded: encodedKey) else {
        fail("the app has no SUPublicEDKey")
    }
    let feed = try XMLDocument(contentsOf: URL(fileURLWithPath: args[1]))
    let entries = try feed.nodes(forXPath: "//item/enclosure").compactMap { $0 as? XMLElement }.filter {
        $0.attribute(forName: "url")?.stringValue?.hasSuffix("/" + zip.lastPathComponent) == true
    }
    guard entries.count == 1, let entry = entries.first else {
        fail("expected one appcast entry for \(zip.lastPathComponent), found \(entries.count)")
    }
    let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    guard let encodedSignature = entry.attribute(forLocalName: "edSignature", uri: sparkle)?.stringValue,
          let signature = Data(base64Encoded: encodedSignature) else {
        fail("the entry has no EdDSA signature")
    }
    let data = try Data(contentsOf: zip, options: .mappedIfSafe)
    guard entry.attribute(forName: "length")?.stringValue == String(data.count) else {
        fail("the entry's length doesn't match the ZIP")
    }
    guard try Curve25519.Signing.PublicKey(rawRepresentation: key).isValidSignature(signature, for: data) else {
        fail("the signature doesn't match the app's SUPublicEDKey")
    }
} catch {
    fail(error.localizedDescription)
}
print("UPDATE SIGNATURE OK")
