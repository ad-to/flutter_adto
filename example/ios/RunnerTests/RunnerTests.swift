import Flutter
import UIKit
import XCTest
import flutter_adto

class RunnerTests: XCTestCase {

  /// On iOS 16+ reading another app's pasteboard waits for the user to answer
  /// the paste alert, and it blocks the thread it runs on. Flutter runs Dart
  /// on the main thread, so a read there froze the SDK and the app until the
  /// user answered: the read must run elsewhere and answer later.
  func testThePasteboardReadNeverRunsInsideTheMainThreadCall() {
    let link = "https://demo.adto.app/spring?adto_click=abcdefgh1234"
    UIPasteboard.general.url = URL(string: link)
    let answered = expectation(description: "readPasteboardUrl answered")
    var insideTheCall = true
    AdtoIdentifiersPlugin().handle(
      FlutterMethodCall(methodName: "readPasteboardUrl", arguments: nil)
    ) { value in
      XCTAssertFalse(insideTheCall, "the read ran on the main thread, inside the call")
      XCTAssertTrue(Thread.isMainThread, "the answer goes back on the main thread")
      XCTAssertEqual(value as? String, link)
      answered.fulfill()
    }
    insideTheCall = false
    wait(for: [answered], timeout: 5)
  }
}
