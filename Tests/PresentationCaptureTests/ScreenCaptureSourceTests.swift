import Testing
@testable import PresentationCapture

@Test func boundedNewestStreamDropsStaleValues() async {
    let mailbox = BoundedNewestStream<Int>(limit: 1)
    mailbox.yield(1)
    mailbox.yield(2)
    mailbox.yield(3)
    mailbox.finish()

    var received: [Int] = []
    for await value in mailbox.stream { received.append(value) }

    #expect(received == [3])
}

@Test func missingDisplayErrorKeepsRequestedIdentifier() {
    #expect(ScreenCaptureSourceError.displayNotFound(42) == .displayNotFound(42))
}
