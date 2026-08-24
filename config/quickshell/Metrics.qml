pragma Singleton

import QtQuick

// Layout scales. A value earns a place here only if it encodes a system rule or
// is shared by more than one surface — a number used by exactly one widget
// belongs at that widget, not in a global bucket.
QtObject {
    // ── Space: a 4pt grid ──────────────────────────────────────────────────
    readonly property int s1: 4
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16
    readonly property int s5: 20
    readonly property int s6: 24
    readonly property int s8: 32

    readonly property int hairline: 1

    // ── Radius ─────────────────────────────────────────────────────────────
    readonly property int rControl: 7
    readonly property int rCard: 10
    // Fallback only; the bar follows Hyprland's rounding once state loads.
    readonly property int rBar: 8
    readonly property int rPanel: 13
    readonly property int rPill: 999

    // Concentric corners: an inset child must curve tighter than its parent by
    // exactly the inset, or the gap between the two arcs visibly pinches.
    function inner(outer, inset) {
        return Math.max(3, outer - inset);
    }

    // ── Icons ──────────────────────────────────────────────────────────────
    // The set is drawn on a 24px grid with a 2px stroke. Sizes are chosen so the
    // stroke lands on or near a whole pixel; 14px (the old default) put it at
    // 1.17px, which is why every glyph read soft.
    readonly property int iconSm: 16
    readonly property int icon: 18
    readonly property int iconLg: 20
    readonly property int iconXl: 24

    // ── Bar ────────────────────────────────────────────────────────────────
    readonly property int barHeight: 32
    readonly property int barMargin: 6
    // Room inside the layer surface for the bar's shadow to fall. Hyprland
    // draws a shadow around every tiled window, so a bar without one sits in a
    // gap that reads wider than theirs at the same measured size.
    readonly property int barShadowPad: 6
    readonly property int barItemHeight: 24
    readonly property int barIcon: 16
    readonly property int barInset: 12
    readonly property int barSpacing: 8

    // ── Rows and controls ──────────────────────────────────────────────────
    readonly property int rowHeight: 34
    readonly property int rowHeightTall: 46
    readonly property int rowInset: 12
    readonly property int controlHeight: 26

    readonly property int toggleWidth: 40
    readonly property int toggleHeight: 24
    readonly property int toggleKnob: 18

    readonly property int trackHeight: 6
    readonly property int knob: 16

    // ── Surfaces ───────────────────────────────────────────────────────────
    readonly property int panelInset: 10
    readonly property int panelNarrow: 320
    readonly property int panelWide: 348
    readonly property int gap: 8
    // Clearance between the bar's lower edge and anything anchored beneath it.
    readonly property int detachment: barHeight + barMargin + gap

    readonly property int wheelStep: 165

    // How far past an edge a wheel may stretch content, and the curve that gets
    // it there: diminishing returns, asymptotic to `overshoot`, so pushing
    // harder against the end never runs away. One home, because two scrollers
    // that stretch differently read as one of them being broken.
    readonly property int overshoot: 72

    function resist(past) {
        return overshoot * past / (past + overshoot);
    }
}
