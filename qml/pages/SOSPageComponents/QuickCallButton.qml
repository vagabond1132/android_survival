/**
 * @file QuickCallButton.qml
 * @brief 快速拨号按钮
 */

import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import OutdoorSurvival 1.0

Button {
    id: quickCall
    property string number: ""
    property string label: ""
    property string accentColor: "#D32F2F"

    text: label + "\n" + number
    Material.background: accentColor
    Layout.preferredHeight: 64

    onClicked: {
        if (number === "120") emergencyService.call120()
        else if (number === "110") emergencyService.call110()
        else if (number === "119") emergencyService.call119()
        else emergencyService.callNumber(number)
    }
}
