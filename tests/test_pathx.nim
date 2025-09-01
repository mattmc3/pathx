import std/[unittest, strutils]
import ../src/pathx

# Helper to run pathx and capture stdout/stderr
proc runPathx(args: seq[string]): tuple[code: int, outp: string, err: string] =
  var outBuf = ""
  var errBuf = ""
  proc ow(s: string) = outBuf.add(s)
  proc ew(s: string) = errBuf.add(s)
  var cmd = PathxCommand(outWriter: ow, errWriter: ew)
  result.code = cmd.pathx(args)
  result.outp = outBuf
  result.err = errBuf

suite "pathx basic operations":
  test "requires at least one path":
    let (code, _, err) = runPathx(@["-a"]) # no positional
    check code != 0
    check err.contains("No paths provided")

  test "absolute + parent + name chain":
    # -apn on foo/bar/file.txt -> absolute -> parent (foo/bar) -> name (bar)
    let (code, outp, _) = runPathx(@["-apn", "foo/bar/file.txt"])
    check code == 0
    let lines = outp.strip.splitLines
    check lines.len == 1
    check lines[0] == "bar"

  test "stem vs root-stem":
    let (codeS, outS, _) = runPathx(@["-s", "dir/file.tar.gz"]) # stem -> file.tar
    let (codeR, outR, _) = runPathx(@["-S", "dir/file.tar.gz"]) # root-stem -> file
    check codeS == 0 and codeR == 0
    check outS.strip == "file.tar"
    check outR.strip == "file"

  test "extension vs extensions":
    let (codeE, outE, _) = runPathx(@["-e", "a/b/c.tar.gz"])
    let (codeEE, outEE, _) = runPathx(@["-E", "a/b/c.tar.gz"])
    check codeE == 0 and codeEE == 0
    check outE.strip == ".gz"
    check outEE.strip == ".tar.gz"

  test "parent then extension becomes empty":
    # -pe: parent removes filename, extension of directory is empty
    let (code, outp, _) = runPathx(@["-pe", "foo/bar.txt"])
    check code == 0
    check outp == "\n"  # single empty line

  test "multiple positionals processed independently":
    let (code, outp, _) = runPathx(@["-e", "x/file.one.two", "y/another.txt", "plain"])
    check code == 0
    let lines = outp.splitLines
    check lines[0] == ".two"
    check lines[1] == ".txt"
    check lines[2] == ""  # no extension

  test "chained stem then extension on multi-ext file":
    # -se: stem first (remove final extension) then extension of remaining chain
    # file.tar.gz -> stem => file.tar ; extension => .tar
    let (code, outp, _) = runPathx(@["-se", "file.tar.gz"])
    check code == 0
    check outp.strip == ".tar"

  test "chained root-stem then extension on multi-ext file":
    # -Se: root-stem => file ; extension => (none) => empty line
    let (code, outp, _) = runPathx(@["-Se", "file.tar.gz"])
    check code == 0
    check outp == "\n"
