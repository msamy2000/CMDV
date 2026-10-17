import Foundation

@main
struct TestRunnerMain {
    @MainActor
    static func main() {
        var passed = 0
        var failed = 0

        let tests: [(String, @MainActor () throws -> Void)] = [
            ("testLoopOverwriteAt20Items", HistoryStoreTestSuite.testLoopOverwriteAt20Items),
            ("testFiveDayExpiration", HistoryStoreTestSuite.testFiveDayExpiration),
            ("testDeduplicationAndTimerReset", HistoryStoreTestSuite.testDeduplicationAndTimerReset),
            ("testBinaryImageAndDiskPersistence", HistoryStoreTestSuite.testBinaryImageAndDiskPersistence),
            ("testConcealedClipboardIgnored", HistoryStoreTestSuite.testConcealedClipboardIgnored),
            ("testWhicheverReachedFirstMixedLimits", HistoryStoreTestSuite.testWhicheverReachedFirstMixedLimits),
            ("testPasteServiceRestoresTextAndBinaryPayloads", HistoryStoreTestSuite.testPasteServiceRestoresTextAndBinaryPayloads)
        ]

        print("Running CMDV Test Suite (\(tests.count) tests)...")
        for (name, testFn) in tests {
            do {
                try testFn()
                print("  [PASS] \(name)")
                passed += 1
            } catch {
                print("  [FAIL] \(name): \(error)")
                failed += 1
            }
        }

        print("Results: \(passed) passed, \(failed) failed.")
        if failed > 0 {
            exit(1)
        }
    }
}
