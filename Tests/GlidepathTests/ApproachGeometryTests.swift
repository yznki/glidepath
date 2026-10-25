import XCTest
@testable import Glidepath

final class ApproachGeometryTests: XCTestCase {
    private func plane(_ n: Int, marker: Int, phase: ApproachPhase = .flying, lane: Int = 0,
                       stack: Int? = nil) -> ApproachPlane {
        ApproachPlane(slug: "lumen/api", n: n, title: "", url: "", phase: phase, marker: marker, label: "",
                      waitingOn: nil, lane: lane, stackIndex: stack, off: false, gates: [], ci: "pending")
    }

    func testPlaneSitsAtTheFurthestMarkerItPassed() {
        XCTAssertEqual(ApproachGeometry.planeX(marker: 0, phase: .flying), 130)
        XCTAssertEqual(ApproachGeometry.planeX(marker: 1, phase: .waiting), 300)
        XCTAssertEqual(ApproachGeometry.planeX(marker: 3, phase: .cleared), 720)
        XCTAssertEqual(ApproachGeometry.planeX(marker: 0, phase: .taxiing), 120)
        XCTAssertEqual(ApproachGeometry.planeX(marker: 3, phase: .landed), ApproachGeometry.landedX)
    }

    func testLandingGlideRunsOnceFromFirstSightingThenSits() {
        let seen = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(ApproachGeometry.landingProgress(seen: seen, at: seen.addingTimeInterval(1.32), frozen: false),
                       0.6, accuracy: 0.0001)
        XCTAssertEqual(ApproachGeometry.landingProgress(seen: seen, at: seen.addingTimeInterval(9), frozen: false), 1)
        // Reduce Motion and a plane never seen both sit on the runway.
        XCTAssertEqual(ApproachGeometry.landingProgress(seen: seen, at: seen, frozen: true), 1)
        XCTAssertEqual(ApproachGeometry.landingProgress(seen: nil, at: seen, frozen: false), 1)
        // The flash is dark until 70% of the glide, full at 80%, and gone at the end.
        XCTAssertEqual(ApproachGeometry.flashOpacity(0.6), 0)
        XCTAssertEqual(ApproachGeometry.flashOpacity(0.8), 1, accuracy: 0.0001)
        XCTAssertEqual(ApproachGeometry.flashOpacity(1), 0)
    }

    func testLaneEasesFromItsStartToTheRunwayCentreLine() {
        XCTAssertEqual(ApproachGeometry.laneY(lane: 0, x: 40), 60)
        XCTAssertEqual(ApproachGeometry.laneY(lane: 1, x: 40), 115)
        XCTAssertEqual(ApproachGeometry.laneY(lane: 0, x: 880), 165, accuracy: 0.001)
        // Lane 2 starts at 170 and has eased 480/840 of the way to the centre line at x 520.
        XCTAssertEqual(ApproachGeometry.laneY(lane: 2, x: 520), 170 - 5 * 480.0 / 840.0, accuracy: 0.001)
        // Lanes past the last are clamped to it.
        XCTAssertEqual(ApproachGeometry.laneY(lane: 9, x: 40), ApproachGeometry.laneY(lane: 4, x: 40))
    }

    func testStackFollowersTrailTheLeaderInLandingOrder() {
        let planes = [plane(1301, marker: 3, lane: 0, stack: 1),
                      plane(1302, marker: 3, phase: .waiting, lane: 0, stack: 2),
                      plane(1303, marker: 2, phase: .waiting, lane: 0, stack: 3),
                      plane(1253, marker: 0, lane: 2)]
        let at = ApproachGeometry.positions(planes)
        XCTAssertEqual(at["lumen/api#1301"]?.x, 720)
        XCTAssertEqual(at["lumen/api#1302"]?.x, 630)
        XCTAssertEqual(at["lumen/api#1303"]?.x, 540)
        XCTAssertEqual(at["lumen/api#1253"]?.x, 130)
        XCTAssertEqual(at["lumen/api#1303"]?.y, ApproachGeometry.laneY(lane: 0, x: 540))
    }
}
