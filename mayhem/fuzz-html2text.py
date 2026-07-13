#!/usr/bin/env python3
# Atheris (libFuzzer) harness for html2text: feed fuzzed strings through the
# html2text.html2text() HTML -> Markdown conversion path (same code path as the
# historical `convert` target).
import sys
import warnings

# html2text.py (py2-era code) emits SyntaxWarnings at import; they pollute the
# libFuzzer output banner and break Mayhem's target sanity check.
warnings.simplefilter("ignore")

import atheris

# Pre-import html2text's (large) stdlib import closure so instrument_imports only
# instruments the project module itself — instrumenting the whole closure made
# startup slow enough to trip Mayhem's option-print sanity timeout, and stdlib
# coverage is noise anyway.
import html.entities  # noqa: F401
import html.parser  # noqa: F401
import optparse  # noqa: F401
import urllib.parse  # noqa: F401
import urllib.request  # noqa: F401

with atheris.instrument_imports():
    import html2text


@atheris.instrument_func
def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    in_str = fdp.ConsumeString(128)
    html2text.html2text(in_str)


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
