//
//  RemidorUITests.swift
//  RemidorUITests
//
//  Created by n9ine on 23.10.2026.
//

import XCTest

final class RemidorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
