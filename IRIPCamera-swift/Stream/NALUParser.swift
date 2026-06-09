//
//  NALUParser.swift
//  IRIPCamera-swift
//
//  Pure, dependency-free helpers for parsing H.264/HEVC parameter sets and
//  converting Annex B byte streams to length-prefixed (AVCC/HVCC) samples.
//
//  These were extracted from `IRStreamVideoDecoder` so the bit-twiddling logic
//  can be unit tested on plain `[UInt8]` / `Data` without VideoToolbox, FFmpeg
//  or unsafe pointers.
//

import Foundation

enum NALUParser {

    /// Parsed parameter sets plus the NAL unit length prefix size.
    struct ParameterSets: Equatable {
        var vps: [Data] = []   // HEVC only
        var sps: [Data] = []
        var pps: [Data] = []
        var nalLengthSize: Int = 4
    }

    // MARK: - Start codes

    static func isStartCode4(_ bytes: [UInt8], _ i: Int) -> Bool {
        i + 4 <= bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1
    }

    static func isStartCode3(_ bytes: [UInt8], _ i: Int) -> Bool {
        i + 3 <= bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1
    }

    /// Returns the start-code length (4 or 3) at `i`, or nil if none.
    static func matchStartCode(_ bytes: [UInt8], _ i: Int) -> Int? {
        if isStartCode4(bytes, i) { return 4 }
        if isStartCode3(bytes, i) { return 3 }
        return nil
    }

    /// True if the buffer begins with an Annex B start code.
    static func isAnnexBStartCode(_ bytes: [UInt8]) -> Bool {
        isStartCode4(bytes, 0) || isStartCode3(bytes, 0)
    }

    /// True if the buffer contains an Annex B start code anywhere.
    static func looksLikeAnnexB(_ bytes: [UInt8]) -> Bool {
        let length = bytes.count
        if isStartCode4(bytes, 0) { return true }
        if isStartCode3(bytes, 0) { return true }
        var i = 0
        while i + 4 <= length {
            if isStartCode4(bytes, i) { return true }
            if isStartCode3(bytes, i) { return true }
            i += 1
        }
        return false
    }

    // MARK: - Length-prefixed (AVCC / HVCC) extradata

    /// Parses `avcC` (H.264) extradata. Returns nil if malformed or no SPS/PPS found.
    static func parseAVCC(_ extradata: [UInt8]) -> ParameterSets? {
        let size = extradata.count
        guard size >= 7, extradata[0] == 1 else { return nil }

        var result = ParameterSets()
        result.nalLengthSize = Int(extradata[4] & 0x03) + 1
        var offset = 5

        let numOfSPS = Int(extradata[offset] & 0x1F)
        offset += 1

        for _ in 0..<numOfSPS {
            if offset + 2 > size { return nil }
            let spsLength = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
            offset += 2
            if offset + spsLength > size { return nil }
            result.sps.append(Data(extradata[offset..<offset + spsLength]))
            offset += spsLength
        }

        if offset + 1 > size { return nil }
        let numOfPPS = Int(extradata[offset])
        offset += 1

        for _ in 0..<numOfPPS {
            if offset + 2 > size { return nil }
            let ppsLength = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
            offset += 2
            if offset + ppsLength > size { return nil }
            result.pps.append(Data(extradata[offset..<offset + ppsLength]))
            offset += ppsLength
        }

        return (!result.sps.isEmpty && !result.pps.isEmpty) ? result : nil
    }

    /// Parses `hvcC` (HEVC) extradata. Returns nil if malformed or VPS/SPS/PPS missing.
    static func parseHVCC(_ extradata: [UInt8]) -> ParameterSets? {
        let size = extradata.count
        guard size >= 23, extradata[0] == 1 else { return nil }

        var result = ParameterSets()
        result.nalLengthSize = Int(extradata[21] & 0x03) + 1

        var offset = 22
        if offset >= size { return nil }

        let numOfArrays = Int(extradata[offset])
        offset += 1

        for _ in 0..<numOfArrays {
            if offset + 3 > size { return nil }
            let arrayCompletenessAndType = extradata[offset]
            offset += 1
            let nalUnitType = Int(arrayCompletenessAndType & 0x3F)
            let numNalus = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
            offset += 2

            for _ in 0..<numNalus {
                if offset + 2 > size { return nil }
                let nalUnitLength = Int(extradata[offset]) << 8 | Int(extradata[offset + 1])
                offset += 2
                if offset + nalUnitLength > size { return nil }
                let data = Data(extradata[offset..<offset + nalUnitLength])
                switch nalUnitType {
                case 32: result.vps.append(data)
                case 33: result.sps.append(data)
                case 34: result.pps.append(data)
                default: break
                }
                offset += nalUnitLength
            }
        }

        return (!result.vps.isEmpty && !result.sps.isEmpty && !result.pps.isEmpty) ? result : nil
    }

