import Foundation
import Testing
@testable import NameplateCore

@Suite("Tag positioning")
struct TagPositionTests {
    private struct Vector: Decodable {
        let name: String
        let position: TagPosition
        let width, height, tagWidth, tagHeight, inset, horizontalOffset, verticalOffset, x, y: Double
    }

    @Test func sharedPlacementVectors() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/tag-placement.json")
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: fixture))
        for vector in vectors {
            let origin = vector.position.origin(
                width: vector.width, height: vector.height, tagWidth: vector.tagWidth, tagHeight: vector.tagHeight,
                inset: vector.inset, horizontalOffset: vector.horizontalOffset, verticalOffset: vector.verticalOffset)
            #expect(origin.x == vector.x, "\(vector.name): x")
            #expect(origin.y == vector.y, "\(vector.name): y")
        }
    }

    @Test func allPositionsRoundTripWithoutExpandingWatermarkCorners() throws {
        #expect(TagPosition.allCases.count == 8)
        #expect(ScreenCorner.allCases.count == 4)
        for position in TagPosition.allCases {
            let encoded = try JSONEncoder().encode(position)
            #expect(try JSONDecoder().decode(TagPosition.self, from: encoded) == position)
        }
        #expect(TagPosition(rawValue: "bottomLeft") == .bottomLeft)
        #expect(TagPosition(rawValue: "unknown") == nil)
    }

    @Test func nonFiniteOffsetsAreNeutral() {
        let origin = TagPosition.rightCenter.origin(
            width: 1000, height: 700, tagWidth: 100, tagHeight: 30,
            inset: 20, horizontalOffset: .nan, verticalOffset: .infinity)
        #expect(origin.x == 880)
        #expect(origin.y == 335)
    }

    @Test func offsetControlsCoverDisplayWithSignedCenteredAxes() {
        #expect(TagPosition.rightCenter.horizontalAnchor.offsetRange(extent: 3000) == 0...3000)
        #expect(TagPosition.rightCenter.verticalAnchor.offsetRange(extent: 2000) == -1000...1000)
        #expect(TagPosition.topCenter.horizontalAnchor.offsetRange(extent: 3000) == -1500...1500)
    }
}
