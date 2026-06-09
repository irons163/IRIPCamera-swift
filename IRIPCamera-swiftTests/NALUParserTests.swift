//
//  NALUParserTests.swift
//  IRIPCamera-swiftTests
//
//  Covers the pure NAL-unit parsing / conversion logic extracted from
//  IRStreamVideoDecoder.
//

import Foundation
import Testing
@testable import IRIPCamera_swift

struct NALUParserTests {

    // MARK: - Start codes

    @Test func detectsLeadingStartCodes() {
        #expect(NALUParser.isAnnexBStartCode([0, 0, 0, 1, 0x67]))
        #expect(NALUParser.isAnnexBStartCode([0, 0, 1, 0x67]))
        #expect(!NALUParser.isAnnexBStartCode([1, 2, 3, 4]))
        #expect(!NALUParser.isAnnexBStartCode([0, 0]))
    }

    @Test func detectsEmbeddedStartCodes() {
        #expect(NALUParser.looksLikeAnnexB([0xFF, 0xFF, 0, 0, 1, 0x65]))
        #expect(NALUParser.looksLikeAnnexB([0, 0, 0, 1, 0x65]))
        #expect(!NALUParser.looksLikeAnnexB([1, 2, 3, 4, 5]))
        #expect(!NALUParser.looksLikeAnnexB([]))
    }

    @Test func matchStartCodePrefersFourByteCode() {
        #expect(NALUParser.matchStartCode([0, 0, 0, 1], 0) == 4)
        #expect(NALUParser.matchStartCode([0, 0, 1, 9], 0) == 3)
        #expect(NALUParser.matchStartCode([9, 0, 0, 1], 0) == nil)
    }

    // MARK: - avcC (H.264)

    @Test func parsesValidAVCC() {
        let extradata: [UInt8] = [
            0x01,                   // configurationVersion
            0x64, 0x00, 0x1F,       // profile / compat / level
            0xFF,                   // lengthSizeMinusOne = 3 -> nalLengthSize 4
            0xE1,                   // numSPS = 1 (top bits reserved)
            0x00, 0x04,             // SPS length 4
            0x67, 0x42, 0x00, 0x1F, // SPS payload
            0x01,                   // numPPS = 1
            0x00, 0x03,             // PPS length 3
            0x68, 0xCE, 0x3C        // PPS payload
        ]

        let sets = NALUParser.parseAVCC(extradata)

        #expect(sets?.nalLengthSize == 4)
        #expect(sets?.sps == [Data([0x67, 0x42, 0x00, 0x1F])])
        #expect(sets?.pps == [Data([0x68, 0xCE, 0x3C])])
        #expect(sets?.vps.isEmpty == true)
    }

    @Test func parsesAVCCLengthSizeFromHeader() {
        let extradata: [UInt8] = [
            0x01, 0x64, 0x00, 0x1F,
            0xFD,                   // lengthSizeMinusOne = 1 -> nalLengthSize 2
            0xE1,
            0x00, 0x02, 0x67, 0x10,
            0x01,
            0x00, 0x02, 0x68, 0x20
        ]

        #expect(NALUParser.parseAVCC(extradata)?.nalLengthSize == 2)
    }

    @Test func rejectsMalformedAVCC() {
        #expect(NALUParser.parseAVCC([0x01, 0x64, 0x00]) == nil)          // too short
        #expect(NALUParser.parseAVCC([0x00, 0x64, 0x00, 0x1F, 0xFF, 0xE1, 0x00]) == nil) // wrong version
        // SPS length runs past the buffer.
        #expect(NALUParser.parseAVCC([0x01, 0, 0, 0, 0xFF, 0xE1, 0x00, 0x09, 0x67]) == nil)
    }

    // MARK: - hvcC (HEVC)

    @Test func parsesValidHVCC() {
        var d: [UInt8] = Array(repeating: 0, count: 22)
        d[0] = 0x01
        d[21] = 0xFF                       // nalLengthSize 4
        d.append(0x03)                     // numArrays
        d.append(contentsOf: [0x20, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01]) // VPS (type 32)
        d.append(contentsOf: [0x21, 0x00, 0x01, 0x00, 0x03, 0x42, 0x01, 0x02]) // SPS (type 33)
        d.append(contentsOf: [0x22, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01]) // PPS (type 34)

        let sets = NALUParser.parseHVCC(d)

        #expect(sets?.nalLengthSize == 4)
        #expect(sets?.vps == [Data([0x40, 0x01])])
        #expect(sets?.sps == [Data([0x42, 0x01, 0x02])])
        #expect(sets?.pps == [Data([0x44, 0x01])])
    }

