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

  // KeyboardPanel, PAS PopupCard : un PopupCard est un `PopupWindow`, donc un
  // xdg-popup — et un xdg-popup NE RECOIT PAS le focus clavier (c'est ecrit
  // dans l'en-tete de `Ui/KeyboardPanel.qml` : « xdg-popups … only receive keys
  // after a click/hover routes focus through their parent surface »). Aucun
  // champ n'acceptait donc la moindre frappe : ni saisie, ni effacement, seules
  // les fleches des champs numeriques repondaient, puisqu'elles passent par la
  // SOURIS. `KeyboardPanel` est un layer-shell qui amorce en
  // `WlrKeyboardFocus.Exclusive` puis retombe en `OnDemand` — c'est ce
  // qu'utilisent tous les panneaux d'Omarchy qui saisissent du texte, y compris
  // le plugin Frigate.
  //
  // Son API est un sous-ensemble de celle de PopupCard ; ni `triggerMode` ni
  // `containsMouse` n'etaient utilises ici. Il gere lui-meme la fermeture au
  // clic ailleurs (surface plein ecran + jumelles sur les autres ecrans), a la
  // place du HyprlandFocusGrab.
  KeyboardPanel {
    id: card
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: card.fittedContentWidth(Style.space(420))
    contentHeight: card.fittedContentHeight(column.implicitHeight)

    // `Keys.priority: Keys.BeforeItem` : sans `blocked`, ce capteur avalerait
    // CHAQUE touche avant les champs — y compris les lettres et les chiffres.
    // Chaque champ editable doit donc figurer dans la condition.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus
        || widthField.field.activeFocus || heightField.field.activeFocus
        || marginXField.field.activeFocus || marginYField.field.activeFocus
        || animField.field.activeFocus
        || positionDropdown.popupOpen || languageDropdown.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(8)

        PanelSectionHeader { text: root.tr("sectionDashboard") }

        TextField {
          id: urlField
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
            id: widthField
            label: root.tr("width")
            from: 200; to: 4000; stepSize: 10
            value: root.get("width", 480)
            onModified: function(v) { root.save("width", v) }
          }

          NumberField {
            id: heightField
            label: root.tr("height")
            from: 200; to: 4000; stepSize: 10
            value: root.get("height", 900)
            onModified: function(v) { root.save("height", v) }
          }
        }

        Dropdown {
          id: positionDropdown
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
            id: marginXField
            label: root.tr("marginSide")
            from: 0; to: 400; stepSize: 1
            value: root.get("marginX", root.get("margin", 12))
            onModified: function(v) { root.save("marginX", v) }
          }

          NumberField {
            id: marginYField
            label: root.tr("marginVertical")
            from: 0; to: 400; stepSize: 1
            value: root.get("marginY", root.get("margin", 12))
            onModified: function(v) { root.save("marginY", v) }
          }
        }

        NumberField {
          id: animField
          label: root.tr("openDuration")
          from: 0; to: 1200; stepSize: 10
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
          id: languageDropdown
          Layout.fillWidth: true
          label: root.tr("language")
          options: root.languageOptions
          value: root.get("language", "auto")
          onChanged: function(v) { root.save("language", v) }
        }
      }
    }
  }
}
