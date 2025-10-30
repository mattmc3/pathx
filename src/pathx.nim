# https://fishshell.com/docs/current/cmds/path.html
# https://zsh.sourceforge.io/Doc/Release/Expansion.html#Modifiers

import std/parseopt
import std/os except normalizePath
import std/strutils

# Swappable writers export
type Writer* = proc(s: string)

# Base command providing writer hooks
type PathxCommand* = ref object of RootObj
  outWriter*: Writer
  errWriter*: Writer

type ModifyOp = enum
  Normalize
  Dirname
  Basename
  Stem
  RootStem
  Extension
  Extensions

proc output*(self: PathxCommand, s: string) =
  if self.outWriter == nil:
    stdout.write(s)
  else:
    self.outWriter(s)

proc outerr*(self: PathxCommand, s: string) =
  if self.errWriter == nil:
    stderr.write(s)
  else:
    self.errWriter(s)

# Helpers for extension/stem handling
proc splitAllExts(file: string): (string, seq[string]) =
  # Correctly gather all extensions without misusing splitFile (which returns dir,name,ext)
  var base = file
  var exts: seq[string] = @[]
  while true:
    let dot = base.rfind('.')
    if dot <= 0: # no dot or leading dot (hidden file) -> stop
      break
    let ext = base[dot ..^ 1]
    exts.add(ext) # first added is the last extension
    base = base[0 ..< dot]
  (base, exts)

proc rootStemOf(path: string): string =
  let (_, file) = splitPath(path)
  if file.len == 0:
    return ""
  let (root, _) = splitAllExts(file)
  root

proc stemOf(path: string): string =
  let (_, file) = splitPath(path)
  if file.len == 0:
    return ""
  let (root, exts) = splitAllExts(file)
  if exts.len == 0:
    return file
  if exts.len == 1:
    return root
  result = root
  for i in countdown(exts.high, 1):
    result.add(exts[i])

proc lastExtOf(path: string): string =
  let (_, file) = splitPath(path)
  if file.len == 0:
    return ""
  let (_, exts) = splitAllExts(file)
  if exts.len == 0:
    ""
  else:
    exts[0]

proc allExtsOf(path: string): string =
  let (_, file) = splitPath(path)
  if file.len == 0:
    return ""
  let (_, exts) = splitAllExts(file)
  if exts.len == 0:
    ""
  else:
    var chain = ""
    for i in countdown(exts.high, 0):
      chain.add(exts[i])
    chain

proc usage*(self: PathxCommand) =
  self.output(
    """
Usage: pathx <command> [ARGS]

Commands:
  modify    Apply path transformations

Use 'pathx modify --help' for detailed options.
"""
  )

proc modifyUsage(self: PathxCommand) =
  self.output(
    """
Usage: pathx modify [OPTIONS] <paths...>
Chain short flags to apply successive transformations to each path.

Flags:
  -n, --normalize     Normalize path (make absolute)
  -d, --dirname       Replace with parent directory
  -b, --basename      Replace with final path component (file/dir name)
  -s, --stem          Filename without final extension (name.tar from name.tar.gz)
  -S, --root-stem     Filename without any extensions (name from name.tar.gz)
  -e, --extension     Final extension only (eg: .gz)
  -E, --extensions    Full extension chain (eg: .tar.gz)
  --help              Show this help

Example:
  pathx modify -nddb ./foo/../bar/file.tar.gz
"""
  )

# Thin wrappers to match op naming while delegating to std/os
proc normalizePath(path: string): string =
  absolutePath(path)

proc dirnameOf(path: string): string =
  parentDir(path)

proc basenameOf(path: string): string =
  lastPathPart(path)

proc modify*(self: PathxCommand, args: seq[string]): int =
  var positionals: seq[string]
  var optParser = initOptParser(args)
  var ops: seq[ModifyOp]

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      positionals = @[key] & optParser.remainingArgs
      break
    of cmdLongOption, cmdShortOption:
      case key
      of "help":
        self.modifyUsage()
        return 0
      of "n", "normalize":
        ops.add(Normalize)
      of "d", "dirname":
        ops.add(Dirname)
      of "b", "basename":
        ops.add(Basename)
      of "s", "stem":
        ops.add(Stem)
      of "S", "root-stem":
        ops.add(RootStem)
      of "e", "extension":
        ops.add(Extension)
      of "E", "extensions":
        ops.add(Extensions)
      of "":
        positionals = optParser.remainingArgs
        break
      else:
        let prefix = (if kind == cmdShortOption: "-" else: "--")
        self.outerr("contains: Unknown option " & prefix & key & "\n")
        return 2
    of cmdEnd:
      break

  if positionals.len == 0:
    self.outerr("contains: No paths provided.\n")
    self.modifyUsage()
    return 1

  for p in positionals:
    var outPath = p
    for op in ops:
      case op
      of Normalize:
        outPath = normalizePath(outPath)
      of Dirname:
        outPath = dirnameOf(outPath)
      of Basename:
        outPath = basenameOf(outPath)
      of Stem:
        outPath = stemOf(outPath)
      of RootStem:
        outPath = rootStemOf(outPath)
      of Extension:
        outPath = lastExtOf(outPath)
      of Extensions:
        outPath = allExtsOf(outPath)
      else:
        raise newException(ValueError, "Unhandled PathOp: " & $op)
    self.output(outPath & "\n")

  return 0

proc pathx*(self: PathxCommand, args: seq[string]): int =
  if args.len == 0:
    self.usage()
    return 1

  let sub = args[0]
  case sub
  of "help", "--help", "-h":
    self.usage()
    return 0
  of "modify":
    return self.modify(args[1 .. ^1])
  else:
    if sub.len > 0 and sub[0] == '-':
      return self.modify(args)
    self.outerr("contains: Unknown command '" & sub & "'\n")
    self.usage()
    return 2

when isMainModule:
  import os
  var cmd = PathxCommand()
  var args = commandLineParams()
  quit(cmd.pathx(args))
