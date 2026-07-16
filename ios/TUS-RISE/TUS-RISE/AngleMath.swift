//
//  AngleMath.swift
//  TUS-RISE
//
//  Pure joint-angle math mirroring VidCalc.py. Keep this file free of
//  UIKit/Vision imports — it will move into the portable analysis
//  package later (design principle 3).
//

import simd

nonisolated enum AngleMath {

    /// Angle at vertex `b` between the vectors b→a and b→c, in degrees.
    /// Mirrors `calculate_angle()` in VidCalc.py.
    static func jointAngle(at b: SIMD3<Float>, a: SIMD3<Float>, c: SIMD3<Float>) -> Double {
        let ba = a - b
        let bc = c - b
        let denom = simd_length(ba) * simd_length(bc)
        guard denom > 0 else { return 0 }
        let cosine = simd_clamp(simd_dot(ba, bc) / denom, -1, 1)
        return Double(acos(cosine)) * 180 / .pi
    }

    /// Angle between the vector bottom→top and the vertical (y) axis, in degrees.
    /// 3D counterpart of `angle_from_vertical()` in VidCalc.py — Vision's 3D
    /// space is y-up, so 0° means perfectly upright.
    static func angleFromVertical(from bottom: SIMD3<Float>, to top: SIMD3<Float>) -> Double {
        let v = top - bottom
        let len = simd_length(v)
        guard len > 0 else { return 0 }
        let cosine = simd_clamp(abs(v.y) / len, 0, 1)
        return Double(acos(cosine)) * 180 / .pi
    }

    // MARK: 2D (pixel-space) variants — used by the simulator/2D fallback path.
    // These match VidCalc.py exactly, which works in image pixels (y down).

    /// Angle at vertex `b` between b→a and b→c, in degrees (2D pixels).
    static func jointAngle(at b: SIMD2<Float>, a: SIMD2<Float>, c: SIMD2<Float>) -> Double {
        let ba = a - b
        let bc = c - b
        let denom = simd_length(ba) * simd_length(bc)
        guard denom > 0 else { return 0 }
        let cosine = simd_clamp(simd_dot(ba, bc) / denom, -1, 1)
        return Double(acos(cosine)) * 180 / .pi
    }

    /// Line-for-line mirror of `angle_from_vertical()` in VidCalc.py:
    /// atan2(|dx|, |dy|) on image coordinates.
    static func angleFromVertical(from bottom: SIMD2<Float>, to top: SIMD2<Float>) -> Double {
        let d = top - bottom
        return Double(atan2(abs(d.x), abs(d.y))) * 180 / .pi
    }
}
