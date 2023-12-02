type
  Colour = enum
    Red #[ Marker
     ^ enum.declare ]#
    Green
    Blue

proc helloWorld() = discard


helloWorld()

block basicVariables:
  var x = 1 #[ Marker
      ^ rename.variableInit ]#
  x = 2 #[ Marker
  ^ rename.variableUse ]#

block renameEnum:
  var a = Red #[ Marker
           ^ enum.varuse ]#
