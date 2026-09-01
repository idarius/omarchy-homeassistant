import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Strings.js" as Strings

// Panneau de configuration, ouvert au clic droit sur l'icone.
//
// Structure imposee par Omarchy : `Panel` est un Item SANS rendu, qui ne porte
// que le cycle ouvrir/fermer. Le contenu doit vivre dans un PopupCard pilote
// par `open: root.opened` — sinon les enfants sont dessines a meme la barre
// (c'est ce qui affichait « TABLEAU DE BORD » en haut de l'ecran).
//
// Les valeurs partent dans shell.json par bar.shell.updateEntryInline puis
// reviennent au widget par le meme chemin ; on applique d'abord localement
// pour que l'interface reagisse au clic, comme le fait l'horloge d'Omarchy.
Panel {
  id: root
  moduleName: "io.github.idarius.homeassistant"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // La barre identifie un panneau par le widget monte dans son emplacement,
  // pas par ce panneau imbrique.
  readonly property var barIdentity: hostWidget || root

  // La langue est resolue par le widget ; le panneau la suit.
  readonly property string lang: hostWidget && hostWidget.lang ? hostWidget.lang : "en"
  function tr(key) { return Strings.t(root.lang, key) }

  function get(key, fallback) {
    var src = hostWidget && hostWidget.settings ? hostWidget.settings : {}
    var v = src[key]
    return v === undefined || v === null ? fallback : v
  }

  // Recopier l'entree entiere evite que deux reglages modifies coup sur coup
  // s'ecrasent mutuellement.
  function save(key, value) {
    if (!hostWidget || !hostWidget.bar || !hostWidget.bar.shell) return
    var entry = { id: root.moduleName }
    var src = hostWidget.settings || {}
    for (var k in src) if (k !== "id") entry[k] = src[k]
    entry[key] = value

    hostWidget.settings = entry
    if (typeof hostWidget.bar.shell.updateEntryInline === "function")
      hostWidget.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  readonly property var positionOptions: Strings.positionOptions(root.lang)
  readonly property var languageOptions: Strings.languageOptions(root.lang)

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    contentWidth: card.fittedContentWidth(Style.space(420))
    contentHeight: card.fittedContentHeight(column.implicitHeight)

    ColumnLayout {
      id: column
      anchors.fill: parent
      spacing: Style.space(8)

      PanelSectionHeader { text: root.tr("sectionDashboard") }

      TextField {
        Layout.fillWidth: true
        text: root.get("url", "")
        placeholderText: root.tr("urlPlaceholder")
        onEditingFinished: root.save("url", text)
      }

      PanelSectionHeader { text: root.tr("sectionWindow") }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        NumberField {
          label: root.tr("width")
          from: 200; to: 4000; stepSize: 20
          value: root.get("width", 480)
          onModified: function(v) { root.save("width", v) }
        }

        NumberField {
          label: root.tr("height")
          from: 200; to: 4000; stepSize: 20
          value: root.get("height", 900)
          onModified: function(v) { root.save("height", v) }
        }
      }

      Dropdown {
        Layout.fillWidth: true
        label: root.tr("position")
        options: root.positionOptions
        value: root.get("position", "top-right")
        onChanged: function(v) { root.save("position", v) }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        NumberField {
          label: root.tr("marginSide")
          from: 0; to: 400; stepSize: 4
          value: root.get("marginX", root.get("margin", 12))
          onModified: function(v) { root.save("marginX", v) }
        }

        NumberField {
          label: root.tr("marginVertical")
          from: 0; to: 400; stepSize: 4
          value: root.get("marginY", root.get("margin", 12))
          onModified: function(v) { root.save("marginY", v) }
        }
      }

      NumberField {
        label: root.tr("openDuration")
        from: 0; to: 1200; stepSize: 20
        value: root.get("animMs", 220)
        onModified: function(v) { root.save("animMs", v) }
      }

      PanelSectionHeader { text: root.tr("sectionBehaviour") }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          Layout.fillWidth: true
          text: root.tr("hideOnOutsideClick")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        ToggleSwitch {
          checked: root.get("autoHide", true)
          onToggled: root.save("autoHide", !checked)
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          Layout.fillWidth: true
          text: root.tr("preloadAtStartup")
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        ToggleSwitch {
          checked: root.get("prewarm", true)
          onToggled: root.save("prewarm", !checked)
        }
      }

      Dropdown {
        Layout.fillWidth: true
        label: root.tr("language")
        options: root.languageOptions
        value: root.get("language", "auto")
        onChanged: function(v) { root.save("language", v) }
      }
    }
  }
}
