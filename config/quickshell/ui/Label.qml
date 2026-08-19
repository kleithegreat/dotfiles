import QtQuick
import qs

Text {
    id: root

    // One of: display, title, headline, body, callout, caption, section, mono.
    property string role: "body"
    property bool numeric: false

    readonly property var _roles: ({
        "display": { size: Theme.sizeDisplay, weight: Theme.weightSemi, color: Theme.text, caps: Font.MixedCase, tracking: -0.4 },
        "title": { size: Theme.sizeTitle, weight: Theme.weightSemi, color: Theme.text, caps: Font.MixedCase, tracking: -0.2 },
        "headline": { size: Theme.sizeHeadline, weight: Theme.weightMedium, color: Theme.text, caps: Font.MixedCase, tracking: 0 },
        "body": { size: Theme.sizeBody, weight: Theme.weightRegular, color: Theme.text, caps: Font.MixedCase, tracking: 0 },
        "callout": { size: Theme.sizeCallout, weight: Theme.weightRegular, color: Theme.textSecondary, caps: Font.MixedCase, tracking: 0 },
        "caption": { size: Theme.sizeCaption, weight: Theme.weightRegular, color: Theme.textTertiary, caps: Font.MixedCase, tracking: 0 },
        "section": { size: Theme.sizeMicro, weight: Theme.weightSemi, color: Theme.textTertiary, caps: Font.AllUppercase, tracking: 0.7 },
        "mono": { size: Theme.sizeCaption, weight: Theme.weightRegular, color: Theme.textSecondary, caps: Font.MixedCase, tracking: 0 }
    })

    readonly property var _spec: _roles[role] || _roles["body"]

    font.family: role === "mono" ? Theme.familyMono : Theme.family
    font.pixelSize: _spec.size
    font.weight: _spec.weight
    font.capitalization: _spec.caps
    font.letterSpacing: _spec.tracking
    font.features: numeric ? Theme.tabular : ({})
    color: _spec.color

    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
        Tint {}
    }
}