    // MARK: - Annex B parameter sets

    /// Walks Annex B extradata collecting VPS/SPS/PPS NAL units. `nalLengthSize` is 4.
    static func parseAnnexBParameterSets(_ extradata: [UInt8], isHEVC: Bool) -> ParameterSets {
        var result = ParameterSets()
        var index = 0
        while let (range, naluType) = nextAnnexBNAL(in: extradata, start: index, isHEVC: isHEVC) {
            let data = Data(extradata[range])
            if isHEVC {
                switch naluType {
                case 32: result.vps.append(data)
                case 33: result.sps.append(data)
                case 34: result.pps.append(data)
                default: break
                }
            } else {
                if naluType == 7 {
                    result.sps.append(data)
                } else if naluType == 8 {
                    result.pps.append(data)
                }
            }
            index = range.upperBound
        }
        return result
    }

    /// Finds the next Annex B NAL unit at or after `start`.
    /// Returns the payload range (excluding the start code) and the NAL unit type.
    static func nextAnnexBNAL(in bytes: [UInt8], start: Int, isHEVC: Bool) -> (range: Range<Int>, naluType: Int)? {
        let size = bytes.count
        var i = start

        var scLen1: Int?
        while i < size {
            if let sc = matchStartCode(bytes, i) {
                scLen1 = sc
                break
            }
            i += 1
        }
        guard let sc1 = scLen1 else { return nil }
        let naluStart = i + sc1

        var j = naluStart
        var nextStartIdx: Int?
        while j < size {
            if matchStartCode(bytes, j) != nil {
                nextStartIdx = j
                break
            }
            j += 1
        }
        let naluEnd = nextStartIdx ?? size
        guard naluEnd > naluStart else { return nil }

        let firstByte = bytes[naluStart]
        let naluType: Int
        if isHEVC {
            naluType = Int((firstByte >> 1) & 0x3F)
        } else {
            naluType = Int(firstByte & 0x1F)
        }
        return (naluStart..<naluEnd, naluType)
    }

    // MARK: - Annex B -> AVCC conversion

    /// Converts an Annex B buffer into a length-prefixed buffer using `nalLengthSize`
    /// byte big-endian length prefixes. Returns empty `Data` if no NAL units found.
    static func convertAnnexBToAVCC(_ bytes: [UInt8], nalLengthSize: Int) -> Data {
        let length = bytes.count
        var nalRanges: [(start: Int, end: Int)] = []
        var i = 0

        while i < length {
            guard let scLen = matchStartCode(bytes, i) else {
                i += 1
                continue
            }
            let naluStart = i + scLen
            var j = naluStart
            var nextStart: Int?
            while j < length {
                if matchStartCode(bytes, j) != nil {
                    nextStart = j
                    break
                }
                j += 1
            }
            let naluEnd = nextStart ?? length
            if naluEnd > naluStart {
                nalRanges.append((start: naluStart, end: naluEnd))
            }
            i = naluEnd
        }

        if nalRanges.isEmpty { return Data() }

        var out = Data()
        out.reserveCapacity(nalRanges.reduce(0) { $0 + nalLengthSize + ($1.end - $1.start) })

        for r in nalRanges {
            let nalSize = r.end - r.start
            // Write length (big-endian)
            for b in stride(from: nalLengthSize - 1, through: 0, by: -1) {
                out.append(UInt8((nalSize >> (b * 8)) & 0xFF))
            }
            // Write NALU payload
            out.append(contentsOf: bytes[r.start..<r.end])
        }
        return out
    }
}
