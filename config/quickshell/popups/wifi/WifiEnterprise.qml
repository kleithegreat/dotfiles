import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string targetSsid
    required property string connectError

    property bool passwordVisible: false
    property bool submitAttempted: false
    readonly property string trimmedIdentity: identityField.text.trim()
    readonly property string trimmedPassword: passwordField.text.trim()
    readonly property bool canSubmit: root.trimmedIdentity !== "" && root.trimmedPassword !== ""
    readonly property string identityErrorText: root.submitAttempted && root.trimmedIdentity === "" ? "Identity required." : ""
    readonly property string passwordErrorText: {
        if (root.connectError !== "")
            return root.connectError;
        if (root.submitAttempted && root.trimmedPassword === "")
            return "Password required.";
        return "";
    }

    signal enterpriseSubmitted(string identity, string password)
    signal backRequested()

    onVisibleChanged: {
        if (visible) {
            identityField.text = "";
            passwordField.text = "";
            root.passwordVisible = false;
            root.submitAttempted = false;
            identityField.forceInputFocus();
        }
    }

    function submit() {
        if (!root.canSubmit) {
            root.submitAttempted = true;
            if (root.trimmedIdentity === "")
                identityField.forceInputFocus();
            else
                passwordField.forceInputFocus();
            return;
        }

        root.submitAttempted = false;
        root.enterpriseSubmitted(root.trimmedIdentity, root.trimmedPassword);
    }

    spacing: 8

    Text { text: "Network: " + root.targetSsid; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
    Text { text: "802.1X \u00b7 PEAP / MSCHAPv2"; color: Theme.fg4
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }

    WifiFormField {
        id: identityField
        Layout.fillWidth: true
        placeholder: "Username / Identity"
        errorText: root.identityErrorText
        onEdited: root.submitAttempted = false
        onSubmitted: {
            if (root.trimmedIdentity === "") {
                root.submitAttempted = true;
                return;
            }

            passwordField.forceInputFocus();
        }
        onEscaped: root.backRequested()
    }

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
        label: "Sign In"
        canSubmit: root.canSubmit
        onClicked: root.submit()
    }

    Text { text: "Only PEAP/MSCHAPv2 is supported."; color: Theme.fg4; wrapMode: Text.WordWrap
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMicro; Layout.fillWidth: true }
}
