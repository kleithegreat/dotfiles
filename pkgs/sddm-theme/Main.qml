import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root

    width: 1920
    height: 1080
    focus: true

    function cfg(key) {
        return typeof config !== "undefined" ? config[key] : undefined;
    }

    function str(val, fb) {
        return val !== undefined && val !== null && String(val) !== "" ? String(val) : fb;
    }

    function col(val, fb) {
        const raw = str(val, fb);
        try {
            return Qt.color(raw);
        } catch (e) {
            return Qt.color(fb);
        }
    }

    function num(val, fb) {
        const parsed = Number(val);
        return isFinite(parsed) && parsed > 0 ? parsed : fb;
    }

    function _channel(value) {
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    }

    function luminance(c) {
        return 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);
    }

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property color cBg: col(cfg("bg"), "#282828")
    readonly property color cBg1: col(cfg("bg1"), "#3c3836")
    readonly property color cBg2: col(cfg("bg2"), "#504945")
    readonly property color cFg: col(cfg("fg"), "#ebdbb2")
    readonly property color cFg2: col(cfg("fg2"), "#d5c4a1")
    readonly property color cFg3: col(cfg("fg3"), "#bdae93")
    readonly property color cAccent: col(cfg("accent"), "#458588")
    readonly property color cOnAccent: col(cfg("onAccent"), "#ebdbb2")
    readonly property color cRed: col(cfg("red"), "#fb4934")
    readonly property color cYellow: col(cfg("yellow"), "#fabd2f")

    readonly property bool isDark: luminance(cBg) < 0.28
    readonly property color cRim: isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.10)
    readonly property color cBorder: Qt.tint(cBg, cRim)
    readonly property color cHover: withAlpha(cFg, isDark ? 0.07 : 0.06)
    readonly property color cPress: withAlpha(cFg, isDark ? 0.12 : 0.10)
    readonly property color cShadow: Qt.rgba(0, 0, 0, isDark ? 0.38 : 0.18)

    readonly property string systemFont: str(cfg("systemFont"), "SF Pro")
    readonly property string monoFont: str(cfg("monoFont"), "JetBrainsMono Nerd Font")
    readonly property int baseFontSize: Math.max(10, Math.round(num(cfg("fontSize"), 12)))

    readonly property string bgRaw: str(cfg("background"), "/var/lib/desktopctl/sddm/background")
    readonly property url bgUrl: bgRaw.startsWith("/") ? ("file://" + bgRaw) : bgRaw

    property int userIndex: typeof userModel !== "undefined" && userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

    property bool sessionMenuOpen: false
    property bool userMenuOpen: false
    property bool loggingIn: false
    property bool authFailed: false
    property string errorText: ""
    property date now: new Date()

    readonly property bool capsLockOn: typeof keyboard !== "undefined" && Boolean(keyboard.capsLock)
    readonly property string currentUserName: userProxy.currentItem
        ? userProxy.currentItem.userName
        : (typeof userModel !== "undefined" && userModel.lastUser ? String(userModel.lastUser) : "")
    readonly property string displayName: userProxy.currentItem && userProxy.currentItem.userDisplayName !== ""
        ? userProxy.currentItem.userDisplayName
        : (currentUserName !== "" ? currentUserName : "User")
    readonly property string currentSessionName: sessionProxy.currentItem && sessionProxy.currentItem.sessionName !== ""
        ? sessionProxy.currentItem.sessionName
        : "Session"

    function closePopups() {
        sessionMenuOpen = false;
        userMenuOpen = false;
    }

    function submitLogin() {
        if (loggingIn || typeof sddm === "undefined" || currentUserName === "")
            return;
        closePopups();
        loggingIn = true;
        authFailed = false;
        errorText = "";
        sddm.login(currentUserName, passwordInput.text, sessionIndex);
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    ListView {
        id: userProxy
        opacity: 0
        width: 1
        height: 1
        enabled: false
        model: typeof userModel !== "undefined" ? userModel : null
        currentIndex: root.userIndex
        delegate: Item {
            required property string name
            required property string realName
            readonly property string userName: name
            readonly property string userDisplayName: realName !== "" ? realName : name
        }
    }

    ListView {
        id: sessionProxy
        opacity: 0
        width: 1
        height: 1
        enabled: false
        model: typeof sessionModel !== "undefined" ? sessionModel : null
        currentIndex: root.sessionIndex
        delegate: Item {
            required property string name
            readonly property string sessionName: name
        }
    }

    Connections {
        target: typeof sddm !== "undefined" ? sddm : null

        function onLoginSucceeded() {
            root.loggingIn = true;
            root.authFailed = false;
            root.errorText = "";
        }

        function onLoginFailed() {
            root.loggingIn = false;
            root.authFailed = true;
            root.errorText = "Incorrect password";
            passwordInput.text = "";
            shakeAnim.restart();
            passwordInput.forceActiveFocus();
        }

        function onInformationMessage(message) {
            if (message && String(message) !== "")
                root.errorText = String(message);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.cBg
    }

    Image {
        id: bgImage
        anchors.fill: parent
        source: root.bgUrl
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        visible: false
    }

    MultiEffect {
        anchors.fill: bgImage
        source: bgImage
        visible: bgImage.status === Image.Ready
        blurEnabled: true
        blur: 0.72
        blurMax: 48
        autoPaddingEnabled: false
        saturation: 0.10
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.isDark ? 0.38 : 0.22)
        visible: bgImage.status === Image.Ready
    }

    Item {
        id: fgLayer
        anchors.fill: parent
        visible: typeof primaryScreen === "undefined" || primaryScreen

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.closePopups();
                passwordInput.forceActiveFocus();
            }
        }

        Item {
            id: cardWrap
            width: 440
            height: cardContent.implicitHeight + 68
            anchors.centerIn: parent
            opacity: 0
            transform: Translate {
                id: cardOffset
                x: 0
                y: 12
            }

            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                blur: 24
                spread: 0
                offset: Qt.vector2d(0, 8)
                color: root.cShadow
                cached: true
            }

            Rectangle {
                id: card
                anchors.fill: parent
                radius: 24
                color: root.cBg
                border.width: 1
                border.color: root.cBorder
                antialiasing: true

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.sessionMenuOpen)
                            root.sessionMenuOpen = false;
                        passwordInput.forceActiveFocus();
                    }
                }

                ColumnLayout {
                    id: cardContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 36
                    anchors.rightMargin: 36
                    spacing: 8

                    Rectangle {
                        id: userPill
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: userRow.implicitWidth + (userProxy.count > 1 ? 20 : 8)
                        implicitHeight: 28
                        radius: 10
                        color: userProxy.count > 1 && userMouse.pressed
                            ? root.cPress
                            : (userProxy.count > 1 && (userMouse.containsMouse || root.userMenuOpen) ? root.cHover : "transparent")

                        RowLayout {
                            id: userRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "Hi, " + root.displayName
                                color: root.cFg2
                                font.family: root.systemFont
                                font.pixelSize: root.baseFontSize + 2
                                font.weight: Font.Medium
                            }

                            Text {
                                visible: userProxy.count > 1
                                text: root.userMenuOpen ? "▴" : "▾"
                                color: root.cFg3
                                font.family: root.systemFont
                                font.pixelSize: root.baseFontSize
                            }
                        }

                        MouseArea {
                            id: userMouse
                            anchors.fill: parent
                            enabled: userProxy.count > 1
                            hoverEnabled: userProxy.count > 1
                            cursorShape: userProxy.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                root.sessionMenuOpen = false;
                                root.userMenuOpen = !root.userMenuOpen;
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        text: Qt.formatDateTime(root.now, "HH:mm")
                        color: root.cFg
                        font.family: root.monoFont
                        font.pixelSize: 82
                        font.weight: Font.Normal
                        font.letterSpacing: -2
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 18
                        text: Qt.formatDateTime(root.now, "dddd, MMMM d")
                        color: root.cFg2
                        font.family: root.systemFont
                        font.pixelSize: root.baseFontSize + 3
                        font.weight: Font.Normal
                    }

                    Rectangle {
                        id: passwordBox
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 320
                        Layout.preferredHeight: 48
                        radius: 12
                        color: root.cBg1
                        border.width: (passwordInput.activeFocus || root.authFailed || root.capsLockOn || root.loggingIn) ? 2 : 1
                        border.color: root.authFailed
                            ? root.cRed
                            : (root.capsLockOn
                                ? root.cYellow
                                : ((passwordInput.activeFocus || root.loggingIn) ? root.cAccent : root.cBg2))
                        antialiasing: true

                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: passwordInput.text.length === 0
                            text: "Password"
                            color: root.cFg3
                            font.family: root.systemFont
                            font.pixelSize: root.baseFontSize + 2
                            font.italic: true
                        }

                        TextInput {
                            id: passwordInput
                            anchors.left: parent.left
                            anchors.right: submitPill.visible ? submitPill.left : parent.right
                            anchors.leftMargin: 42
                            anchors.rightMargin: submitPill.visible ? 8 : 42
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            passwordMaskDelay: 0
                            color: root.cFg
                            selectionColor: root.cAccent
                            selectedTextColor: root.cOnAccent
                            cursorVisible: activeFocus
                            font.family: root.systemFont
                            font.pixelSize: root.baseFontSize + 3
                            enabled: !root.loggingIn
                            clip: true
                            focus: true

                            onTextChanged: {
                                if (root.authFailed && text.length > 0) {
                                    root.authFailed = false;
                                    root.errorText = "";
                                }
                            }

                            Keys.onReturnPressed: root.submitLogin()
                            Keys.onEnterPressed: root.submitLogin()
                        }

                        Rectangle {
                            id: submitPill
                            width: 30
                            height: 30
                            radius: 15
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordInput.text.length > 0 && !root.loggingIn
                            color: submitMouse.pressed ? Qt.darker(root.cAccent, 1.12) : root.cAccent
                            antialiasing: true

                            Text {
                                anchors.centerIn: parent
                                text: "→"
                                color: root.cOnAccent
                                font.family: root.systemFont
                                font.pixelSize: root.baseFontSize + 2
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: submitMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.submitLogin()
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        Layout.preferredHeight: 20
                        verticalAlignment: Text.AlignVCenter
                        text: root.errorText !== ""
                            ? root.errorText
                            : (root.loggingIn
                                ? "Signing in…"
                                : (root.capsLockOn ? "Caps Lock is on" : ""))
                        color: root.errorText !== ""
                            ? root.cRed
                            : (root.capsLockOn && !root.loggingIn ? root.cYellow : root.cFg3)
                        font.family: root.systemFont
                        font.pixelSize: root.baseFontSize
                        font.weight: Font.Medium
                    }
                }
            }

            Rectangle {
                id: userPopup
                visible: root.userMenuOpen && userProxy.count > 1
                width: 240
                height: userList.implicitHeight + 12
                anchors.top: card.top
                anchors.topMargin: 64
                anchors.horizontalCenter: card.horizontalCenter
                radius: 14
                color: root.cBg
                border.width: 1
                border.color: root.cBorder
                antialiasing: true
                z: 10

                RectangularShadow {
                    anchors.fill: parent
                    radius: parent.radius
                    blur: 18
                    spread: 0
                    offset: Qt.vector2d(0, 6)
                    color: root.cShadow
                    cached: true
                    z: -1
                }

                ListView {
                    id: userList
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2
                    implicitHeight: Math.min(contentHeight, 220)
                    clip: true
                    model: typeof userModel !== "undefined" ? userModel : null

                    delegate: Rectangle {
                        id: userRowItem
                        required property int index
                        required property string name
                        required property string realName
                        readonly property string rowDisplayName: realName !== "" ? realName : name

                        width: userList.width
                        height: 36
                        radius: 9
                        color: itemMouse.pressed
                            ? root.cPress
                            : (itemMouse.containsMouse ? root.cHover : "transparent")

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            Rectangle {
                                Layout.preferredWidth: 6
                                Layout.preferredHeight: 6
                                radius: 3
                                color: userRowItem.index === root.userIndex ? root.cAccent : "transparent"
                            }

                            Text {
                                Layout.fillWidth: true
                                text: userRowItem.rowDisplayName
                                color: userRowItem.index === root.userIndex ? root.cFg : root.cFg2
                                font.family: root.systemFont
                                font.pixelSize: root.baseFontSize + 1
                                font.weight: userRowItem.index === root.userIndex ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.userIndex = userRowItem.index;
                                root.userMenuOpen = false;
                                root.authFailed = false;
                                root.errorText = "";
                                passwordInput.text = "";
                                passwordInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        ParallelAnimation {
            id: enterAnim
            running: true
            NumberAnimation {
                target: cardWrap
                property: "opacity"
                from: 0
                to: 1
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: cardOffset
                property: "y"
                from: 12
                to: 0
                duration: 280
                easing.type: Easing.OutCubic
            }
        }

        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: cardOffset; property: "x"; to: -10; duration: 55; easing.type: Easing.OutQuad }
            NumberAnimation { target: cardOffset; property: "x"; to: 10; duration: 55; easing.type: Easing.InOutQuad }
            NumberAnimation { target: cardOffset; property: "x"; to: -6; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: cardOffset; property: "x"; to: 6; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: cardOffset; property: "x"; to: 0; duration: 55; easing.type: Easing.OutQuad }
        }

        Rectangle {
            id: sessionPopup
            visible: root.sessionMenuOpen && sessionProxy.count > 0
            width: Math.max(sessionPill.width, 220)
            height: sessionList.implicitHeight + 12
            anchors.left: sessionPill.left
            anchors.bottom: sessionPill.top
            anchors.bottomMargin: 8
            radius: 14
            color: root.cBg
            border.width: 1
            border.color: root.cBorder
            antialiasing: true
            z: 10

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                blur: 18
                spread: 0
                offset: Qt.vector2d(0, 6)
                color: root.cShadow
                cached: true
                z: -1
            }

            ListView {
                id: sessionList
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2
                implicitHeight: Math.min(contentHeight, 240)
                clip: true
                model: typeof sessionModel !== "undefined" ? sessionModel : null

                delegate: Rectangle {
                    id: sessionRowItem
                    required property int index
                    required property string name
                    readonly property string rowSessionName: name !== "" ? name : "Session"

                    width: sessionList.width
                    height: 36
                    radius: 9
                    color: sessionItemMouse.pressed
                        ? root.cPress
                        : (sessionItemMouse.containsMouse ? root.cHover : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 6
                            Layout.preferredHeight: 6
                            radius: 3
                            color: sessionRowItem.index === root.sessionIndex ? root.cAccent : "transparent"
                        }

                        Text {
                            Layout.fillWidth: true
                            text: sessionRowItem.rowSessionName
                            color: sessionRowItem.index === root.sessionIndex ? root.cFg : root.cFg2
                            font.family: root.systemFont
                            font.pixelSize: root.baseFontSize + 1
                            font.weight: sessionRowItem.index === root.sessionIndex ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: sessionItemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sessionIndex = sessionRowItem.index;
                            root.sessionMenuOpen = false;
                            passwordInput.forceActiveFocus();
                        }
                    }
                }
            }
        }

        Rectangle {
            id: sessionPill
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 24
            implicitWidth: sessionRow.implicitWidth + 24
            implicitHeight: 36
            radius: 12
            color: sessionMouse.pressed
                ? Qt.tint(root.cBg, root.cPress)
                : (sessionMouse.containsMouse || root.sessionMenuOpen ? Qt.tint(root.cBg, root.cHover) : root.cBg)
            border.width: 1
            border.color: root.cBorder
            antialiasing: true

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                blur: 14
                spread: 0
                offset: Qt.vector2d(0, 4)
                color: root.cShadow
                cached: true
                z: -1
            }

            RowLayout {
                id: sessionRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: root.currentSessionName
                    color: root.cFg2
                    font.family: root.systemFont
                    font.pixelSize: root.baseFontSize
                    font.weight: Font.Medium
                }

                Text {
                    visible: sessionProxy.count > 1
                    text: root.sessionMenuOpen ? "▴" : "▾"
                    color: root.cFg3
                    font.family: root.systemFont
                    font.pixelSize: root.baseFontSize - 1
                }
            }

            MouseArea {
                id: sessionMouse
                anchors.fill: parent
                enabled: sessionProxy.count > 1
                hoverEnabled: sessionProxy.count > 1
                cursorShape: sessionProxy.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    root.userMenuOpen = false;
                    root.sessionMenuOpen = !root.sessionMenuOpen;
                }
            }
        }

        Rectangle {
            id: powerPill
            readonly property bool anyAction: (typeof sddm !== "undefined") && (sddm.canSuspend || sddm.canReboot || sddm.canPowerOff)
            visible: anyAction
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            implicitWidth: powerRow.implicitWidth + 12
            implicitHeight: 36
            radius: 12
            color: root.cBg
            border.width: 1
            border.color: root.cBorder
            antialiasing: true

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                blur: 14
                spread: 0
                offset: Qt.vector2d(0, 4)
                color: root.cShadow
                cached: true
                z: -1
            }

            RowLayout {
                id: powerRow
                anchors.centerIn: parent
                spacing: 4

                Rectangle {
                    visible: typeof sddm !== "undefined" && sddm.canSuspend
                    implicitWidth: suspendLabel.implicitWidth + 16
                    implicitHeight: 26
                    radius: 8
                    color: suspendMouse.pressed ? root.cPress : (suspendMouse.containsMouse ? root.cHover : "transparent")

                    Text {
                        id: suspendLabel
                        anchors.centerIn: parent
                        text: "Suspend"
                        color: root.cFg2
                        font.family: root.systemFont
                        font.pixelSize: root.baseFontSize
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: suspendMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sddm.suspend()
                    }
                }

                Rectangle {
                    visible: typeof sddm !== "undefined" && sddm.canSuspend && (sddm.canReboot || sddm.canPowerOff)
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 14
                    color: root.cBg2
                }

                Rectangle {
                    visible: typeof sddm !== "undefined" && sddm.canReboot
                    implicitWidth: rebootLabel.implicitWidth + 16
                    implicitHeight: 26
                    radius: 8
                    color: rebootMouse.pressed ? root.cPress : (rebootMouse.containsMouse ? root.cHover : "transparent")

                    Text {
                        id: rebootLabel
                        anchors.centerIn: parent
                        text: "Restart"
                        color: root.cFg2
                        font.family: root.systemFont
                        font.pixelSize: root.baseFontSize
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: rebootMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sddm.reboot()
                    }
                }

                Rectangle {
                    visible: typeof sddm !== "undefined" && sddm.canReboot && sddm.canPowerOff
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 14
                    color: root.cBg2
                }

                Rectangle {
                    visible: typeof sddm !== "undefined" && sddm.canPowerOff
                    implicitWidth: powerOffLabel.implicitWidth + 16
                    implicitHeight: 26
                    radius: 8
                    color: powerOffMouse.pressed ? root.cPress : (powerOffMouse.containsMouse ? root.cHover : "transparent")

                    Text {
                        id: powerOffLabel
                        anchors.centerIn: parent
                        text: "Shut down"
                        color: root.cFg2
                        font.family: root.systemFont
                        font.pixelSize: root.baseFontSize
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: powerOffMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sddm.powerOff()
                    }
                }
            }
        }
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            if (root.sessionMenuOpen || root.userMenuOpen) {
                root.closePopups();
            } else {
                passwordInput.text = "";
                root.authFailed = false;
                root.errorText = "";
            }
            passwordInput.forceActiveFocus();
            event.accepted = true;
        } else if (event.key === Qt.Key_F2 && sessionProxy.count > 1) {
            root.sessionIndex = (root.sessionIndex + 1) % sessionProxy.count;
            event.accepted = true;
        }
    }

    Component.onCompleted: passwordInput.forceActiveFocus()
}
