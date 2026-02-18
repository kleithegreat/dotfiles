pragma Singleton
import QtQuick

QtObject {
    // Gruvbox Dark
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

    // Bar
    readonly property int barHeight: 32
    readonly property int barMargin: 4
    readonly property int barRadius: 8
    readonly property int barSpacing: 8
    readonly property int barPadding: 12
    readonly property real barOpacity: 0.92
    readonly property int gapOut: 6

    // Fonts
    readonly property string fontFamily: "JetBrains Mono Nerd Font"
    readonly property int fontSize: 12
    readonly property int fontSizeSmall: 10
    readonly property int fontSizeLarge: 14
    readonly property int iconSize: 14

    // Notifications
    readonly property int notifWidth: 380
    readonly property int notifRadius: 8
    readonly property int notifPadding: 12
    readonly property int notifSpacing: 8
    readonly property int notifTimeout: 5000

    // OSD
    readonly property int osdWidth: 220
    readonly property int osdHeight: 40
    readonly property int osdRadius: 20
    readonly property int osdTimeout: 1500
    readonly property int osdBarHeight: 4
    readonly property int osdBarRadius: 2

    // Drawer / Power menu
    readonly property int drawerWidth: 380
    readonly property int powerBtnSize: 72
    readonly property int powerBtnRadius: 16
    readonly property int powerBtnSpacing: 24
    readonly property int powerIconSize: 28

    // Popups (shared)
    readonly property int popupWidth: 320
    readonly property int popupRadius: 10
    readonly property int popupPadding: 14
    readonly property int popupTopMargin: barHeight + barMargin + gapOut

    // Audio popup
    readonly property int audioPopupWidth: 340
    readonly property int sliderHeight: 6

    // Calendar
    readonly property int calCellSize: 32
    readonly property int calWidth: calCellSize * 7 + popupPadding * 2 + 12

    // MPRIS popup
    readonly property int mprisArtSize: 80
    readonly property int mprisPopupWidth: 340
}
