import std/[parseopt, os, strutils]

# Swappable writers export
type Writer* = proc (s: string)

# Base command providing writer hooks
type PathxCommand* = ref object of RootObj
  outWriter*: Writer
  errWriter*: Writer

type PathOp = enum
  Absolute,
  Parent,
  Name,
  Stem,
  RootStem,
  Extension,
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
    let ext = base[dot..^1]
    exts.add(ext)          # first added is the last extension
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
  self.output("""
Usage: pathx [OPTIONS] <paths...>
Chain short flags to apply successive transformations to each path.

Flags:
  -a, --absolute      Make path absolute
  -p, --parent        Replace with parent directory
  -n, --name          Replace with final path component (file/dir name)
  -s, --stem          Filename without final extension (filename.tar from filename.tar.gz)
  -S, --root-stem     Filename without any extensions (filename from filename.tar.gz)
  -e, --extension     Final extension only (e.g. .gz)
  -E, --extensions    Full extension chain (e.g. .tar.gz)
  --help              Show this help

Example:
  pathx -appn ./foo/../bar/file.tar.gz
""")

proc pathx*(self: PathxCommand, args: seq[string]): int =
  var positionals: seq[string]
  var optParser = initOptParser(args)
  var ops: seq[PathOp]

  for kind, key, val in optParser.getopt():
    case kind
    of cmdArgument:
      positionals = @[key] & optParser.remainingArgs
      break
    of cmdLongOption, cmdShortOption:
      case key
      of "help":
        self.usage()
        return 0
      of "a", "absolute":
        ops.add(Absolute)
      of "p", "parent":
        ops.add(Parent)
      of "n", "name":
        ops.add(Name)
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
    self.usage()
    return 1

  for p in positionals:
    var outPath = p
    for op in ops:
      case op
      of Absolute:
        outPath = absolutePath(outPath)
      of Parent:
        outPath = parentDir(outPath)
      of Name:
        outPath = lastPathPart(outPath)
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

when isMainModule:
  import os
  var cmd = PathxCommand()
  var args = commandLineParams()
  quit(cmd.pathx(args))
