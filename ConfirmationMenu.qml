import QtQuick
import qs.Commons
import qs.Ui

// Omalaunch-local confirmation and result content. The host replaces its normal
// content with this item, so this is a menu view and not a dialog overlay.
Item {
  id: control

  property bool opened: false
  property string heading: "Confirm"
  property string headingIcon: ""
  property color headingColor: foreground
  property real messageOpacity: 0.58
  property string message: ""
  property string cancelText: "Cancel"
  property string actionText: "Continue"
  property bool resultOnly: false
  property bool actionFirst: false
  property string defaultChoice: "cancel"
  property string actionTone: "neutral"
  property string actionIcon: ""
  property string cancelIcon: "󰁍"
  property int selectedIndex: 0

  property color foreground: "white"
  property color selectedBackground: "#404040"
  property color selectedText: "white"
  property color mutedText: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.64)
  property color accentText: Color.accent
  property color dangerText: Color.urgent
  property var selectedBorderSpec: Border.none()
  property string fontFamily: "sans-serif"
  property int cornerRadius: Style.cornerRadius
  property int itemFontSize: Style.font.title
  property int secondaryFontSize: Style.font.bodySmall
  property int rowHeight: Style.space(44)
  property int headerHeight: Style.space(44)
  property int contentSpacing: Style.spacing.md
  property real maximumHeight: Number.POSITIVE_INFINITY

  signal canceled()
  signal confirmed()

  visible: opened
  enabled: opened
  implicitHeight: Math.min(content.implicitHeight, maximumHeight > 0 ? maximumHeight : content.implicitHeight)

  onOpenedChanged: if (opened) { selectedIndex = defaultIndex(); Qt.callLater(ensureChoiceVisible) }
  onResultOnlyChanged: if (opened) { selectedIndex = defaultIndex(); Qt.callLater(ensureChoiceVisible) }
  onSelectedIndexChanged: Qt.callLater(ensureChoiceVisible)

  function optionCount() { return resultOnly ? 1 : 2 }
  function actionIndex() { return resultOnly || actionFirst ? 0 : 1 }
  function cancelIndex() { return actionFirst ? 1 : 0 }
  function defaultIndex() { return resultOnly ? 0 : (defaultChoice === "action" ? actionIndex() : cancelIndex()) }
  function optionAt(index) {
    if (resultOnly || index === actionIndex())
      return { role: "action", text: actionText, icon: actionIcon }
    return { role: "cancel", text: cancelText, icon: cancelIcon }
  }
  function optionColor(option, selected) {
    if (selected) return selectedText
    if (option.role === "cancel") return mutedText
    if (actionTone === "danger") return dangerText
    if (actionTone === "accent") return accentText
    return foreground
  }
  function moveSelection(delta) {
    var count = optionCount()
    selectedIndex = (selectedIndex + delta + count) % count
  }
  function activateSelection() {
    if (!resultOnly && selectedIndex === cancelIndex()) canceled()
    else confirmed()
  }
  function ensureChoiceVisible() {
    if (!opened || choices.y === undefined) return
    var top = choices.y + selectedIndex * (rowHeight + Style.spacing.xs)
    var bottom = top + rowHeight
    if (top < viewport.contentY) viewport.contentY = top
    else if (bottom > viewport.contentY + viewport.height) viewport.contentY = bottom - viewport.height
  }
  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) canceled()
    else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers === Qt.NoModifier)) moveSelection(-1)
    else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers === Qt.NoModifier)) moveSelection(1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) activateSelection()
    return true
  }

  // Consume pointer input in blank content. Only a choice can cause an action.
  MouseArea { anchors.fill: parent }

  Flickable {
    id: viewport
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: content
      width: viewport.width
      spacing: control.contentSpacing

    Item {
      width: parent.width
      height: control.headerHeight

      Text {
        anchors.fill: parent
        text: (control.headingIcon ? control.headingIcon + "  " : "") + control.heading
        color: control.headingColor
        font.family: control.fontFamily
        font.pixelSize: control.itemFontSize
        font.weight: Font.Medium
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }
    }

    Text {
      width: parent.width
      text: control.message
      color: control.foreground
      opacity: control.messageOpacity
      font.family: control.fontFamily
      font.pixelSize: control.secondaryFontSize
      wrapMode: Text.Wrap
    }

    Column {
      id: choices
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: control.optionCount()

        BorderSurface {
          required property int index
          property var option: control.optionAt(index)
          width: parent.width
          height: control.rowHeight
          radius: control.cornerRadius
          color: control.selectedIndex === index ? control.selectedBackground : "transparent"
          borderSpec: control.selectedIndex === index ? control.selectedBorderSpec : Border.none()

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              width: Style.space(36)
              visible: option.icon.length > 0
              text: option.icon
              color: control.optionColor(option, control.selectedIndex === index)
              font.family: "omarchy"
              font.pixelSize: control.itemFontSize
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: parent.width - (option.icon.length > 0 ? Style.space(42) : Style.space(10))
              text: option.text
              color: control.optionColor(option, control.selectedIndex === index)
              font.family: control.fontFamily
              font.pixelSize: control.itemFontSize
              font.weight: Font.Medium
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: control.selectedIndex = index
            onClicked: control.activateSelection()
          }
        }
      }
    }
    }
  }
}
