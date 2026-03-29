import QtQuick

QtObject {
    property bool powerMenuVisible: false
    property bool drawerVisible: false
    property bool calendarVisible: false
    property bool trayVisible: false
    property bool mprisVisible: false
    property bool audioVisible: false
    property bool wifiVisible: false
    property bool bluetoothVisible: false
    property bool powerProfileVisible: false
    property bool settingsVisible: false
    property bool vpnVisible: false

    function closeAll() {
        powerMenuVisible = false
        drawerVisible = false
        calendarVisible = false
        trayVisible = false
        mprisVisible = false
        audioVisible = false
        wifiVisible = false
        bluetoothVisible = false
        powerProfileVisible = false
        settingsVisible = false
        vpnVisible = false
    }

    function toggleExclusive(isVisible, showPopup) {
        if (isVisible) {
            closeAll()
            return
        }

        closeAll()
        showPopup()
    }

    function togglePowerMenu() { toggleExclusive(powerMenuVisible, function() { powerMenuVisible = true }) }
    function toggleDrawer() { toggleExclusive(drawerVisible, function() { drawerVisible = true }) }
    function toggleCalendar() { toggleExclusive(calendarVisible, function() { calendarVisible = true }) }
    function toggleTray() { toggleExclusive(trayVisible, function() { trayVisible = true }) }
    function toggleMpris() { toggleExclusive(mprisVisible, function() { mprisVisible = true }) }
    function toggleAudio() { toggleExclusive(audioVisible, function() { audioVisible = true }) }
    function toggleWifi() { toggleExclusive(wifiVisible, function() { wifiVisible = true }) }
    function toggleBluetooth() { toggleExclusive(bluetoothVisible, function() { bluetoothVisible = true }) }
    function togglePowerProfile() { toggleExclusive(powerProfileVisible, function() { powerProfileVisible = true }) }
    function toggleSettings() { toggleExclusive(settingsVisible, function() { settingsVisible = true }) }
    function toggleVpn() { toggleExclusive(vpnVisible, function() { vpnVisible = true }) }
}
