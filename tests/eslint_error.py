"""eslint_error.py < stderr of the eslint command: the message of the fatal error it printed, as
veslint prints it after `veslint: <configuration>: `. The command prints a heading, its version and
either the text of a message template or the stack of the error (its name, its message and the
frames)."""
import re, sys

text = sys.stdin.read()
heading = re.match(r"\nOops! Something went wrong! :\(\n\nESLint: [^\n]+\n\n", text)
if not heading:
    sys.exit("not a fatal error of the eslint command:\n" + text)
body = text[heading.end():]
frames = body.find("\n    at ")
if frames >= 0:
    body = re.sub(r"^[A-Za-z]*Error: ", "", body[:frames]) + "\n"
sys.stdout.write(body)
