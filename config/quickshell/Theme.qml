pragma Singleton
import QtQuick

QtObject {
    // Colors: Gruvbox Dark
    readonly property color bg:        "#282828"
    readonly property color bg0_h:     "#1d2021"
    readonly property color bg1:       "#3c3836"
    readonly property color bg2:       "#504945"
    readonly property color bg3:       "#665c54"
    readonly property color fg:        "#ebdbb2"
    readonly property color fg2:       "#d5c4a1"
    readonly property color fg3:       "#bdae93"
    readonly property color fg4:       "#a89984"
    readonly property color red:       "#cc241d"
    readonly property color green:     "#98971a"
    readonly property color yellow:    "#d79921"
    readonly property color blue:      "#458588"
    readonly property color purple:    "#b16286"
    readonly property color aqua:      "#689d6a"
    readonly property color orange:    "#d65d0e"
    readonly property color redBright:    "#fb4934"
    readonly property color greenBright:  "#b8bb26"
    readonly property color yellowBright: "#fabd2f"
    readonly property color blueBright:   "#83a598"
    readonly property color purpleBright: "#d3869b"
    readonly property color aquaBright:   "#8ec07c"
    readonly property color orangeBright: "#fe8019"
    readonly property color accent:       "#458588"

    readonly property int barHeight: 32
    readonly property int barMargin: 4
    readonly property int barRadius: 8
    readonly property int barSpacing: 8
    readonly property int barPadding: 12
    readonly property real barOpacity: 0.92
    readonly property int gapOut: 6

    readonly property string fontFamily: "JetBrains Mono Nerd Font"
    readonly property int fontSize: 12
    readonly property int fontSizeSmall: 10
    readonly property int fontSizeLarge: 14
    readonly property int iconSize: 14

    readonly property int notifWidth: 380
    readonly property int notifRadius: 8
    readonly property int notifPadding: 12
    readonly property int notifSpacing: 8
    readonly property int notifTimeout: 5000

    readonly property int osdWidth: 220
    readonly property int osdHeight: 40
    readonly property int osdRadius: 20
    readonly property int osdTimeout: 1500
    readonly property int osdBarHeight: 4
    readonly property int osdBarRadius: 2

    readonly property int drawerWidth: 380
    readonly property int powerBtnSize: 72
    readonly property int powerBtnRadius: 16
    readonly property int powerBtnSpacing: 24
    readonly property int powerIconSize: 28

    readonly property int popupWidth: 320
    readonly property int popupRadius: 10
    readonly property int popupPadding: 14
    readonly property int popupTopMargin: barHeight + barMargin + gapOut

    readonly property int audioPopupWidth: 340
    readonly property int sliderHeight: 6

    readonly property int calCellSize: 32
    readonly property int calWidth: calCellSize * 7 + popupPadding * 2 + 12

    readonly property int mprisArtSize: 80
    readonly property int mprisPopupWidth: 340

    // ── Animation constants ──
    // Shell chrome should feel instant/reactive, not floaty.
    // Opens are slightly slower (ease-in to land), close/nav are fast (get out of the way).
    readonly property real animScale: 1.6

    // Micro-interactions (press scale, icon color, hover bg)
    readonly property int animMicro:       60
    readonly property int animFast:        80
    readonly property int animHover:       120

    // Content transitions (state swaps, cross-fades, text changes)
    readonly property int animContentSwap: 150
    readonly property int animNormal:      180
    readonly property int animSpring:      220

    // Popup open — keep a bit of weight so it feels intentional
    readonly property int animPopupIn:     280
    // Popup close / navigation — snappy, get out of the way
    readonly property int animPopupOut:    150
    readonly property int animMedium:      250

    // Popup height resize
    readonly property int animHeightResize: 200

    // Notification slide
    readonly property int animNotifIn:     280
    readonly property int animNotifOut:    180

    // Stagger delay per item in lists/grids
    readonly property int animStagger:     30

    // OSD pop
    readonly property int animOsdIn:       200
    readonly property int animOsdOut:      140

    // ── Shared interactive element geometry ──
    readonly property int hoverRadius: 8        // unified hover highlight corner radius
    readonly property int listItemHeight: 40    // standard interactive row height
    readonly property int listItemPadding: 10   // standard row left/right inset
    readonly property int sectionSpacing: 12    // space between logical sections in a popup
    readonly property int headerFontSize: fontSize // popup header text size

    // Toggle switch dimensions
    readonly property int toggleWidth: 40
    readonly property int toggleHeight: 22
    readonly property int toggleKnobSize: 18

    // Small action button geometry
    readonly property int btnRadius: 6
    readonly property int btnHeight: 26
    readonly property int btnPaddingH: 12
}
