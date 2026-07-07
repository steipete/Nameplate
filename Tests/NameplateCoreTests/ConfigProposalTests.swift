import Foundation
import Testing
@testable import NameplateCore

@Suite("ConfigProposal")
struct ConfigProposalTests {
    @Test func parsesHappyPath() throws {
        let url = try #require(URL(string: "nameplate://config?name=%20megaclaw%20&glyph=%F0%9F%A6%9E"
            + "&color=%231D9E75&frameThickness=5&frameOpacity=1.0&cornerRadius=22"
            + "&roundTopLeft=0&roundTopRight=0&roundBottomLeft=1&roundBottomRight=1"
            + "&tagCorner=bottomLeft&watermarkOpacity=0.05&frameEnabled=1&tagEnabled=1"
            + "&watermarkEnabled=1&splashDuration=2.4"))
        let proposal = try #require(ConfigProposal(url: url))

        #expect(proposal.name == "megaclaw")
        #expect(proposal.glyph == "🦞")
        #expect(proposal.colorHex == "#1D9E75")
        #expect(proposal.frameThickness == 5)
        #expect(proposal.frameOpacity == 1)
        #expect(proposal.cornerRadius == 22)
        #expect(proposal.roundTopLeft == false)
        #expect(proposal.roundTopRight == false)
        #expect(proposal.roundBottomLeft == true)
        #expect(proposal.roundBottomRight == true)
        #expect(proposal.tagCorner == .bottomLeft)
        #expect(proposal.watermarkOpacity == 0.05)
        #expect(proposal.frameEnabled == true)
        #expect(proposal.tagEnabled == true)
        #expect(proposal.watermarkEnabled == true)
        #expect(proposal.splashDuration == 2.4)
        #expect(!proposal.isEmpty)
        #expect(proposal.summaryItems.count == 16)
    }

    @Test func normalizesHexWithoutHash() throws {
        let proposal = try #require(self.proposal("color=1d9e75"))
        #expect(proposal.colorHex == "#1D9E75")
    }

    @Test func ignoresInvalidHex() throws {
        let proposal = try #require(self.proposal("color=not-a-color"))
        #expect(proposal.colorHex == nil)
        #expect(proposal.isEmpty)
    }

    @Test func parsesBooleanVariants() throws {
        let proposal = try #require(self.proposal(
            "roundTopLeft=1&roundTopRight=true&roundBottomLeft=YES&roundBottomRight=0"
                + "&frameEnabled=false&tagEnabled=no"))
        #expect(proposal.roundTopLeft == true)
        #expect(proposal.roundTopRight == true)
        #expect(proposal.roundBottomLeft == true)
        #expect(proposal.roundBottomRight == false)
        #expect(proposal.frameEnabled == false)
        #expect(proposal.tagEnabled == false)
    }

    @Test func clampsOutOfRangeNumbers() throws {
        let proposal = try #require(self.proposal(
            "frameThickness=100&frameOpacity=0&cornerRadius=-4"
                + "&watermarkOpacity=1&splashDuration=0.1"))
        #expect(proposal.frameThickness == 20)
        #expect(proposal.frameOpacity == 0.1)
        #expect(proposal.cornerRadius == 0)
        #expect(proposal.watermarkOpacity == 0.3)
        #expect(proposal.splashDuration == 0.5)
    }

    @Test func ignoresUnknownParameters() throws {
        let proposal = try #require(self.proposal("name=test&unknown=value"))
        #expect(proposal.name == "test")
        #expect(proposal.summaryItems.count == 1)
    }

    @Test func returnsNilWithoutRecognizedParameters() throws {
        let unknown = try #require(URL(string: "nameplate://config?unknown=value"))
        let empty = try #require(URL(string: "nameplate://config"))
        #expect(ConfigProposal(url: unknown) == nil)
        #expect(ConfigProposal(url: empty) == nil)
    }

    @Test func parsesTagCornerRawValue() throws {
        let proposal = try #require(self.proposal("tagCorner=topRight"))
        #expect(proposal.tagCorner == .topRight)
    }

    private func proposal(_ query: String) -> ConfigProposal? {
        guard let url = URL(string: "nameplate://config?\(query)") else { return nil }
        return ConfigProposal(url: url)
    }
}
