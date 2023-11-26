type
  Colour = enum
    Red
    Green
    Blue

var x = Red #[ Marker
    ^ test.rename.variableInit ]#
x = Colour.Blue #[ Marker
^ rename.variableUse ]#