    @Test func rejectsMalformedHVCC() {
        #expect(NALUParser.parseHVCC(Array(repeating: 0, count: 10)) == nil) // too short
        var noVersion = Array<UInt8>(repeating: 0, count: 30)
        noVersion[0] = 0x02
        #expect(NALUParser.parseHVCC(noVersion) == nil)                       // wrong version
    }

    // MARK: - Annex B parameter sets

    @Test func parsesAnnexBH264ParameterSets() {
        let extradata: [UInt8] = [
            0, 0, 0, 1, 0x67, 0xAA, // SPS (type 7)
            0, 0, 0, 1, 0x68, 0xBB  // PPS (type 8)
        ]

        let sets = NALUParser.parseAnnexBParameterSets(extradata, isHEVC: false)

        #expect(sets.sps == [Data([0x67, 0xAA])])
        #expect(sets.pps == [Data([0x68, 0xBB])])
        #expect(sets.nalLengthSize == 4)
    }

    @Test func parsesAnnexBHEVCParameterSets() {
        let extradata: [UInt8] = [
            0, 0, 0, 1, 0x40, 0x01, // VPS (type 32)
            0, 0, 0, 1, 0x42, 0x02, // SPS (type 33)
            0, 0, 0, 1, 0x44, 0x03  // PPS (type 34)
        ]

        let sets = NALUParser.parseAnnexBParameterSets(extradata, isHEVC: true)

        #expect(sets.vps == [Data([0x40, 0x01])])
        #expect(sets.sps == [Data([0x42, 0x02])])
        #expect(sets.pps == [Data([0x44, 0x03])])
    }

    @Test func nextAnnexBNALReportsTypeAndRange() {
        let bytes: [UInt8] = [0, 0, 0, 1, 0x67, 0x42, 0x00]
        let nal = NALUParser.nextAnnexBNAL(in: bytes, start: 0, isHEVC: false)
        #expect(nal?.naluType == 7)              // 0x67 & 0x1F
        #expect(nal?.range == 4..<7)

        let hevc = NALUParser.nextAnnexBNAL(in: bytes, start: 0, isHEVC: true)
        #expect(hevc?.naluType == 0x33)          // (0x67 >> 1) & 0x3F

        #expect(NALUParser.nextAnnexBNAL(in: [1, 2, 3], start: 0, isHEVC: false) == nil)
    }

    // MARK: - Annex B -> AVCC conversion

    @Test func convertsAnnexBToFourByteLengthPrefixed() {
        let annexB: [UInt8] = [
            0, 0, 0, 1, 0x67, 0x42, // NAL #1
            0, 0, 1, 0x68           // NAL #2 (3-byte start code)
        ]

        let avcc = NALUParser.convertAnnexBToAVCC(annexB, nalLengthSize: 4)

        #expect(avcc == Data([0, 0, 0, 2, 0x67, 0x42, 0, 0, 0, 1, 0x68]))
    }

    @Test func convertsAnnexBWithTwoByteLengthPrefix() {
        let annexB: [UInt8] = [0, 0, 0, 1, 0x65, 0x11, 0x22]

        let avcc = NALUParser.convertAnnexBToAVCC(annexB, nalLengthSize: 2)

        #expect(avcc == Data([0, 3, 0x65, 0x11, 0x22]))
    }

    @Test func convertReturnsEmptyWhenNoStartCode() {
        #expect(NALUParser.convertAnnexBToAVCC([1, 2, 3, 4], nalLengthSize: 4).isEmpty)
    }

    @Test func roundTripsAVCCParametersThroughConversion() {
        // An Annex B access unit converted to AVCC should round-trip the payloads
        // when parsed back with a matching length size.
        let annexB: [UInt8] = [0, 0, 0, 1, 0x67, 0x01, 0x02, 0, 0, 0, 1, 0x68, 0x03]
        let avcc = NALUParser.convertAnnexBToAVCC(annexB, nalLengthSize: 4)
        // 4-byte len (3) + [67,01,02] + 4-byte len (2) + [68,03]
        #expect(avcc == Data([0, 0, 0, 3, 0x67, 0x01, 0x02, 0, 0, 0, 2, 0x68, 0x03]))
    }
}
