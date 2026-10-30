import QtQuick
import qs.services

QtObject {
    property string name
    property list<string> categories
    /// everything no other category takes, as Windows' "Other" (it held only games: empty)
    property bool rest: false
}
