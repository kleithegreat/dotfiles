import QtQuick

QtObject {
    property bool powerMenuVisible: false
    property bool drawerVisible: false
    property bool calendarVisible: false
    property bool trayVisible: false
    property bool mprisVisible: false
    property bool settingsVisible: false
    property bool quickSettingsVisible: false

    function closeAll() {
        powerMenuVisible = false
        drawerVisible = false
        calendarVisible = false
        trayVisible = false
        mprisVisible = false
        settingsVisible = false
        quickSettingsVisible = false
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
    function toggleSettings() { toggleExclusive(settingsVisible, function() { settingsVisible = true }) }
    function toggleQuickSettings() { toggleExclusive(quickSettingsVisible, function() { quickSettingsVisible = true }) }
}
