import std/[unittest, asyncdispatch, os, options, json, strutils, tables,
            strscans, strformat, osproc, streams]
import .. / src / nimlsppkg / baseprotocol
include .. / src / nimlsppkg / messages

let
  nimlsp = parentDir(parentDir(currentSourcePath())) / "nimlsp"
  p = startProcess(nimlsp, options = {})

proc writeData(data: JsonNode) =
  assert p.running, "NimLSP has crashed"
  p.inputStream.sendJson(data)

proc sendMessage(name: string, params: JsonNode): JsonNode =
  ## Sends a message to the LSP server and returns
  ## the response.
  # Send the request then read back the response
  RequestMessage.create("2.0", 0, name, some(params)).JsonNode.writeData()
  result = p.outputStream.readFrame().parseJson()
  checkpoint $result

proc sendNotification(name: string, params: JsonNode) =
  ## Sends a notification to the LSP server
  NotificationMessage.create("2.0", name, some(params)).JsonNode.writeData()


# To make writing the tests easier we parse in the document
# and then store all the markers (Like testament markers). The system
# isn't very sophisticated but means lines can be rearranged
# without issue
const
  testDir = currentSourcePath().parentDir()
  exampleFilePath = testDir / "example.nim"
  exampleFileURI = "file://" & exampleFilePath
  exampleFile = readFile(exampleFilePath)
  exampleLines = exampleFile.splitLines()
var
  markers: Table[string, Position] # Store positions of markers
  isMarker = false # Means that the current line is a marker

for i in 0..<exampleLines.len:
  let line = exampleLines[i]
  if not isMarker:
    isMarker = line.endsWith("#[ Marker")
    continue
  isMarker = false
  let (ok, varName) = line.scanTuple("$s^$s$+ ]#")
  if not ok:
    raise (ref ValueError)(msg: fmt"Invalid marker at line {i + 1}")
  # Just so we don't accidently write a marker twice
  if varName in markers:
    raise (ref KeyError)(msg: fmt"{varName} already in use at {markers[varName]}")
  # Also add the range of the symbol
  let marker = line.find("^")
  markers[varName] = Position.create(line = i - 1, character = marker)

suite "Nim LSP basic operation":
  test "Nim LSP can be initialised":
    var ir = create(InitializeParams,
        processId = getCurrentProcessId(),
        rootPath = none(string),
        rootUri = "file://" & testDir,
        initializationOptions = none(JsonNode),
        capabilities = create(ClientCapabilities,
          workspace = none(WorkspaceClientCapabilities),
          textDocument = none(TextDocumentClientCapabilities),
          experimental = none(JsonNode)
        ),
        trace = none(string),
        workspaceFolders = none(seq[WorkspaceFolder])
      ).JsonNode
    var message = "initialize".sendMessage(ir)
    if message.isValid(ResponseMessage):
      var data = ResponseMessage(message)
      check data["id"].getInt == 0
      check data["error"].isNone()
      echo data["result"]
    else:
      check false

    echo message

# Open the example for rest of tests
block:
  "textDocument/didOpen".sendNotification(
    DidOpenTextDocumentParams.create(
      TextDocumentItem.create(
        uri = exampleFileURI,
        languageId = "nim",
        version = 0,
        text = exampleFile
      )
    ).JsonNode)

func symRange(pos: Position): JsonNode =
  ## Returns the range of a symbol at a position
  let p = pos.JsonNode
  # Just use the line of the position, symbols
  # can't go across lines so we are safe
  let
    lineNum = p["line"].getInt()
    line = exampleLines[lineNum]
  var
    start = p["character"].getInt()
    finish = p["character"].getInt
  # Find the end of the symbol
  while finish < line.len and line[finish] in IdentChars:
    inc finish
  # Find the end
  while start > 0 and line[start - 1] in IdentChars:
    dec start
  result = %*{
    "start": {"line": lineNum, "character": start},
    "end": {"line": lineNum, "character": finish}
  }

suite "Renaming":
  test "Can rename variable":
    const varLen = "x".len
    let resp = "textDocument/rename".sendMessage(
      RenameParams.create(
        textDocument = TextDocumentIdentifier.create(exampleFileURI),
        newName = "foo",
        position = markers["rename.variableInit"]
      ).JsonNode
    )
    let changes = resp["result"]["changes"][exampleFileURI].mapIt(it["range"])
    check changes.len == 2
    check markers["rename.variableInit"].symRange() in changes
    check markers["rename.variableUse"].symRange() in changes

p.terminate()
