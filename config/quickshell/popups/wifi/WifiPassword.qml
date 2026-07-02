import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string targetSsid
    required property string connectError

    property bool passwordVisible: false
    property bool submitAttempted: false
    readonly property string trimmedPassword: passwordField.text.trim()
    readonly property bool canSubmit: root.trimmedPassword !== ""
    readonly property string passwordErrorText: {
        if (root.connectError !== "")
            return root.connectError;
        if (root.submitAttempted && !root.canSubmit)
            return "Password required.";
        return "";
    }

    signal passwordSubmitted(string password)
    signal backRequested()

    onVisibleChanged: {
        if (visible) {
            passwordField.text = "";
            root.passwordVisible = false;
            root.submitAttempted = false;
            passwordField.forceInputFocus();
        }
    }

    function submit() {
        if (!root.canSubmit) {
            root.submitAttempted = true;
            passwordField.forceInputFocus();
            return;
        }

        root.submitAttempted = false;
        root.passwordSubmitted(root.trimmedPassword);
    }

    spacing: 8

    Text { text: "Network: " + root.targetSsid; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

    WifiFormField {
        id: passwordField
        Layout.fillWidth: true
        placeholder: "Password"
        isPassword: true
        revealed: root.passwordVisible
        errorText: root.passwordErrorText
        onRevealToggled: root.passwordVisible = !root.passwordVisible
        onEdited: root.submitAttempted = false
        onSubmitted: root.submit()
        onEscaped: root.backRequested()
    }

    WifiSubmitButton {
        label: "Connect"
        canSubmit: root.canSubmit
        onClicked: root.submit()
    }
}
